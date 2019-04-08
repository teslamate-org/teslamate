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
            last_used: nil,
            sudpend_after_idle_min: nil,
            suspend_min: nil,
            deps: %{}

  alias __MODULE__, as: Data

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts,
      name: Keyword.get_lazy(opts, :name, fn -> :"#{Keyword.fetch!(opts, :vehicle).id}" end)
    )
  end

  def state(car_id) do
    GenStateMachine.call(:"#{car_id}", :get_state)
  end

  def suspend(car_id) do
    GenStateMachine.call(:"#{car_id}", :suspend)
  end

  def wake_up(car_id) do
    GenStateMachine.call(:"#{car_id}", :wake_up)
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
      last_used: DateTime.utc_now(),
      sudpend_after_idle_min: Keyword.get(opts, :sudpend_after_idle_min, 15),
      suspend_min: Keyword.get(opts, :suspend_min, 21),
      deps: deps
    }

    {:ok, :start, data, {:next_event, :internal, :fetch}}
  end

  # TODO
  # - deep sleep time with checks every 30min
  # - Schedule Sleep Mode: time window where idle times is set to 0 / is bypassed
  # - Deep Sleep Mode: time window where polling is limited to 30min
  # - reverse adress lookup
  # - geofecnces
  # - mqtt
  # - UI with LiveView
  #   - make suspend settings configurable
  #   - make cars configurable
  #   - create geo fences
  #   - check the vehicle state during sleep attempt - does it still work?
  # - indices
  # - cron job which "closes" drives & charging_processes (i.e there is no end_time)

  ## Fetch

  @impl true
  def handle_event(event, :fetch, state, data) when event in [:state_timeout, :internal] do
    case fetch(data, expected_state: state) do
      {:ok, %Vehicle{} = vehicle} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, {:online, vehicle}}}}

      {:ok, :offline} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, :offline}}}

      {:ok, :asleep} ->
        {:keep_state_and_data, {:next_event, :internal, {:update, :asleep}}}

      {:ok, unknown} ->
        Logger.warn("Error / vehicle state #{unknown}}")

        {:keep_state_and_data, schedule_fetch()}

      {:error, %Error{error: :timeout}} ->
        {:keep_state_and_data, schedule_fetch(5)}

      {:error, %Error{error: error, message: message}} ->
        Logger.warn("Error / #{inspect(error)}: #{message}")

        {:keep_state_and_data, schedule_fetch()}

      {:error, reason} ->
        Logger.warn("Error / #{inspect(reason)}")

        {:keep_state_and_data, schedule_fetch()}
    end
  end

  ## Get_state

  def handle_event({:call, from}, :get_state, state, _data) do
    state =
      case state do
        {:driving, _trip_id} -> :driving
        {:charging, "Charging", _process_id} -> :charging
        {:charging, "Complete", _process_id} -> :charging_complete
        {:suspend, _} -> :suspend
        state -> state
      end

    {:keep_state_and_data, {:reply, from, state}}
  end

  ## Wake_up

  def handle_event({:call, from}, :wake_up, {:suspend, prev_state}, data) do
    case call(data.deps.api, :wake_up, [data.id]) do
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      :ok ->
        {:next_state, prev_state, data, [{:reply, from, :ok}, schedule_fetch()]}
    end
  end

  def handle_event({:call, from}, :wake_up, _state, data) do
    result = call(data.deps.api, :wake_up, [data.id])
    {:keep_state_and_data, [{:reply, from, result}, schedule_fetch()]}
  end

  ## Suspend

  def handle_event({:call, from}, :suspend, state, _data) when state in [:offline, :asleep] do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :suspend, {:suspend, _}, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :suspend, {:driving, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :vehicle_not_parked}}}
  end

  def handle_event({:call, from}, :suspend, {:charging, state, _}, _data)
      when state != "Complete" do
    {:keep_state_and_data, {:reply, from, {:error, :charging_in_progress}}}
  end

  def handle_event({:call, from}, :suspend, _online_or_charging_complete, data) do
    with {:ok, %Vehicle{} = vehicle} <- fetch(data, expected_state: :online),
         :ok <- can_suspend(vehicle) do
      Logger.info("Start / :suspend / Manual")

      {:next_state, {:suspend, :online}, data,
       [schedule_fetch(data.suspend_min, :minutes), {:reply, from, :ok}]}
    else
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      {:ok, state} ->
        {:keep_state_and_data, {:reply, from, {:error, state}}}
    end
  end

  ## Update

  ### :start

  def handle_event(:internal, {:update, :asleep}, :start, data) do
    Logger.info("Start / :asleep")

    :ok = call(data.deps.log, :start_state, [data.car_id, :asleep])

    {:next_state, :asleep, data, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, :offline}, :start, data) do
    Logger.info("Start / :offline")

    :ok = call(data.deps.log, :start_state, [data.car_id, :offline])

    {:next_state, :offline, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :start, data) do
    Logger.info("Start / :online")

    :ok = call(data.deps.log, :start_state, [data.car_id, :online])

    {:next_state, :online, data, {:next_event, :internal, event}}
  end

  ### :online

  def handle_event(:internal, {:update, :offline}, :online, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, :online, data) do
    case vehicle do
      %{drive_state: %State.Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Driving / Start")

        {:ok, trip_id} = call(data.deps.log, :start_trip, [data.car_id])
        :ok = insert_position(vehicle, data, trip_id: trip_id)

        {:next_state, {:driving, trip_id}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(5)}

      %{charge_state: %State.Charge{charging_state: charging_state, time_to_full_charge: t}}
      when charging_state in ["Charging", "Complete"] ->
        Logger.info("Charging / #{t}h left")

        position = create_position(vehicle)

        {:ok, charging_id} = call(data.deps.log, :start_charging_process, [data.car_id, position])
        :ok = insert_charge(charging_id, vehicle, data)

        {:next_state, {:charging, charging_state, charging_id},
         %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      _ ->
        try_to_suspend(vehicle, :online, data)
    end
  end

  ### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _, _}, _data) do
    Logger.warn("Vehicle went offline while charging")

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:charging, last, pid} = s, data) do
    case {vehicle.charge_state.charging_state, last} do
      {"Charging", last_state} ->
        if last_state == "Complete", do: Logger.info("Charging / Restart")

        :ok = insert_charge(pid, vehicle, data)

        interval =
          vehicle.charge_state
          |> Map.get(:charger_power)
          |> determince_interval()

        {:next_state, {:charging, "Charging", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch(interval)}

      {"Complete", "Complete"} ->
        try_to_suspend(vehicle, s, data)

      {"Complete", "Charging"} ->
        Logger.info("Charging / Complete")

        :ok = insert_charge(pid, vehicle, data)

        {:next_state, {:charging, "Complete", pid}, %Data{data | last_used: DateTime.utc_now()},
         schedule_fetch()}

      {charging_state, _} ->
        {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
          call(data.deps.log, :close_charging_process, [pid])

        Logger.info("Charging / #{charging_state} / #{added} kWh – #{duration} min")

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  ### :driving

  def handle_event(:internal, {:update, :offline}, {:driving, _trip_id}, _data) do
    Logger.warn("Vehicle went offline while driving")

    {:keep_state_and_data, schedule_fetch(5)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:driving, trip_id}, data) do
    case vehicle.drive_state.shift_state do
      shift_state when shift_state in ["D", "R", "N"] ->
        :ok = insert_position(vehicle, data, trip_id: trip_id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      "P" ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(10)}

      nil ->
        {:ok, %Log.Trip{distance: distance, duration_min: duration}} =
          call(data.deps.log, :close_trip, [trip_id])

        Logger.info("Driving / Ended / #{Float.round(distance, 1)} km – #{duration} min")

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  ### :asleep

  def handle_event(:internal, {:update, :asleep}, :asleep, _data) do
    {:keep_state_and_data, schedule_fetch(60)}
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
    {:keep_state_and_data, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, :asleep}, :offline, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, :offline, data) do
    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  ### :suspend

  def handle_event(:internal, {:update, {:online, _}} = event, {:suspend, prev_state}, data) do
    {:next_state, prev_state, data, {:next_event, :internal, event}}
  end

  def handle_event(:internal, {:update, state}, {:suspend, _}, data)
      when state in [:asleep, :offline] do
    {:next_state, :start, data, schedule_fetch()}
  end

  # Private

  defp fetch(%Data{id: id, deps: deps}, expected_state: expected_state) do
    reachable? =
      case expected_state do
        {:driving, _} -> true
        {:charging, _, _} -> true
        {:suspend, _} -> false
        :online -> true
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

  defp insert_position(vehicle, data, opts) do
    position = create_position(vehicle, opts)

    with {:ok, _pos} <- call(data.deps.log, :insert_position, [data.car_id, position]) do
      :ok
    end
  end

  defp create_position(%Vehicle{} = vehicle, opts \\ []) do
    %{
      trip_id: Keyword.get(opts, :trip_id),
      date: parse_timestamp(vehicle.drive_state.timestamp),
      latitude: vehicle.drive_state.latitude,
      longitude: vehicle.drive_state.longitude,
      speed: mph_to_kmh(vehicle.drive_state.speed),
      power: with(n when is_number(n) <- vehicle.drive_state.power, do: n * 1.0),
      battery_level: vehicle.charge_state.battery_level,
      outside_temp: vehicle.climate_state.outside_temp,
      odometer: miles_to_km(vehicle.vehicle_state.odometer, 6),
      ideal_battery_range_km: miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
      altitude: nil,
      fan_status: vehicle.climate_state.fan_status,
      is_climate_on: vehicle.climate_state.is_climate_on,
      driver_temp_setting: vehicle.climate_state.driver_temp_setting,
      passenger_temp_setting: vehicle.climate_state.passenger_temp_setting,
      is_rear_defroster_on: vehicle.climate_state.is_rear_defroster_on,
      is_front_defroster_on: vehicle.climate_state.is_front_defroster_on
    }
  end

  defp insert_charge(charging_process_id, %Vehicle{} = vehicle, data) do
    attrs = %{
      date: parse_timestamp(vehicle.charge_state.timestamp),
      battery_heater_on: vehicle.charge_state.battery_heater_on,
      battery_level: vehicle.charge_state.battery_level,
      charge_energy_added: vehicle.charge_state.charge_energy_added,
      charger_actual_current: vehicle.charge_state.charger_actual_current,
      charger_phases: with(p when is_number(p) <- vehicle.charge_state.charger_phases, do: p + 1),
      charger_pilot_current: vehicle.charge_state.charger_pilot_current,
      charger_power: vehicle.charge_state.charger_power,
      charger_voltage: vehicle.charge_state.charger_voltage,
      conn_charge_cable: vehicle.charge_state.conn_charge_cable,
      fast_charger_present: vehicle.charge_state.fast_charger_present,
      fast_charger_brand: vehicle.charge_state.fast_charger_brand,
      fast_charger_type: vehicle.charge_state.fast_charger_type,
      ideal_battery_range_km: miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
      not_enough_power_to_heat: vehicle.charge_state.not_enough_power_to_heat,
      outside_temp: vehicle.climate_state.outside_temp
    }

    with {:ok, _} <- call(data.deps.log, :insert_charge, [charging_process_id, attrs]) do
      :ok
    end
  end

  defp parse_timestamp(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.truncate(:second)
  end

  defp try_to_suspend(vehicle, current_state, data) do
    suspend? =
      diff(DateTime.utc_now(), data.last_used) / 60 >
        data.sudpend_after_idle_min

    if suspend? do
      case can_suspend(vehicle) do
        {:error, :user_present} ->
          Logger.warn("Present user prevents car to go to sleep")

          {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}

        {:error, :preconditioning} ->
          Logger.warn("Preconditioning prevents car to go to sleep")

          {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}

        {:error, :shift_state} ->
          Logger.warn("Shift state prevents car to go to sleep")

          {:keep_state_and_data, schedule_fetch(30)}

        :ok ->
          Logger.info("Start / :suspend")

          {:next_state, {:suspend, current_state}, data,
           schedule_fetch(data.suspend_min, :minutes)}
      end
    else
      {:keep_state_and_data, schedule_fetch(30)}
    end
  end

  defp can_suspend(vehicle) do
    alias State.{Climate, VehicleState, Drive}

    case vehicle do
      %Vehicle{vehicle_state: %VehicleState{is_user_present: true}} ->
        {:error, :user_present}

      %Vehicle{climate_state: %Climate{is_preconditioning: true}} ->
        {:error, :preconditioning}

      %Vehicle{drive_state: %Drive{shift_state: shift_state}} when not is_nil(shift_state) ->
        {:error, :shift_state}

      %Vehicle{} ->
        :ok
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
