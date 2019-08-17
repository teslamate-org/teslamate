defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Summary
  alias TeslaMate.{Api, Log, Settings, Convert}

  alias TeslaApi.Vehicle.State.{Climate, VehicleState, Drive, Charge}
  alias TeslaApi.Vehicle

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct car: nil,
            last_used: nil,
            last_response: nil,
            suspend_after_idle_min: nil,
            suspend_min: nil,
            deps: %{}

  alias __MODULE__, as: Data

  @topic inspect(__MODULE__)
  @asleep_interval 60

  def child_spec(arg) do
    %{
      id: :"#{__MODULE__}_#{Keyword.fetch!(arg, :car).id}",
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts,
      name: Keyword.get_lazy(opts, :name, fn -> :"#{Keyword.fetch!(opts, :car).id}" end)
    )
  end

  def subscribe(car_id) do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic <> "#{car_id}")
  end

  def summary(car_id) do
    GenStateMachine.call(:"#{car_id}", :summary)
  end

  def suspend_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :suspend_logging)
  end

  def resume_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :resume_logging)
  end

  @impl true
  def init(opts) do
    %Log.Car{} = car = Keyword.fetch!(opts, :car)

    suspend_after_idle_min =
      Keyword.get_lazy(opts, :suspend_after_idle_min, fn ->
        settings = Settings.get_settings!()
        settings.suspend_after_idle_min
      end)

    suspend_min =
      Keyword.get_lazy(opts, :suspend_min, fn ->
        settings = Settings.get_settings!()
        settings.suspend_min
      end)

    deps = %{
      log: Keyword.get(opts, :log, Log),
      api: Keyword.get(opts, :api, Api),
      settings: Keyword.get(opts, :settings, Settings),
      pubsub: Keyword.get(opts, :pubsub, Phoenix.PubSub)
    }

    data = %Data{
      car: car,
      last_used: DateTime.utc_now(),
      suspend_after_idle_min: suspend_after_idle_min,
      suspend_min: suspend_min,
      deps: deps
    }

    :ok = call(deps.settings, :subscribe_to_changes)

    {:ok, :start, data, {:next_event, :internal, :fetch}}
  end

  ## Calls

  ### Summary

  def handle_event({:call, from}, :summary, state, %Data{last_response: vehicle}) do
    {:keep_state_and_data, {:reply, from, Summary.into(state, vehicle)}}
  end

  ### resume_logging

  def handle_event({:call, from}, :resume_logging, {:suspended, prev_state}, data) do
    Logger.info("Resuming logging", car_id: data.car.id)

    {:next_state, prev_state, %Data{data | last_used: DateTime.utc_now()},
     [{:reply, from, :ok}, notify_subscribers(), schedule_fetch(5)]}
  end

  def handle_event({:call, from}, :resume_logging, {state, _interval}, data)
      when state in [:asleep, :offline] do
    Logger.info("Expecting imminent wakeup. Increasing polling frequency ...", car_id: data.car.id)

    {:next_state, {state, 1}, data, [{:reply, from, :ok}, {:next_event, :internal, :fetch}]}
  end

  def handle_event({:call, from}, :resume_logging, _state, data) do
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, {:reply, from, :ok}}
  end

  ### suspend_logging

  def handle_event({:call, from}, :suspend_logging, {:offline, _}, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :suspend_logging, {:asleep, _}, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :suspend_logging, {:suspended, _}, _data) do
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :suspend_logging, {:driving, _, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :vehicle_not_parked}}}
  end

  def handle_event({:call, from}, :suspend_logging, {:charging, state, _}, _data)
      when state != "Complete" do
    {:keep_state_and_data, {:reply, from, {:error, :charging_in_progress}}}
  end

  def handle_event({:call, from}, :suspend_logging, _online_or_charging_complete, data) do
    with {:ok, %Vehicle{} = vehicle} <- fetch(data, expected_state: :online),
         :ok <- can_fall_asleep(vehicle) do
      Logger.info("Suspending logging [Triggered manually]", car_id: data.car.id)

      {:next_state, {:suspended, :online}, %Data{data | last_response: vehicle},
       [{:reply, from, :ok}, notify_subscribers(), schedule_fetch(data.suspend_min, :minutes)]}
    else
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      {:ok, state} ->
        {:keep_state_and_data, {:reply, from, {:error, state}}}
    end
  end

  ## Info

  def handle_event(:info, %Settings.Settings{} = settings, _state, data) do
    %Settings.Settings{suspend_min: suspend, suspend_after_idle_min: after_idle} = settings
    {:keep_state, %Data{data | suspend_min: suspend, suspend_after_idle_min: after_idle}}
  end

  ## Internal Events

  ### Fetch

  @impl true
  def handle_event(event, :fetch, state, data) when event in [:state_timeout, :internal] do
    case fetch(data, expected_state: state) do
      {:ok, %Vehicle{state: "online"} = vehicle} ->
        {:keep_state, %Data{data | last_response: vehicle},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      {:ok, %Vehicle{state: "offline"} = vehicle} ->
        {:keep_state,
         if(is_nil(data.last_response), do: %Data{data | last_response: vehicle}, else: data),
         {:next_event, :internal, {:update, :offline}}}

      {:ok, %Vehicle{state: "asleep"} = vehicle} ->
        {:keep_state,
         if(is_nil(data.last_response), do: %Data{data | last_response: vehicle}, else: data),
         {:next_event, :internal, {:update, :asleep}}}

      {:ok, unknown} ->
        Logger.warn("Error / unkown vehicle state: #{inspect(unknown)}}", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch()}

      {:error, :timeout} ->
        Logger.warn("Error / :timeout", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(5)}

      {:error, :unknown} ->
        Logger.warn("Error / :unknown", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(30)}

      {:error, reason} ->
        Logger.warn("Error / #{inspect(reason)}", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch()}
    end
  end

  ## notify_subscribers

  def handle_event(:internal, :notify_subscribers, state, %Data{last_response: vehicle} = data) do
    payload = Summary.into(state, vehicle)

    :ok =
      call(data.deps.pubsub, :broadcast, [TeslaMate.PubSub, @topic <> "#{data.car.id}", payload])

    :keep_state_and_data
  end

  ### Update

  #### :start

  def handle_event(:internal, {:update, :asleep}, :start, data) do
    Logger.info("Start / :asleep", car_id: data.car.id)

    :ok = call(data.deps.log, :start_state, [data.car.id, :asleep])

    {:next_state, {:asleep, @asleep_interval}, data, [notify_subscribers(), schedule_fetch(30)]}
  end

  def handle_event(:internal, {:update, :offline}, :start, data) do
    Logger.info("Start / :offline", car_id: data.car.id)

    :ok = call(data.deps.log, :start_state, [data.car.id, :offline])

    {:next_state, {:offline, @asleep_interval}, data, [notify_subscribers(), schedule_fetch()]}
  end

  def handle_event(:internal, {:update, {:online, vehicle}} = event, :start, data) do
    Logger.info("Start / :online", car_id: data.car.id)

    :ok = call(data.deps.log, :start_state, [data.car.id, :online])
    :ok = insert_position(vehicle, data)

    {:next_state, :online, data, [notify_subscribers(), {:next_event, :internal, event}]}
  end

  #### :online

  def handle_event(:internal, {:update, event}, :online, data)
      when event in [:offline, :asleep] do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, :online, data) do
    case vehicle do
      %Vehicle{vehicle_state: %VehicleState{software_update: %{status: "installing"}}} ->
        Logger.info("Update / Start", car_id: data.car.id)

        {:ok, update_id} = call(data.deps.log, :start_update, [data.car.id])

        {:next_state, {:updating, update_id}, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(15)]}

      %{drive_state: %Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Driving / Start", car_id: data.car.id)

        {:ok, drive_id} = call(data.deps.log, :start_drive, [data.car.id])
        :ok = insert_position(vehicle, data, drive_id: drive_id)

        {:next_state, {:driving, :available, drive_id},
         %Data{data | last_used: DateTime.utc_now()}, [notify_subscribers(), schedule_fetch(2.5)]}

      %{charge_state: %Charge{charging_state: charging_state, battery_level: lvl}}
      when charging_state in ["Starting", "Charging"] ->
        Logger.info("Charging / SOC: #{lvl}%", car_id: data.car.id)

        position = create_position(vehicle)
        {:ok, charge_id} = call(data.deps.log, :start_charging_process, [data.car.id, position])
        :ok = insert_charge(charge_id, vehicle, data)

        {:next_state, {:charging, charging_state, charge_id},
         %Data{data | last_used: DateTime.utc_now()}, [notify_subscribers(), schedule_fetch(2.5)]}

      _ ->
        try_to_suspend(vehicle, :online, data)
    end
  end

  #### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _, _}, data) do
    Logger.warn("Vehicle went offline while charging", car_id: data.car.id)

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:charging, last, pid} = s, data) do
    case {vehicle.charge_state.charging_state, last} do
      {charging_state, last_state} when charging_state in ["Starting", "Charging"] ->
        if last_state == "Complete" do
          Logger.info("Charging / Restart", car_id: data.car.id)
          {:ok, _cproc} = call(data.deps.log, :resume_charging_process, [pid])
        end

        :ok = insert_charge(pid, vehicle, data)

        interval =
          vehicle.charge_state
          |> Map.get(:charger_power)
          |> determince_interval()

        {:next_state, {:charging, "Charging", pid}, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(interval)]}

      {"Complete", "Complete"} ->
        try_to_suspend(vehicle, s, data)

      {"Complete", "Charging"} ->
        :ok = insert_charge(pid, vehicle, data)

        {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [pid])

        Logger.info("Charging / Complete / #{added} kWh – #{duration} min", car_id: data.car.id)

        {:next_state, {:charging, "Complete", pid}, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch()]}

      {state, _} ->
        {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [pid])

        Logger.info("Charging / #{state} / #{added} kWh – #{duration} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :driving

  #### msg: :offline

  def handle_event(:internal, {:update, :offline}, {:driving, :available, drive_id}, data) do
    Logger.warn("Vehicle went offline while driving", car_id: data.car.id)

    {:next_state, {:driving, {:unavailable, 0}, drive_id},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
  end

  def handle_event(:internal, {:update, :offline}, {:driving, {:unavailable, n}, drive_id}, data)
      when n < 15 do
    {:next_state, {:driving, {:unavailable, n + 1}, drive_id},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}
  end

  def handle_event(:internal, {:update, :offline}, {:driving, {:unavailable, _n}, drive_id}, data) do
    {:next_state, {:driving, {:offline, data.last_response}, drive_id},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, :offline}, {:driving, {:offline, _}, _drive_id}, data) do
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, {:online, now}}, {:driving, {:offline, last}, id}, data) do
    offline_start = parse_timestamp(last.drive_state.timestamp)
    offline_end = parse_timestamp(now.drive_state.timestamp)

    offline_min = DateTime.diff(offline_end, offline_start, :second) / 60

    has_gained_range? =
      now.charge_state.ideal_battery_range - last.charge_state.ideal_battery_range > 5

    Logger.info("Vehicle came back online after #{round(offline_min)} min", car_id: data.car.id)

    cond do
      has_gained_range? and offline_min >= 5 ->
        {:ok, %Log.Drive{distance: km, duration_min: min}} =
          call(data.deps.log, :close_drive, [id])

        Logger.info("Logged previous drive: #{round(km)} km – #{min} min", car_id: data.car.id)

        position = create_position(last)

        {:ok, charge_id} =
          call(data.deps.log, :start_charging_process, [
            data.car.id,
            position,
            [date: DateTime.add(offline_start, 1, :second)]
          ])

        :ok = insert_charge(charge_id, last, data)
        :ok = insert_charge(charge_id, now, data)

        {:ok, %Log.ChargingProcess{charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [
            charge_id,
            [date: DateTime.add(offline_end, -1, :second)]
          ])

        Logger.info("Vehicle was charged while being offline: #{added} kWh", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      not has_gained_range? and offline_min >= 15 ->
        {:ok, %Log.Drive{distance: km, duration_min: min}} =
          call(data.deps.log, :close_drive, [id])

        Logger.info("Logged previous drive: #{round(km)} km – #{min} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      true ->
        {:next_state, {:driving, :available, id}, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}
    end
  end

  #### msg: :online

  def handle_event(:internal, {:update, {:online, _} = e}, {:driving, {:unavailable, _}, id}, d) do
    Logger.info("Vehicle is back online", car_id: d.car.id)

    {:next_state, {:driving, :available, id}, %Data{d | last_used: DateTime.utc_now()},
     {:next_event, :internal, {:update, e}}}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:driving, :available, did}, data) do
    case get(vehicle, [:drive_state, :shift_state]) do
      shift_state when shift_state in ["D", "R", "N"] ->
        :ok = insert_position(vehicle, data, drive_id: did)

        {:next_state, {:driving, :available, did}, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(2.5)]}

      shift_state when is_nil(shift_state) or shift_state == "P" ->
        {:ok, %Log.Drive{distance: km, duration_min: min}} =
          call(data.deps.log, :close_drive, [did])

        Logger.info("Driving / Ended / #{round(km)} km – #{min} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :updating

  def handle_event(:internal, {:update, :offline}, {:updating, _update_id}, data) do
    Logger.warn("Vehicle went offline while updating", car_id: data.car.id)
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:updating, update_id}, data) do
    case vehicle.vehicle_state.software_update do
      %VehicleState.SoftwareUpdate{status: "installing"} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(15)}

      %VehicleState.SoftwareUpdate{status: "available"} = software_update ->
        {:ok, %Log.Update{}} = call(data.deps.log, :cancel_update, [update_id])

        Logger.warn("Update canceled | #{inspect(software_update)}", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      %VehicleState.SoftwareUpdate{status: status} = software_update ->
        if status != "" do
          Logger.error("Update failed: #{status} | #{inspect(software_update)}",
            car_id: data.car.id
          )
        end

        car_version = vehicle.vehicle_state.car_version
        {:ok, %Log.Update{}} = call(data.deps.log, :finish_update, [update_id, car_version])

        Logger.info("Update / Installed / #{car_version}", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :asleep / :offline

  def handle_event(:internal, {:update, state}, {state, @asleep_interval}, _data)
      when state in [:asleep, :offline] do
    {:keep_state_and_data, schedule_fetch(@asleep_interval)}
  end

  def handle_event(:internal, {:update, state}, {state, interval}, data)
      when state in [:asleep, :offline] do
    {:next_state, {state, min(interval * 2, @asleep_interval)}, data, schedule_fetch(interval)}
  end

  def handle_event(:internal, {:update, :offline}, {:asleep, _interval}, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, :asleep}, {:offline, _interval}, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, _}} = event, {state, _interval}, data)
      when state in [:asleep, :offline] do
    {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
     {:next_event, :internal, event}}
  end

  #### :suspended

  def handle_event(:internal, {:update, {:online, _}} = event, {:suspended, prev_state}, data) do
    {:next_state, prev_state, data, {:next_event, :internal, event}}
  end

  def handle_event(:internal, {:update, :offline}, {:suspended, _}, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, :asleep}, {:suspended, _}, data) do
    {:next_state, :start, data, schedule_fetch()}
  end

  # Private

  defp fetch(%Data{car: car, deps: deps}, expected_state: expected_state) do
    reachable? =
      case expected_state do
        :online -> true
        {:driving, _, _} -> true
        {:updating, _} -> true
        {:charging, _, _} -> true
        :start -> false
        {:offline, _} -> false
        {:asleep, _} -> false
        {:suspended, _} -> false
      end

    if reachable? do
      fetch_with_reachable_assumption(car.eid, deps)
    else
      fetch_with_unreachable_assumption(car.eid, deps)
    end
  end

  defp fetch_with_reachable_assumption(id, deps) do
    with {:error, :vehicle_unavailable} <- call(deps.api, :get_vehicle_with_state, [id]) do
      call(deps.api, :get_vehicle, [id])
    end
  end

  defp fetch_with_unreachable_assumption(id, deps) do
    with {:ok, %Vehicle{state: "online"}} <- call(deps.api, :get_vehicle, [id]) do
      call(deps.api, :get_vehicle_with_state, [id])
    end
  end

  defp insert_position(vehicle, data, opts \\ []) do
    position = create_position(vehicle, opts)

    with {:ok, _pos} <- call(data.deps.log, :insert_position, [data.car.id, position]) do
      :ok
    end
  end

  defp create_position(%Vehicle{} = vehicle, opts \\ []) do
    %{
      drive_id: Keyword.get(opts, :drive_id),
      date: parse_timestamp(vehicle.drive_state.timestamp),
      latitude: vehicle.drive_state.latitude,
      longitude: vehicle.drive_state.longitude,
      speed: Convert.mph_to_kmh(vehicle.drive_state.speed),
      power: with(n when is_number(n) <- vehicle.drive_state.power, do: n * 1.0),
      battery_level: vehicle.charge_state.battery_level,
      outside_temp: vehicle.climate_state.outside_temp,
      inside_temp: vehicle.climate_state.inside_temp,
      odometer: Convert.miles_to_km(vehicle.vehicle_state.odometer, 6),
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
      est_battery_range_km: Convert.miles_to_km(vehicle.charge_state.est_battery_range, 1),
      altitude: nil,
      fan_status: vehicle.climate_state.fan_status,
      is_climate_on: vehicle.climate_state.is_climate_on,
      driver_temp_setting: vehicle.climate_state.driver_temp_setting,
      passenger_temp_setting: vehicle.climate_state.passenger_temp_setting,
      is_rear_defroster_on: vehicle.climate_state.is_rear_defroster_on,
      is_front_defroster_on: vehicle.climate_state.is_front_defroster_on,
      battery_heater_on: vehicle.charge_state.battery_heater_on,
      battery_heater: vehicle.climate_state.battery_heater,
      battery_heater_no_power: vehicle.climate_state.battery_heater_no_power
    }
  end

  defp insert_charge(charging_process_id, %Vehicle{} = vehicle, data) do
    attrs = %{
      date: parse_timestamp(vehicle.charge_state.timestamp),
      battery_heater_on: vehicle.charge_state.battery_heater_on,
      battery_heater: vehicle.climate_state.battery_heater,
      battery_heater_no_power: vehicle.climate_state.battery_heater_no_power,
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
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
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

  defp try_to_suspend(vehicle, current_state, %Data{car: car} = data) do
    idle_min = diff_seconds(DateTime.utc_now(), data.last_used) / 60
    suspend = idle_min >= data.suspend_after_idle_min

    case can_fall_asleep(vehicle) do
      {:error, :preconditioning} ->
        if suspend, do: Logger.warn("Preconditioning prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}

      {:error, :user_present} ->
        if suspend, do: Logger.warn("Present user prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

      {:error, :unlocked} ->
        if suspend,
          do: Logger.warn("Vehicle cannot to go to sleep because it is unlocked", car_id: car.id)

        {:keep_state_and_data, [notify_subscribers(), schedule_fetch()]}

      {:error, :sentry_mode} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(30)]}

      :ok ->
        if suspend do
          Logger.info("Suspending logging", car_id: car.id)

          {:next_state, {:suspended, current_state}, data,
           [notify_subscribers(), schedule_fetch(data.suspend_min, :minutes)]}
        else
          {:keep_state_and_data, [notify_subscribers(), schedule_fetch(15)]}
        end
    end
  end

  defp can_fall_asleep(vehicle) do
    case vehicle do
      %Vehicle{vehicle_state: %VehicleState{is_user_present: true}} ->
        {:error, :user_present}

      %Vehicle{climate_state: %Climate{is_preconditioning: true}} ->
        {:error, :preconditioning}

      %Vehicle{vehicle_state: %VehicleState{sentry_mode: true}} ->
        {:error, :sentry_mode}

      %Vehicle{vehicle_state: %VehicleState{locked: false}} ->
        {:error, :unlocked}

      %Vehicle{} ->
        :ok
    end
  end

  defp determince_interval(n) when not is_nil(n) and n > 0, do: round(725 / n) |> min(30)
  defp determince_interval(_), do: 15

  defp notify_subscribers do
    {:next_event, :internal, :notify_subscribers}
  end

  defp get(struct, keys) do
    Enum.reduce(keys, struct, fn key, acc -> if acc, do: Map.get(acc, key) end)
  end

  defp schedule_fetch(n \\ 10, unit \\ :seconds)

  case(Mix.env()) do
    :test -> defp schedule_fetch(n, _unit), do: {:state_timeout, round(n), :fetch}
    _____ -> defp schedule_fetch(n, u), do: {:state_timeout, round(apply(:timer, u, [n])), :fetch}
  end

  case(Mix.env()) do
    :test -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :millisecond)
    _____ -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :second)
  end
end
