defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Identification
  alias TeslaMate.{Api, Log}

  alias TeslaApi.Vehicle.State
  alias TeslaApi.{Vehicle, Error}

  import Core.Dependency, only: [call: 3]

  defstruct id: nil,
            car_id: nil,
            vehicle_id: nil,
            last_shift_state: nil,
            last_used: nil,
            sleep_between: %{from: nil, to: nil},
            sudpend_after_idle_min: nil,
            suspend_min: nil,
            deps: %{}

  alias __MODULE__, as: Data

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, [])
  end

  def go_to_sleep(car_id) do
    GenStateMachine.call(car_id, :go_to_sleep, 15_000)
  end

  def wake_up(car_id) do
    GenStateMachine.call(car_id, :wake_up, 15_000)
  end

  @impl true
  def init(opts) do
    %Vehicle{} = vehicle = Keyword.fetch!(opts, :vehicle)

    Logger.info("Found Vehicle '#{vehicle.display_name}'")

    deps = %{
      log: Keyword.get(opts, :log, Log),
      api: Keyword.get(opts, :api, Api)
    }

    {:ok, %Log.Car{id: car_id}} =
      case call(deps.log, :get_car_by_eid, [vehicle.id]) do
        nil ->
          properties = Identification.properties(vehicle)

          call(deps.log, :create_car, [
            %{
              eid: vehicle.id,
              vid: vehicle.vehicle_id,
              model: properties.model,
              efficiency: properties.efficiency
            }
          ])

        car ->
          {:ok, car}
      end

    data = %Data{
      id: vehicle.id,
      car_id: car_id,
      vehicle_id: vehicle.vehicle_id,
      last_used: DateTime.utc_now(),
      sudpend_after_idle_min: Keyword.get(opts, :sudpend_after_idle_min, 15),
      suspend_min: Keyword.get(opts, :suspend_min, 21),
      deps: deps
    }

    {:ok, :start, data, {:next_event, :internal, :fetch}}
  end

  # TODO
  # - /wake_up & /sleep routes
  # - reverse adress lookup
  # - geofecnces
  # - mqtt
  # - indices
  # - cron job which "closes" drives & charging_processes

  @impl true
  def handle_event(event, :fetch, state, data) when event in [:state_timeout, :internal] do
    case fetch(data, expected_state: state) do
      {:ok, %Vehicle{} = vehicle_state} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, {:online, vehicle_state}}}}

      {:ok, :offline} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, :offline}}}

      {:ok, :asleep} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, :asleep}}}

      {:ok, :unknown} ->
        Logger.warn("Error / vehicle_state: :unknown}")

        {:keep_state_and_data, schedule_fetch()}

      {:error, %Error{error: :timeout}} ->
        {:keep_state_and_data, schedule_fetch(5)}

      {:error, %Error{error: error, message: message}} ->
        Logger.warn("Error / #{inspect(error)}: #{message}")

        {:keep_state_and_data, schedule_fetch()}
    end
  end

  ## Update

  ### :start

  def handle_event(:internal, {:update, :asleep}, :start, data) do
    Logger.info("Start / :asleep")

    :ok = call(data.deps.log, :start_state, [data.car_id, :asleep])

    {:next_state, :asleep, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, :offline}, :start, data) do
    Logger.info("Start / :offline")

    :ok = call(data.deps.log, :start_state, [data.car_id, :offline])

    {:next_state, :offline, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :start, data) do
    Logger.info("Start / :online")

    :ok = call(data.deps.log, :start_state, [data.car_id, :online])

    {:next_state, :online, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  ### :online

  def handle_event(:internal, {:update, :offline}, :online, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, :online, data) do
    case vehicle_state do
      %{drive_state: %State.Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Driving / Start")

        {:ok, trip_id} = call(data.deps.log, :start_trip, [data.car_id])
        :ok = insert_position(vehicle_state, data, trip_id: trip_id)

        {:next_state, {:driving, trip_id}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

      %{charge_state: %State.Charge{charging_state: charging_state, time_to_full_charge: t}}
      when charging_state in ["Charging", "Complete"] ->
        Logger.info("Charging / #{t}h left")

        position = create_position(vehicle_state)

        {:ok, charging_process_id} =
          call(data.deps.log, :start_charging_process, [data.car_id, position])

        {:next_state, {:charging, charging_state, charging_process_id},
         %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      _ ->
        try_to_suspend(vehicle_state, data)
    end
  end

  ### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _, _}, _data) do
    Logger.warn("Vehicle went offline while charging")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:charging, last, pid}, data) do
    case {vehicle_state.charge_state.charging_state, last} do
      {"Charging", last_state} ->
        if last_state == "Complete", do: Logger.info("Charging / Restart")

        :ok = insert_charge(pid, vehicle_state, data)

        interval =
          vehicle_state.charge_state
          |> Map.get(:charger_power)
          |> determince_interval()

        {:next_state, {:charging, "Charging", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(interval)}

      {"Complete", "Complete"} ->
        try_to_suspend(vehicle_state, data)

      {"Complete", "Charging"} ->
        energy_added = vehicle_state.charge_state.charge_energy_added
        Logger.info("Charging / Complete / Added #{energy_added}kWh")

        :ok = insert_charge(pid, vehicle_state, data)

        {:next_state, {:charging, "Complete", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch()}

      {charging_state, _} ->
        energy_added = vehicle_state.charge_state.charge_energy_added
        Logger.info("Charging / #{charging_state} / Added #{energy_added}kWh")

        :ok = call(data.deps.log, :close_charging_process, [pid])

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle_state}}}}
    end
  end

  ### :driving

  def handle_event(:internal, {:update, :offline}, {:driving, _trip_id}, _data) do
    Logger.warn("Vehicle went offline while driving")

    {:keep_state_and_data, schedule_fetch(5)}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:driving, trip_id}, data) do
    case vehicle_state.drive_state.shift_state do
      shift_state when shift_state in ["D", "R", "N"] ->
        :ok = insert_position(vehicle_state, data, trip_id: trip_id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      "P" ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(10)}

      nil ->
        Logger.info("Driving / Ended")

        :ok = call(data.deps.log, :close_trip, [trip_id])

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle_state}}}}
    end
  end

  ### :asleep

  def handle_event(:internal, {:update, :asleep}, :asleep, _data) do
    {:keep_state_and_data, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, :offline}, :asleep, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :asleep, data) do
    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  ### :offline

  def handle_event(:internal, {:update, :offline}, :offline, _data) do
    {:keep_state_and_data, schedule_fetch(15)}
  end

  def handle_event(:internal, {:update, :asleep}, :offline, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :offline, data) do
    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  # Private

  defp fetch(%Data{id: id, deps: deps}, expected_state: expected_state) do
    reachable? =
      case expected_state do
        :online -> true
        {:driving, _} -> true
        {:charging, _, _} -> true
        :offline -> false
        :asleep -> false
        :start -> false
      end

    if reachable? do
      fetch_with_reachable_assumption(id, deps)
    else
      fetch_with_unreachable_assumption(id, deps)
    end
  end

  defp fetch_with_reachable_assumption(id, deps) do
    with {:error, :unavailable} <- call(deps.api, :get_vehicle_with_state, [id]),
         {:ok, vehicle} <- call(deps.api, :get_vehicle, [id]) do
      {:ok, String.to_atom(vehicle.state)}
    end
  end

  defp fetch_with_unreachable_assumption(id, deps) do
    case call(deps.api, :get_vehicle, [id]) do
      {:ok, %Vehicle{state: "online"}} -> call(deps.api, :get_vehicle_with_state, [id])
      {:ok, vehicle} -> {:ok, String.to_atom(vehicle.state)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_position(vehicle_state, data, opts) do
    position = create_position(vehicle_state, opts)
    call(data.deps.log, :insert_position, [data.car_id, position])
  end

  defp create_position(%Vehicle{drive_state: %State.Drive{}} = state, opts \\ []) do
    %{
      trip_id: Keyword.get(opts, :trip_id),
      date: parse_timestamp(state.drive_state.timestamp),
      latitude: state.drive_state.latitude,
      longitude: state.drive_state.longitude,
      speed: mph_to_kmh(state.drive_state.speed),
      power: with(n when is_number(n) <- state.drive_state.power, do: n * 1.0),
      battery_level: state.charge_state.battery_level,
      outside_temp: state.climate_state.outside_temp,
      odometer: miles_to_km(state.vehicle_state.odometer, 6),
      ideal_battery_range_km: miles_to_km(state.charge_state.ideal_battery_range, 1),
      altitude: nil,
      fan_status: state.climate_state.fan_status,
      is_climate_on: state.climate_state.is_climate_on,
      driver_temp_setting: state.climate_state.driver_temp_setting,
      passenger_temp_setting: state.climate_state.passenger_temp_setting,
      is_rear_defroster_on: state.climate_state.is_rear_defroster_on,
      is_front_defroster_on: state.climate_state.is_front_defroster_on
    }
  end

  defp insert_charge(process_id, %Vehicle{charge_state: %State.Charge{}} = state, data) do
    attrs = %{
      date: parse_timestamp(state.charge_state.timestamp),
      battery_heater_on: state.charge_state.battery_heater_on,
      battery_level: state.charge_state.battery_level,
      charge_energy_added: state.charge_state.charge_energy_added,
      charger_actual_current: state.charge_state.charger_actual_current,
      charger_phases: with(p when is_number(p) <- state.charge_state.charger_phases, do: p + 1),
      charger_pilot_current: state.charge_state.charger_pilot_current,
      charger_power: state.charge_state.charger_power,
      charger_voltage: state.charge_state.charger_voltage,
      conn_charge_cable: state.charge_state.conn_charge_cable,
      fast_charger_present: state.charge_state.fast_charger_present,
      fast_charger_brand: state.charge_state.fast_charger_brand,
      fast_charger_type: state.charge_state.fast_charger_type,
      ideal_battery_range_km: miles_to_km(state.charge_state.ideal_battery_range, 1),
      not_enough_power_to_heat: state.charge_state.not_enough_power_to_heat,
      outside_temp: state.climate_state.outside_temp
    }

    :ok = call(data.deps.log, :insert_charge, [process_id, attrs])
  end

  defp parse_timestamp(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.truncate(:second)
  end

  defp try_to_suspend(vehicle_state, data) do
    alias State.{Climate, VehicleState}

    suspend? =
      diff(DateTime.utc_now(), data.last_used) / 60 >
        data.sudpend_after_idle_min

    case {suspend?, vehicle_state} do
      {true, %Vehicle{vehicle_state: %VehicleState{is_user_present: true}}} ->
        Logger.warn("Present user prevents car to go to sleep")

        {:keep_state_and_data, schedule_fetch()}

      {true, %Vehicle{climate_state: %Climate{is_preconditioning: true}}} ->
        Logger.warn("Preconditioning prevents car to go to sleep")

        {:keep_state_and_data, schedule_fetch()}

      {true, %Vehicle{climate_state: %Climate{is_preconditioning: _}}} ->
        Logger.info("Start / :suspend")

        {:next_state, :start, data, schedule_fetch(data.suspend_min, :minutes)}

      {false, _} ->
        {:keep_state, data, schedule_fetch()}
    end
  end

  defp mph_to_kmh(nil), do: nil
  defp mph_to_kmh(mph), do: round(mph * 1.60934)

  defp miles_to_km(nil, _precision), do: nil
  defp miles_to_km(miles, precision), do: Float.round(miles / 0.62137, precision)

  defp determince_interval(n) when not is_nil(n) and n > 0, do: round(1000 / n) |> min(60)
  defp determince_interval(_), do: 15

  defp schedule_fetch(n \\ 10, unit \\ :seconds)

  case(Mix.env()) do
    :test -> defp schedule_fetch(n, _unit), do: {:state_timeout, n, :fetch}
    _____ -> defp schedule_fetch(n, unit), do: {:state_timeout, apply(:timer, unit, [n]), :fetch}
  end

  case(Mix.env()) do
    :test -> defp diff(a, b), do: DateTime.diff(a, b, :millisecond)
    _____ -> defp diff(a, b), do: DateTime.diff(a, b, :second)
  end
end
