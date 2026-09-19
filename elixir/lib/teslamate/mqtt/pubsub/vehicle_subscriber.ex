defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Mqtt.PubSub.HomeAssistant
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles

  @discovery_retry_initial_delay :timer.seconds(5)
  @discovery_retry_max_delay :timer.minutes(5)

  defstruct [
    :car_id,
    :last_values,
    :deps,
    :namespace,
    :discovery,
    :discovery_base_url,
    :discovery_prefix,
    :migration_delay,
    :discovery_device,
    :discovery_pending_summary,
    :discovery_pending_device,
    :discovery_retry_delay,
    :discovery_retry_timer,
    :discovery_retry_token
  ]

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

      case call(publisher, :publish, [topic, "", [retain: true, qos: 1]]) do
        :ok ->
          :ok

        error ->
          Logger.warning("MQTT retained cleanup failed for #{topic}: #{inspect(error)}")
      end
    end)
  end

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    # :namespace is absent (not nil) when MQTT_NAMESPACE is unset, since
    # Mqtt.init drops nil options before starting PubSub.
    namespace = Keyword.get(opts, :namespace)

    deps = %{
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      publisher: Keyword.get(opts, :deps_publisher, Publisher)
    }

    discovery = Keyword.get(opts, :discovery, false)
    discovery_base_url = Keyword.get(opts, :discovery_base_url)
    discovery_prefix = Keyword.get(opts, :discovery_prefix)
    migration_delay = Keyword.get(opts, :migration_delay)

    :ok = call(deps.vehicles, :subscribe_to_summary, [car_id])

    {:ok,
     %State{
       car_id: car_id,
       namespace: namespace,
       deps: deps,
       discovery: discovery,
       discovery_base_url: discovery_base_url,
       discovery_prefix: discovery_prefix,
       migration_delay: migration_delay
     }, {:continue, :clear_retained}}
  end

  @impl true
  def handle_continue(
        :clear_retained,
        %State{car_id: car_id, namespace: namespace, deps: deps} = state
      ) do
    clear_retained(car_id, namespace, deps.publisher)
    clear_discovery(state)
    {:noreply, state}
  end

  defp clear_discovery(%State{discovery: false, deps: deps} = state) do
    case HomeAssistant.clear(state.car_id, discovery_opts(state), deps.publisher) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("MQTT HA discovery cleanup failed: #{inspect(reason)}")
    end
  end

  defp clear_discovery(%State{}), do: :ok

  @publish_if_nil ~w(charge_energy_added charger_actual_current charger_phases
                       charger_power charger_voltage scheduled_charging_start_time
                       time_to_full_charge shift_state geofence trim_badging)a

  @impl true
  def handle_info(%Summary{} = summary, %State{} = state) do
    values =
      %{}
      |> add_simple_values(summary)
      |> add_software_update(state.last_values)
      |> add_car_latitude_longitude(summary)
      |> add_geofence(summary)
      |> add_active_route(summary)

    last_values = publish_values(values, state)

    state = maybe_publish_discovery(summary, state)

    {:noreply, %{state | last_values: last_values}}
  end

  def handle_info(
        {:retry_discovery, token},
        %State{
          discovery: true,
          discovery_retry_token: token,
          discovery_pending_summary: %Summary{} = summary,
          discovery_pending_device: device
        } = state
      ) do
    state = %{
      state
      | discovery_pending_summary: nil,
        discovery_pending_device: nil,
        discovery_retry_timer: nil,
        discovery_retry_token: nil
    }

    {:noreply, publish_or_schedule_discovery(summary, device, state)}
  end

  def handle_info({:retry_discovery, _stale_token}, %State{} = state), do: {:noreply, state}

  defp maybe_publish_discovery(%Summary{} = summary, %State{discovery: true} = state) do
    opts = discovery_opts(state)
    device = HomeAssistant.device(summary, opts)

    cond do
      device == state.discovery_device ->
        reset_discovery_retry(state)

      is_reference(state.discovery_retry_timer) ->
        %{
          state
          | discovery_pending_summary: summary,
            discovery_pending_device: device
        }

      true ->
        publish_or_schedule_discovery(summary, device, state)
    end
  end

  defp maybe_publish_discovery(%Summary{}, %State{} = state), do: state

  defp publish_or_schedule_discovery(%Summary{} = summary, device, %State{} = state) do
    case publish_discovery(summary, discovery_opts(state), state) do
      :ok ->
        state
        |> reset_discovery_retry()
        |> Map.put(:discovery_device, device)

      {:error, reason} ->
        schedule_discovery_retry(summary, device, reason, state)
    end
  end

  defp publish_discovery(
         %Summary{} = summary,
         opts,
         %State{discovery_device: nil, deps: deps}
       ) do
    HomeAssistant.migrate(summary, opts, deps.publisher)
  end

  defp publish_discovery(%Summary{} = summary, opts, %State{deps: deps}) do
    HomeAssistant.publish(summary, opts, deps.publisher)
  end

  defp schedule_discovery_retry(%Summary{} = summary, device, reason, %State{} = state) do
    delay = next_discovery_retry_delay(state.discovery_retry_delay)
    token = make_ref()
    timer = Process.send_after(self(), {:retry_discovery, token}, delay)

    Logger.warning(
      "MQTT HA discovery publishing failed: #{inspect(reason)}; retrying in #{div(delay, 1_000)}s"
    )

    %{
      state
      | discovery_pending_summary: summary,
        discovery_pending_device: device,
        discovery_retry_delay: delay,
        discovery_retry_timer: timer,
        discovery_retry_token: token
    }
  end

  defp next_discovery_retry_delay(nil), do: @discovery_retry_initial_delay

  defp next_discovery_retry_delay(delay) do
    min(delay * 2, @discovery_retry_max_delay)
  end

  defp reset_discovery_retry(%State{discovery_retry_timer: timer} = state) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    %{
      state
      | discovery_pending_summary: nil,
        discovery_pending_device: nil,
        discovery_retry_delay: nil,
        discovery_retry_timer: nil,
        discovery_retry_token: nil
    }
  end

  defp discovery_opts(%State{} = state) do
    [
      car_id: state.car_id,
      namespace: state.namespace,
      base_url: state.discovery_base_url,
      discovery_prefix: state.discovery_prefix,
      migration_delay: state.migration_delay
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
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
    |> Enum.reduce(last_values, fn
      {:ok, {{key, value}, :ok}}, acc ->
        Map.put(acc, key, value)

      {:ok, {_entry, reason}}, acc ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")
        acc

      {:exit, reason}, acc ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")
        acc
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

  defp add_software_update(map, last_values) do
    values =
      (last_values || %{})
      |> Map.merge(Map.reject(map, fn {_key, value} -> value in [nil, :unknown] end))

    with version when is_binary(version) <- values[:version],
         update_available when is_boolean(update_available) <- values[:update_available],
         latest_version when is_binary(latest_version) <-
           if(update_available, do: values[:update_version], else: version) do
      software_update =
        Jason.encode!(%{
          installed_version: version,
          latest_version: latest_version
        })

      Map.put(map, :software_update, software_update)
    else
      _value -> map
    end
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
end
