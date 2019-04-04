defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Identification
  alias TeslaMate.{Api, Log}

  alias TeslaApi.Vehicle.State
  alias TeslaApi.Vehicle

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

    data = %Data{
      id: vehicle.id,
      vehicle_id: vehicle.vehicle_id,
      last_used: DateTime.utc_now(),
      sudpend_after_idle_min: Keyword.get(opts, :sudpend_after_idle_min, 10),
      suspend_min: Keyword.get(opts, :suspend_min, 21),
      deps: deps
    }

    {:ok, :start, data, {:next_event, :internal, {:init, vehicle}}}
  end

  @impl true
  def handle_event(:internal, {:init, vehicle}, :start, data) do
    {:ok, %Log.Car{id: car_id}} =
      case call(data.deps.log, :get_car_by_eid, [vehicle.id]) do
        nil ->
          properties = Identification.properties(vehicle)

          call(data.deps.log, :create_car, [
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

    {:keep_state, %Data{data | car_id: car_id}, {:next_event, :internal, :fetch}}
  end

  # TODO
  # - /wake_up & /sleep routes
  # - supoort for multiple cars
  # - reverse adress lookup
  # - geofecnces
  # - mqtt
  # - indices
  # - cron job which "closes" drives & charging_processes

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

      {:error, reason} ->
        Logger.warn("Error / vehicle_state: #{inspect(reason)}")

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

    # TODO
    # all states have a position; bring start and end positinos back
    :ok = call(data.deps.log, :start_state, [data.car_id, :offline])

    {:next_state, :offline, data, schedule_fetch()}
  end

  def handle_event(:internal, event, :start, data) do
    Logger.info("Start / :online")

    :ok = call(data.deps.log, :start_state, [data.car_id, :online])

    {:next_state, :online, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  ### :online

  def handle_event(:internal, {:update, :offline}, :online, _data) do
    Logger.warn("Vehicle went abrupbly offline")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, :online, data) do
    case vehicle_state do
      %{drive_state: %State.Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Start / :driving")

        {:ok, trip_id} = call(data.deps.log, :start_trip, [data.car_id])
        :ok = insert_position(vehicle_state, data, trip_id: trip_id)

        {:next_state, {:driving, trip_id}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

      %{charge_state: %State.Charge{charging_state: charging_state}}
      when charging_state in ["Complete", "Charging"] ->
        Logger.info("Start / :charging")

        :ok = insert_position(vehicle_state, data)
        {:ok, charging_process_id} = call(data.deps.log, :start_charging_process, [data.car_id])

        {:next_state, {:charging, charging_state, charging_process_id},
         %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      _ ->
        suspend? =
          diff(DateTime.utc_now(), data.last_used) / 60 >
            data.sudpend_after_idle_min

        case {suspend?, vehicle_state.climate_state} do
          {true, %State.Climate{is_preconditioning: true}} ->
            Logger.warn("Preconditioning prevents car to go to sleep")

            {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

          {true, %State.Climate{is_preconditioning: _}} ->
            Logger.info("Start / :suspend")

            {:next_state, :start, data, schedule_fetch(data.suspend_min, :minutes)}

          {false, _} ->
            {:keep_state, data, schedule_fetch()}
        end
    end
  end

  ### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _, _}, _data) do
    Logger.warn("Vehicle went offline while charging")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:charging, last, pid}, data) do
    case {vehicle_state.charge_state.charging_state, last} do
      {"Charging", _} ->
        :ok = insert_charge(pid, vehicle_state, data)

        next_check_in = round(1000 / Map.get(vehicle_state.charge_state, :charge_power, 100))

        {:next_state, {:charging, "Charging", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(next_check_in)}

      {"Complete", "Complete"} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

      {"Complete", _} ->
        Logger.info("Charging complete")

        :ok = insert_charge(pid, vehicle_state, data)

        {:next_state, {:charging, "Complete", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch()}

      {charging_state, last_charging_state} ->
        Logger.info(
          "Charging ended (?): #{inspect(charging_state)} | Before: #{last_charging_state}"
        )

        :ok = call(data.deps.log, :close_charging_process, [pid])

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
    end
  end

  ### :driving

  def handle_event(:internal, {:update, :offline}, {:driving, _trip_id}, _data) do
    Logger.warn("Vehicle went offline while driving")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:driving, trip_id}, data) do
    case vehicle_state.drive_state.shift_state do
      shift_state when shift_state in ["D", "R", "N"] ->
        :ok = insert_position(vehicle_state, data, trip_id: trip_id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      "P" ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(10)}

      nil ->
        Logger.info("Trip ended")

        :ok = call(data.deps.log, :close_trip, [trip_id])

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
    end
  end

  ### :asleep

  def handle_event(:internal, {:update, :asleep}, :asleep, _data) do
    {:keep_state_and_data, schedule_fetch(15)}
  end

  def handle_event(:internal, {:update, :offline}, :asleep, _data) do
    Logger.warn("Vehicle went offline while asleep")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :asleep, data) do
    Logger.info("Vehicle woke up")

    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  ### :offline

  def handle_event(:internal, {:update, :offline}, :offline, _data) do
    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, :asleep}, :offline, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :offline, data) do
    Logger.info("Is available again")

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

  defp insert_position(%Vehicle{drive_state: %State.Drive{}} = state, data, opts \\ []) do
    trip_id = Keyword.get(opts, :trip_id)

    attrs = %{
      trip_id: trip_id,
      date: DateTime.from_unix!(state.drive_state.timestamp, :millisecond),
      latitude: state.drive_state.latitude,
      longitude: state.drive_state.longitude,
      speed: mph_to_kmh(state.drive_state.speed),
      power: state.drive_state.power,
      battery_level: state.charge_state.battery_level,
      outside_temp: state.climate_state.outside_temp,
      odometer: miles_to_km(state.vehicle_state.odometer, 6),
      ideal_battery_range_km: miles_to_km(state.charge_state.ideal_battery_range, 1),
      altitude: nil
    }

    :ok = call(data.deps.log, :insert_position, [data.car_id, attrs])
  end

  defp insert_charge(process_id, %Vehicle{charge_state: %State.Charge{}} = state, data) do
    attrs = %{
      date: DateTime.from_unix!(state.charge_state.timestamp, :millisecond),
      battery_level: state.charge_state.battery_level,
      charge_energy_added: state.charge_state.charge_energy_added,
      charger_actual_current: state.charge_state.charger_actual_current,
      charger_phases: state.charge_state.charger_phases,
      charger_power: state.charge_state.charger_power,
      charger_voltage: state.charge_state.charger_voltage,
      ideal_battery_range_km: miles_to_km(state.charge_state.ideal_battery_range, 1),
      battery_heater_on: state.charge_state.battery_heater_on,
      outside_temp: state.climate_state.outside_temp
    }

    :ok = call(data.deps.log, :insert_charge, [process_id, attrs])
  end

  defp mph_to_kmh(mph, precision \\ 0)
  defp mph_to_kmh(nil, _precision), do: nil
  defp mph_to_kmh(mph, precision), do: Float.round(mph * 1.60934, precision)

  defp miles_to_km(nil, _precision), do: nil
  defp miles_to_km(miles, precision), do: Float.round(miles / 0.62137, precision)

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
