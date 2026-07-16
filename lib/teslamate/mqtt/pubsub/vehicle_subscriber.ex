defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.RuntimeHealth
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles

  defstruct [:car_id, :last_values, :deps, :namespace, mqtt_generation: 0]
  alias __MODULE__, as: State

  def child_spec(arg) do
    %{
      id: :"#{__MODULE__}#{Keyword.fetch!(arg, :car_id)}",
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @do_not_retain ~w(healthy)a

  # Clears previously retained messages for topics that should not be retained
  # This ensures backward compatibility by cleaning up stale retained messages
  # from installations before PR #4817: https://github.com/teslamate-org/teslamate/pull/4817
  defp clear_retained(car_id, namespace, publisher) do
    Enum.each(@do_not_retain, fn key ->
      topic =
        ["teslamate", namespace, "cars", car_id, key]
        |> Enum.reject(&is_nil(&1))
        |> Enum.join("/")

      call(publisher, :publish, [topic, "", [retain: true, qos: 1]])
    end)
  end

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    namespace = Keyword.fetch!(opts, :namespace)

    deps = %{
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      publisher: Keyword.get(opts, :deps_publisher, Publisher),
      runtime_health: Keyword.get(opts, :deps_runtime_health, RuntimeHealth)
    }

    :ok = call(deps.vehicles, :subscribe_to_summary, [car_id])
    :ok = call(deps.runtime_health, :subscribe_mqtt, [])
    :ok = clear_retained(car_id, namespace, deps.publisher)

    mqtt_snapshot = call(deps.runtime_health, :mqtt_snapshot, [])

    mqtt_generation =
      if mqtt_snapshot.status == :ok do
        send(self(), {:mqtt_reconnected, mqtt_snapshot.generation})
        nil
      else
        mqtt_snapshot.generation
      end

    {:ok,
     %State{
       car_id: car_id,
       namespace: namespace,
       deps: deps,
       mqtt_generation: mqtt_generation
     }}
  end

  @publish_if_nil ~w(charge_energy_added charger_actual_current charger_phases
                       charger_power charger_voltage scheduled_charging_start_time
                       time_to_full_charge shift_state geofence trim_badging)a

  @impl true
  def handle_info(%Summary{} = summary, %State{} = state) do
    state = reconcile_mqtt_generation(state)
    publish_summary(summary, state)
  end

  def handle_info({:mqtt_reconnected, generation}, %State{} = state) do
    mqtt_snapshot = current_mqtt_snapshot(state)

    if mqtt_snapshot.status == :ok and mqtt_snapshot.generation == generation and
         generation != state.mqtt_generation do
      state = %{state | last_values: nil, mqtt_generation: generation}

      case current_summary(state) do
        %Summary{} = summary -> publish_summary(summary, state)
        _other -> {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp publish_summary(%Summary{} = summary, %State{} = state) do
    values =
      %{}
      |> add_simple_values(summary)
      |> add_car_latitude_longitude(summary)
      |> add_geofence(summary)
      |> add_active_route(summary)

    {last_values, result} = publish_values(values, state)
    :ok = call(state.deps.runtime_health, :record_mqtt_publish, [state.car_id, result])
    {:noreply, %{state | last_values: last_values}}
  end

  defp publish_values(values, state) do
    last_values = state.last_values || %{}

    values
    |> Stream.reject(&match?({_key, :unknown}, &1))
    |> Stream.filter(fn {key, value} ->
      ((key in @publish_if_nil or value != nil) and
         (not Map.has_key?(last_values, key) or Map.get(last_values, key) != value)) or
        key in @do_not_retain
    end)
    |> Task.async_stream(fn entry -> {entry, publish(entry, state)} end,
      max_concurrency: 10,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce({last_values, 0}, fn
      {:ok, {{key, value}, :ok}}, {acc, failures} ->
        {Map.put(acc, key, value), failures}

      {:ok, {_entry, reason}}, {acc, failures} ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")
        {acc, failures + 1}

      {:exit, reason}, {acc, failures} ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")
        {acc, failures + 1}
    end)
    |> then(fn
      {values, 0} -> {values, :ok}
      {values, _failures} -> {values, {:error, :publish_failed}}
    end)
  end

  @simple_values ~w(
    display_name state since healthy latitude longitude heading battery_level charging_state usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km charge_energy_added
    speed outside_temp inside_temp is_climate_on is_preconditioning locked sentry_mode
    plugged_in scheduled_charging_start_time charge_limit_soc charger_power windows_open
    driver_front_window_open driver_rear_window_open passenger_front_window_open passenger_rear_window_open
    doors_open driver_front_door_open driver_rear_door_open passenger_front_door_open passenger_rear_door_open
    odometer shift_state charge_port_door_open time_to_full_charge charger_phases
    charger_actual_current charger_voltage version update_available update_version is_user_present
    model trim_badging exterior_color wheel_type spoiler_type trunk_open frunk_open elevation power
    charge_current_request charge_current_request_max tpms_pressure_fl tpms_pressure_fr tpms_pressure_rl tpms_pressure_rr
    tpms_soft_warning_fl tpms_soft_warning_fr tpms_soft_warning_rl tpms_soft_warning_rr climate_keeper_mode center_display_state
    service_mode sun_roof_state sun_roof_installed sun_roof_percent_open download_perc install_perc
  )a

  defp add_simple_values(map, %Summary{} = summary) do
    Map.merge(map, Map.take(summary, @simple_values))
  end

  defp add_car_latitude_longitude(map, %Summary{} = summary) do
    lat_lng =
      case {summary.latitude, summary.longitude} do
        {nil, _} -> nil
        {_, nil} -> nil
        {%Decimal{} = lat, %Decimal{} = lon} -> {Decimal.to_float(lat), Decimal.to_float(lon)}
        {lat, lon} -> {lat, lon}
      end

    case lat_lng do
      nil ->
        map

      {lat, lon} ->
        location =
          %{
            latitude: lat,
            longitude: lon
          }
          |> Jason.encode!()

        Map.put(map, :location, location)
    end
  end

  defp add_geofence(map, %Summary{} = summary) do
    case summary.geofence do
      nil ->
        Map.put(map, :geofence, Application.get_env(:teslamate, :default_geofence))

      geofence ->
        Map.put(map, :geofence, geofence.name)
    end
  end

  defp add_active_route(map, %Summary{active_route_destination: nil}) do
    error =
      %{
        error: "No active route available"
      }
      |> Jason.encode!()

    Map.merge(
      map,
      %{
        active_route_destination: "nil",
        active_route_latitude: "nil",
        active_route_longitude: "nil",
        active_route: error
      }
    )
  end

  defp add_active_route(map, %Summary{} = summary) do
    location =
      %{
        latitude: summary.active_route_latitude,
        longitude: summary.active_route_longitude
      }

    active_route =
      %{
        destination: summary.active_route_destination,
        energy_at_arrival: summary.active_route_energy_at_arrival,
        miles_to_arrival: summary.active_route_miles_to_arrival,
        minutes_to_arrival: summary.active_route_minutes_to_arrival,
        traffic_minutes_delay: summary.active_route_traffic_minutes_delay,
        location: location,
        error: nil
      }
      |> Jason.encode!()

    Map.merge(map, %{
      active_route_destination: summary.active_route_destination,
      active_route_latitude: summary.active_route_latitude,
      active_route_longitude: summary.active_route_longitude,
      active_route: active_route
    })
  end

  defp publish({key, value}, %State{car_id: car_id, namespace: namespace, deps: deps}) do
    topic =
      ["teslamate", namespace, "cars", car_id, key]
      |> Enum.reject(&is_nil(&1))
      |> Enum.join("/")

    call(deps.publisher, :publish, [
      topic,
      to_str(value),
      [retain: key not in @do_not_retain, qos: 1]
    ])
  end

  defp to_str(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp to_str(value), do: to_string(value)

  defp current_summary(%State{car_id: car_id, deps: deps}) do
    call(deps.vehicles, :summary, [car_id])
  catch
    :exit, reason ->
      Logger.warning("Could not republish MQTT snapshot: #{inspect(reason)}")
      nil
  end

  defp reconcile_mqtt_generation(%State{} = state) do
    case current_mqtt_snapshot(state) do
      %{status: :ok, generation: generation}
      when not is_nil(generation) and generation != state.mqtt_generation ->
        %{state | last_values: nil, mqtt_generation: generation}

      _snapshot ->
        state
    end
  end

  defp current_mqtt_snapshot(%State{deps: deps}) do
    call(deps.runtime_health, :mqtt_snapshot, [])
  catch
    :exit, _reason -> %{status: :unavailable, generation: nil}
  end
end
