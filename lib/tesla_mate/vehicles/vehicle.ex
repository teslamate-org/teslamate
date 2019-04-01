defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Identification
  alias TeslaMate.{Api, Log}

  alias TeslaApi.Vehicle.State
  alias TeslaApi.Vehicle

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct id: nil,
            vehicle_id: nil,
            properties: nil,
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

    properties = Identification.properties(vehicle)

    Logger.info("Found Vehicle '#{vehicle.display_name}' [#{inspect(properties)}]")

    deps = %{
      log: Keyword.get(opts, :log, Log),
      api: Keyword.get(opts, :api, Api)
    }

    data = %Data{
      id: vehicle.id,
      vehicle_id: vehicle.vehicle_id,
      properties: properties,
      last_used: DateTime.utc_now(),
      sudpend_after_idle_min: Keyword.get(opts, :sudpend_after_idle_min, 15),
      suspend_min: Keyword.get(opts, :suspend_min, 21),
      deps: deps
    }

    {:ok, :start, data, {:next_event, :internal, :init}}
  end

  @impl true
  def handle_event(:internal, :init, :start, data) do
    # create_car if not exists

    # DBHelper.getLastTrip()

    case call(data.deps.log, :close_charging_state) do
      {:erorr, :no_charging_state_to_be_closed} -> :ok
      :ok -> :ok
    end

    case call(data.deps.log, :close_drive_state) do
      {:erorr, :no_drive_state_to_be_closed} -> :ok
      :ok -> :ok
    end

    {:keep_state_and_data, {:next_event, :internal, :fetch}}
  end

  # TODO
  # - /wake_up & /sleep routes
  # - supoort for multiple cars
  # - reverse adress lookup
  # - geofecnces
  # - mqtt
  # - indices

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

    :ok = call(data.deps.log, :start_state, [:asleep])

    {:next_state, :asleep, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, :offline}, :start, data) do
    Logger.info("Start / :offline")

    :ok = call(data.deps.log, :start_state, [:offline])

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, :start, data) do
    Logger.info("Start / :online")

    :ok = insert_position(vehicle_state, data)
    :ok = call(data.deps.log, :start_state, [:online])

    {:next_state, :online, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}
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

        :ok = insert_position(vehicle_state, data)
        :ok = call(data.deps.log, :start_drive_state)
        # wh.StartStreamThread(); // for altitude

        {:next_state, {:driving, shift_state}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

      %{charge_state: %State.Charge{charging_state: charging_state}}
      when charging_state in ["Complete", "Charging"] ->
        Logger.info("Start / :charging")

        :ok = insert_charge(vehicle_state, data)
        :ok = insert_position(vehicle_state, data)
        :ok = call(data.deps.log, :start_charging_state)

        {:next_state, {:charging, charging_state}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

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

            # Insert last position before sleep
            :ok = insert_position(vehicle_state, data)

            {:next_state, :start, data, schedule_fetch(data.suspend_min, :minutes)}

          {false, _} ->
            {:keep_state, data, schedule_fetch()}
        end
    end
  end

  ### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _}, _data) do
    Logger.warn("Vehicle went offline while charging")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:charging, last}, data) do
    case {vehicle_state.charge_state.charging_state, last} do
      {"Charging", _} ->
        :ok = insert_charge(vehicle_state, data)

        next_check_in = round(1000 / Map.get(vehicle_state.charge_state, :charge_power, 100))

        {:next_state, {:charging, "Charging"}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(next_check_in)}

      {"Complete", "Complete"} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

      {"Complete", _} ->
        Logger.info("Charging complete")

        :ok = insert_charge(vehicle_state, data)

        {:next_state, {:charging, "Complete"}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch()}

      {charging_state, last_charging_state} ->
        Logger.info(
          "Charging ended (?): #{inspect(charging_state)} | Before: #{last_charging_state}"
        )

        :ok = insert_position(vehicle_state, data)
        :ok = call(data.deps.log, :close_charging_state)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
    end
  end

  ### :driving

  def handle_event(:internal, {:update, :offline}, {:driving, _}, _data) do
    Logger.warn("Vehicle went offline while driving")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle_state}}, {:driving, _}, data) do
    case vehicle_state.drive_state.shift_state do
      shift_state when shift_state in ["D", "R", "N"] ->
        :ok = insert_position(vehicle_state, data)

        {:next_state, {:driving, shift_state}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

      "P" ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(10)}

      nil ->
        Logger.info("Driving ended")

        # wh.StopStreaming();
        :ok = call(data.deps.log, :close_drive_state)

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

  def handle_event(:internal, {:update, {:online, vehicle_state}}, :asleep, data) do
    Logger.info("Vehicle woke up")

    :ok = insert_position(vehicle_state, data)

    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
  end

  # Private

  defp fetch(%Data{id: id, deps: deps}, expected_state: expected_state) do
    reachable? =
      case expected_state do
        :online -> true
        {:driving, _} -> true
        {:charging, _} -> true
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

  defp insert_position(%Vehicle{drive_state: %State.Drive{}} = state, data) do
    attrs = %{
      date: DateTime.from_unix!(state.drive_state.timestamp, :microsecond),
      latitude: state.drive_state.latitude,
      longitude: state.drive_state.longitude,
      speed: state.drive_state.speed,
      power: state.drive_state.power,
      battery_level: Map.get(state.charge_state, :battery_level),
      outside_temp: Map.get(state.climate_state, :outside_temp),
      odometer: Map.get(state.vehicle_state, :odometer),
      ideal_battery_range: Map.get(state.charge_state, :ideal_battery_range),
      altitude: nil
    }

    :ok = call(data.deps.log, :insert_position, [attrs])
  end

  defp insert_charge(%Vehicle{charge_state: %State.Charge{}} = state, data) do
    attrs = %{
      date: DateTime.from_unix!(state.charge_state.timestamp, :microsecond),
      battery_level: state.charge_state.battery_level,
      charge_energy_added: state.charge_state.charge_energy_added,
      charger_actual_current: state.charge_state.charger_actual_current,
      charger_phases: state.charge_state.charger_phases,
      charger_power: state.charge_state.charger_power,
      charger_voltage: state.charge_state.charger_voltage,
      ideal_battery_range: state.charge_state.ideal_battery_range,
      outside_temp: Map.get(state.climate_state, :outside_temp)
    }

    :ok = call(data.deps.log, :insert_charge, [attrs])
  end

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
