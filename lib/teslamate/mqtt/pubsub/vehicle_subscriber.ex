defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Vehicles

  defstruct [:car_id, :last_values, :deps, :namespace]
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

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    namespace = Keyword.fetch!(opts, :namespace)

    deps = %{
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      publisher: Keyword.get(opts, :deps_publisher, Publisher)
    }

    :ok = call(deps.vehicles, :subscribe_to_summary, [car_id])

    {:ok, %State{car_id: car_id, namespace: namespace, deps: deps}}
  end

  @always_published ~w(charge_energy_added charger_actual_current charger_phases
                       charger_power charger_voltage scheduled_charging_start_time
                       time_to_full_charge shift_state geofence trim_badging)a

  @impl true
  def handle_info(%Summary{} = summary, state) do
    values =
      %{}
      |> add_simple_values(summary)
      |> add_car_latitude_longitude(summary)
      |> add_geofence(summary)
      |> add_active_route(summary)

    publish_values(values, state)
    {:noreply, %State{state | last_values: values}}
  end

  defp publish_values(values, %State{last_values: values}) do
    nil
  end

  defp publish_values(values, state) do
    values
    |> Stream.reject(&match?({_key, :unknown}, &1))
    |> Stream.filter(fn {key, value} ->
      (key in @always_published or value != nil) and
        (state.last_values == nil or Map.get(state.last_values, key) != value)
    end)
    |> Task.async_stream(&publish(&1, state),
      max_concurrency: 10,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {_, reason} when reason != :ok ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")

      _ok ->
        nil
    end)
  end

  @simple_values ~w(
    display_name state since healthy latitude longitude heading battery_level charging_state usable_battery_level
    ideal_battery_range_km est_battery_range_km rated_battery_range_km charge_energy_added
    speed outside_temp inside_temp is_climate_on is_preconditioning locked sentry_mode
    plugged_in scheduled_charging_start_time charge_limit_soc charger_power windows_open doors_open
    odometer shift_state charge_port_door_open time_to_full_charge charger_phases
    charger_actual_current charger_voltage version update_available update_version is_user_present
    model trim_badging exterior_color wheel_type spoiler_type trunk_open frunk_open elevation power
    charge_current_request charge_current_request_max tpms_pressure_fl tpms_pressure_fr tpms_pressure_rl tpms_pressure_rr
    tpms_soft_warning_fl tpms_soft_warning_fr tpms_soft_warning_rl tpms_soft_warning_rr climate_keeper_mode
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

    call(deps.publisher, :publish, [topic, to_str(value), [retain: true, qos: 1]])
  end

  defp to_str(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp to_str(value), do: to_string(value)
end
