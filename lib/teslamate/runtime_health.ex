defmodule TeslaMate.RuntimeHealth do
  @moduledoc """
  Tracks redacted, in-memory liveness for the vehicle API, streaming API and MQTT.

  Runtime health intentionally resets on application restart. Persisting these values
  would make old connection state look current.
  """

  use GenServer

  alias TeslaApi.Stream

  @name __MODULE__
  @default_stale_after %{api: :timer.hours(1) |> div(1000), stream: 120, summary: 3600}
  @default_vehicle_expiry :timer.hours(24) |> div(1000)

  defmodule ComponentState do
    @enforce_keys [:status]
    defstruct status: :unknown,
              last_success_at: nil,
              last_failure_at: nil,
              last_event_at: nil,
              consecutive_failures: 0,
              reason: nil,
              retry_at: nil
  end

  defmodule VehicleHealth do
    @enforce_keys [:car_id]
    defstruct car_id: nil,
              logger_state: :unknown,
              last_summary_at: nil,
              last_seen_at: nil,
              api: %ComponentState{status: :unknown},
              stream: %ComponentState{status: :unknown},
              mqtt: %ComponentState{status: :unknown}
  end

  defmodule State do
    defstruct name: nil,
              clock: nil,
              vehicles: %{},
              mqtt: %ComponentState{status: :disabled},
              mqtt_generation: nil,
              stale_after: %{},
              vehicle_expiry_seconds: nil
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  def report(name \\ @name) do
    call_or(name, :report, fn -> {:error, :unavailable} end)
  end

  def public_report(name \\ @name) do
    call_or(name, :public_report, fn -> {:error, :unavailable} end)
  end

  def snapshot(name \\ @name) do
    call_or(name, :snapshot, fn -> {:error, :unavailable} end)
  end

  def mqtt_generation(name \\ @name) do
    mqtt_snapshot(name).generation
  end

  def mqtt_snapshot(name \\ @name) do
    call_or(name, :mqtt_snapshot, fn -> %{status: :unavailable, generation: nil} end)
  end

  def subscribe_mqtt(name \\ @name) do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, mqtt_topic(name))
  end

  def record_api(car_id, result), do: record_api(@name, car_id, result)

  def record_api(name, car_id, result) do
    cast_if_running(name, {:api, car_id, normalize_api_result(result)})
  end

  def record_stream(car_id, event), do: record_stream(@name, car_id, event)

  def record_stream(name, car_id, event) do
    cast_if_running(name, {:stream, car_id, normalize_stream_event(event)})
  end

  def record_summary(car_id, logger_state), do: record_summary(@name, car_id, logger_state)

  def record_summary(name, car_id, logger_state) do
    cast_if_running(name, {:summary, car_id, normalize_logger_state(logger_state)})
  end

  def remove_vehicle(car_id), do: remove_vehicle(@name, car_id)
  def remove_vehicle(name, car_id), do: cast_if_running(name, {:remove_vehicle, car_id})

  def record_mqtt_connection(event), do: record_mqtt_connection(@name, event)

  def record_mqtt_connection(name, event) do
    cast_if_running(name, {:mqtt_connection, normalize_mqtt_connection(event)})
  end

  def record_mqtt_publish(car_id, result), do: record_mqtt_publish(@name, car_id, result)

  def record_mqtt_publish(name, car_id, result) do
    cast_if_running(name, {:mqtt_publish, car_id, normalize_publish_result(result)})
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, &DateTime.utc_now/0)
    mqtt_status = if Keyword.get(opts, :mqtt_enabled, false), do: :unknown, else: :disabled

    stale_after =
      @default_stale_after
      |> Map.merge(opts |> Keyword.get(:stale_after, []) |> Map.new())

    {:ok,
     %State{
       name: Keyword.fetch!(opts, :name),
       clock: clock,
       mqtt: %ComponentState{status: mqtt_status},
       mqtt_generation: new_generation(),
       stale_after: stale_after,
       vehicle_expiry_seconds: Keyword.get(opts, :vehicle_expiry_seconds, @default_vehicle_expiry)
     }}
  end

  @impl true
  def handle_call(:report, _from, state) do
    state = prune_vehicles(state)
    {:reply, render(state), state}
  end

  def handle_call(:public_report, _from, state) do
    state = prune_vehicles(state)
    {:reply, {:ok, render_public(state)}, state}
  end

  def handle_call(:snapshot, _from, state) do
    state = prune_vehicles(state)
    {:reply, state, state}
  end

  def handle_call(:mqtt_snapshot, _from, state) do
    {:reply, %{status: state.mqtt.status, generation: state.mqtt_generation}, state}
  end

  @impl true
  def handle_cast({:summary, car_id, logger_state}, state) do
    now = now(state)

    state =
      update_vehicle(state, car_id, now, fn health ->
        %{health | logger_state: logger_state, last_summary_at: now}
      end)

    {:noreply, state}
  end

  def handle_cast({:api, car_id, signal}, state) do
    now = now(state)

    state =
      update_vehicle(state, car_id, now, fn health ->
        %{health | api: api_state(health.api, signal, now)}
      end)

    {:noreply, state}
  end

  def handle_cast({:stream, car_id, signal}, state) do
    now = now(state)

    state =
      update_vehicle(state, car_id, now, fn health ->
        %{health | stream: stream_state(health.stream, signal, now)}
      end)

    {:noreply, state}
  end

  def handle_cast({:mqtt_publish, car_id, signal}, state) do
    now = now(state)

    state =
      update_vehicle(state, car_id, now, fn health ->
        %{health | mqtt: publish_state(health.mqtt, signal, now)}
      end)

    {:noreply, state}
  end

  def handle_cast({:remove_vehicle, car_id}, state) do
    {:noreply, %{state | vehicles: Map.delete(state.vehicles, car_id)}}
  end

  def handle_cast({:mqtt_connection, event}, state) do
    now = now(state)
    previous_status = state.mqtt.status
    mqtt = mqtt_connection_state(state.mqtt, event, now)

    reconnect? =
      event == :up and previous_status in [:degraded, :down] and mqtt.status == :ok

    state = %{state | mqtt: mqtt}

    state =
      if reconnect? do
        generation = new_generation()
        broadcast_reconnect(state.name, generation)
        %{state | mqtt_generation: generation}
      else
        state
      end

    {:noreply, state}
  end

  defp api_state(component, :success, now), do: succeeded(component, now, now)
  defp api_state(component, {:idle, reason}, now), do: idle(component, now, reason)

  defp api_state(component, {:rate_limited, retry_after}, now) do
    failed(component, now, :rate_limited, retry_at: DateTime.add(now, retry_after, :second))
  end

  defp api_state(component, {:failure, reason}, now), do: failed(component, now, reason)

  defp stream_state(component, {:data, %DateTime{} = observed_at}, now) do
    succeeded(component, now, observed_at)
  end

  defp stream_state(component, :data, now), do: succeeded(component, now, now)
  defp stream_state(component, {:idle, reason}, now), do: idle(component, now, reason)
  defp stream_state(component, {:failure, reason}, now), do: failed(component, now, reason)

  defp stream_state(component, {:down, reason}, now) do
    failed(component, now, reason, status: :down)
  end

  defp stream_state(component, :ignored, _now), do: component

  defp mqtt_connection_state(component, :up, now), do: succeeded(component, now, now)
  defp mqtt_connection_state(component, :down, now), do: failed(component, now, :broker_down)

  defp mqtt_connection_state(component, :terminating, now) do
    failed(component, now, :broker_terminating, status: :down)
  end

  defp mqtt_connection_state(component, :terminated, now) do
    failed(component, now, :client_terminated, status: :down)
  end

  defp mqtt_connection_state(component, :ignored, _now), do: component

  defp publish_state(component, :success, now), do: succeeded(component, now, now)
  defp publish_state(component, :failure, now), do: failed(component, now, :publish_failed)

  defp succeeded(%ComponentState{} = component, now, observed_at) do
    %ComponentState{
      component
      | status: :ok,
        last_success_at: now,
        last_event_at: observed_at,
        consecutive_failures: 0,
        reason: nil,
        retry_at: nil
    }
  end

  defp idle(%ComponentState{} = component, now, reason) do
    %ComponentState{
      component
      | status: :idle,
        last_event_at: now,
        consecutive_failures: 0,
        reason: reason,
        retry_at: nil
    }
  end

  defp failed(%ComponentState{} = component, now, reason, opts \\ []) do
    failures = component.consecutive_failures + 1
    status = Keyword.get(opts, :status, if(failures >= 3, do: :down, else: :degraded))

    %ComponentState{
      component
      | status: status,
        last_failure_at: now,
        consecutive_failures: failures,
        reason: reason,
        retry_at: Keyword.get(opts, :retry_at)
    }
  end

  defp update_vehicle(state, car_id, now, fun) when is_integer(car_id) do
    health = Map.get(state.vehicles, car_id, %VehicleHealth{car_id: car_id})
    health = %{fun.(health) | last_seen_at: now}
    %{state | vehicles: Map.put(state.vehicles, car_id, health)}
  end

  defp update_vehicle(state, _car_id, _now, _fun), do: state

  defp normalize_api_result({:ok, _value}), do: :success
  defp normalize_api_result({:error, :vehicle_unavailable}), do: {:idle, :vehicle_unavailable}

  defp normalize_api_result({:error, :too_many_request, retry_after})
       when is_number(retry_after) do
    {:rate_limited, round(retry_after)}
  end

  defp normalize_api_result({:error, reason}), do: {:failure, api_reason(reason)}
  defp normalize_api_result(_unexpected), do: {:failure, :unexpected_result}

  defp normalize_stream_event(%Stream.Data{time: %DateTime{} = observed_at}),
    do: {:data, observed_at}

  defp normalize_stream_event(%Stream.Data{}), do: :data
  defp normalize_stream_event(:inactive), do: {:idle, :inactive}
  defp normalize_stream_event(:vehicle_offline), do: {:idle, :vehicle_offline}
  defp normalize_stream_event({:liveness, :connected}), do: {:idle, :waiting_for_data}
  defp normalize_stream_event({:liveness, :disconnected}), do: {:idle, :not_expected}
  defp normalize_stream_event({:liveness, :reconnecting}), do: {:failure, :reconnecting}
  defp normalize_stream_event({:liveness, :terminated}), do: {:down, :terminated}
  defp normalize_stream_event(:too_many_disconnects), do: {:failure, :too_many_disconnects}
  defp normalize_stream_event(:tokens_expired), do: {:down, :tokens_expired}
  defp normalize_stream_event(_event), do: :ignored

  defp normalize_mqtt_connection(event) when event in [:up, :down, :terminating, :terminated],
    do: event

  defp normalize_mqtt_connection({:terminated, _reason}), do: :terminated
  defp normalize_mqtt_connection(_event), do: :ignored

  defp normalize_publish_result(:ok), do: :success
  defp normalize_publish_result({:ok, _value}), do: :success
  defp normalize_publish_result(_error), do: :failure

  defp api_reason(:timeout), do: :timeout
  defp api_reason(:unauthorized), do: :unauthorized
  defp api_reason(:not_signed_in), do: :not_signed_in
  defp api_reason(:gateway_error), do: :gateway_error
  defp api_reason(:tokens_expired), do: :tokens_expired
  defp api_reason(_reason), do: :api_error

  defp normalize_logger_state({state, _, _}) when is_atom(state), do: state
  defp normalize_logger_state({state, _}) when is_atom(state), do: state
  defp normalize_logger_state(state) when is_atom(state), do: state
  defp normalize_logger_state(_state), do: :unknown

  defp render(state) do
    generated_at = now(state)
    broker = current_component(state.mqtt, generated_at, nil, state.mqtt.status != :disabled)

    vehicles =
      state.vehicles
      |> Map.values()
      |> Enum.sort_by(& &1.car_id)
      |> Enum.map(&render_vehicle(&1, broker, generated_at, state.stale_after))

    components =
      [
        broker
        | Enum.flat_map(
            vehicles,
            &(Map.take(&1, [:logger, :api, :stream, :mqtt]) |> Map.values())
          )
      ]

    %{
      schema_version: 1,
      generated_at: DateTime.to_iso8601(generated_at),
      status: overall_status(components),
      mqtt: render_component(broker, generated_at),
      mqtt_generation: state.mqtt_generation,
      vehicles: vehicles
    }
  end

  defp render_public(state) do
    report = render(state)
    statuses = Enum.frequencies_by(report.vehicles, & &1.status)

    %{
      schema_version: report.schema_version,
      status: report.status,
      mqtt: %{status: report.mqtt.status},
      vehicles: %{
        total: length(report.vehicles),
        ok: Map.get(statuses, :ok, 0),
        degraded: Map.get(statuses, :degraded, 0)
      }
    }
  end

  defp render_vehicle(health, broker, now, stale_after) do
    logger = summary_component(health.last_summary_at, now, stale_after.summary)
    api = current_component(health.api, now, stale_after.api, true)

    stream_expected? =
      health.stream.status == :ok or health.stream.reason == :waiting_for_data

    stream = current_component(health.stream, now, stale_after.stream, stream_expected?)

    mqtt =
      if broker.status in [:degraded, :down, :disabled] do
        broker
      else
        current_component(health.mqtt, now, nil, true)
      end

    components = [logger, api, stream, mqtt]

    %{
      car_id: health.car_id,
      status: overall_status(components),
      logger_state: health.logger_state,
      last_summary_at: iso8601(health.last_summary_at),
      summary_age_seconds: age_seconds(health.last_summary_at, now),
      logger: render_component(logger, now),
      api: render_component(api, now),
      stream: render_component(stream, now),
      mqtt: render_component(mqtt, now)
    }
  end

  defp summary_component(nil, _now, _stale_after) do
    %ComponentState{status: :degraded, reason: :no_signal}
  end

  defp summary_component(last_summary_at, now, stale_after) do
    component = %ComponentState{
      status: :ok,
      last_success_at: last_summary_at,
      last_event_at: last_summary_at
    }

    current_component(component, now, stale_after, true)
  end

  defp current_component(%ComponentState{status: :unknown} = component, _now, _stale, true) do
    %{component | status: :degraded, reason: :no_signal}
  end

  defp current_component(%ComponentState{} = component, now, stale_after, expected?) do
    stale? =
      expected? and is_integer(stale_after) and
        (component.status == :ok or component.reason == :waiting_for_data) and
        stale?(component.last_event_at, now, stale_after)

    if stale?, do: %{component | status: :degraded, reason: :stale}, else: component
  end

  defp render_component(component, now) do
    %{
      status: component.status,
      last_success_at: iso8601(component.last_success_at),
      last_failure_at: iso8601(component.last_failure_at),
      last_event_at: iso8601(component.last_event_at),
      data_age_seconds: age_seconds(component.last_event_at, now),
      consecutive_failures: component.consecutive_failures,
      reason: component.reason,
      retry_at: iso8601(component.retry_at)
    }
  end

  defp overall_status(components) do
    if Enum.any?(components, &(&1.status in [:degraded, :down])), do: :degraded, else: :ok
  end

  defp prune_vehicles(%State{vehicle_expiry_seconds: expiry} = state)
       when is_integer(expiry) and expiry >= 0 do
    now = now(state)

    vehicles =
      Map.filter(state.vehicles, fn {_car_id, health} ->
        not stale?(health.last_seen_at, now, expiry)
      end)

    %{state | vehicles: vehicles}
  end

  defp prune_vehicles(state), do: state

  defp stale?(nil, _now, _max_age), do: true
  defp stale?(datetime, now, max_age), do: DateTime.diff(now, datetime, :second) > max_age

  defp age_seconds(nil, _now), do: nil
  defp age_seconds(datetime, now), do: max(DateTime.diff(now, datetime, :second), 0)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp now(%State{clock: clock}) when is_function(clock, 0), do: clock.()
  defp now(%State{}), do: DateTime.utc_now()

  defp call_or(name, message, fallback) do
    case GenServer.whereis(name) do
      nil -> fallback.()
      pid -> GenServer.call(pid, message)
    end
  catch
    :exit, _reason -> fallback.()
  end

  defp cast_if_running(name, message) do
    case GenServer.whereis(name) do
      nil -> :ok
      pid -> GenServer.cast(pid, message)
    end
  end

  defp broadcast_reconnect(name, generation) do
    if Process.whereis(TeslaMate.PubSub) do
      Phoenix.PubSub.broadcast(
        TeslaMate.PubSub,
        mqtt_topic(name),
        {:mqtt_reconnected, generation}
      )
    end
  end

  defp new_generation, do: System.unique_integer([:positive, :monotonic])
  defp mqtt_topic(name), do: "#{__MODULE__}:mqtt:#{inspect(name)}"
end
