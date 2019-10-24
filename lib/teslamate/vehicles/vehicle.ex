defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Summary
  alias TeslaMate.{Vehicles, Api, Log, Locations, Settings, Convert}

  alias TeslaApi.Vehicle.State.{Climate, VehicleState, Drive, Charge, VehicleConfig}
  alias TeslaApi.Vehicle

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct car: nil,
            last_used: nil,
            last_response: nil,
            last_state_change: nil,
            settings: nil,
            deps: %{}

  alias __MODULE__, as: Data

  @topic inspect(__MODULE__)

  @asleep_interval 60
  @charging_interval 5
  @driving_interval 2.5

  @drive_timout_min 15

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

  def healthy?(car_id) do
    with :ok <- :fuse.ask(fuse_name(:api_error, car_id), :sync),
         :ok <- :fuse.ask(fuse_name(:vehicle_not_found, car_id), :sync) do
      true
    else
      :blown -> false
    end
  end

  def summary(pid) when is_pid(pid), do: GenStateMachine.call(pid, :summary)
  def summary(car_id), do: GenStateMachine.call(:"#{car_id}", :summary)

  def suspend_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :suspend_logging)
  end

  def resume_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :resume_logging)
  end

  @impl true
  def init(opts) do
    %Log.Car{} = car = Keyword.fetch!(opts, :car)

    deps = %{
      log: Keyword.get(opts, :deps_log, Log),
      api: Keyword.get(opts, :deps_api, Api),
      settings: Keyword.get(opts, :deps_settings, Settings),
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      pubsub: Keyword.get(opts, :deps_pubsub, Phoenix.PubSub)
    }

    settings = %Settings.Settings{} = Keyword.get_lazy(opts, :settings, &Settings.get_settings!/0)

    last_state_change =
      with %Log.State{start_date: date} <- call(deps.log, :get_current_state, [car.id]) do
        date
      end

    data = %Data{
      car: car,
      last_used: DateTime.utc_now(),
      last_state_change: last_state_change,
      settings: settings,
      deps: deps
    }

    fuses = [
      {:vehicle_not_found, {{:standard, 8, :timer.minutes(20)}, {:reset, :timer.minutes(10)}}},
      {:api_error, {{:standard, 3, :timer.minutes(10)}, {:reset, :timer.minutes(5)}}}
    ]

    for {key, opts} <- fuses do
      name = fuse_name(key, data.car.id)
      :ok = :fuse.install(name, opts)
      :ok = :fuse.circuit_enable(name)
    end

    :ok = call(deps.settings, :subscribe_to_changes)

    {:ok, :start, data, {:next_event, :internal, :fetch}}
  end

  ## Calls

  ### Summary

  def handle_event({:call, from}, :summary, state, %Data{last_response: vehicle} = data) do
    summary =
      Summary.into(vehicle, %{
        state: state,
        since: data.last_state_change,
        healthy?: healthy?(data.car.id),
        car: data.car
      })

    {:keep_state_and_data, {:reply, from, summary}}
  end

  ### resume_logging

  def handle_event({:call, from}, :resume_logging, {:suspended, prev_state}, data) do
    Logger.info("Resuming logging", car_id: data.car.id)

    {:next_state, prev_state,
     %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
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

  def handle_event({:call, from}, :suspend_logging, {:updating, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :update_in_progress}}}
  end

  def handle_event({:call, from}, :suspend_logging, {:charging, _}, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :charging_in_progress}}}
  end

  def handle_event({:call, from}, :suspend_logging, _online_or_charging_complete, data) do
    with {:ok, %Vehicle{} = vehicle} <- fetch(data, expected_state: :online),
         :ok <- can_fall_asleep(vehicle, data.settings) do
      Logger.info("Suspending logging [Triggered manually]", car_id: data.car.id)

      {:next_state, {:suspended, :online},
       %Data{data | last_state_change: DateTime.utc_now(), last_response: vehicle},
       [
         {:reply, from, :ok},
         notify_subscribers(),
         schedule_fetch(data.settings.suspend_min, :minutes)
       ]}
    else
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      {:ok, state} ->
        {:keep_state_and_data, {:reply, from, {:error, state}}}
    end
  end

  ## Info

  def handle_event(:info, %Settings.Settings{} = settings, _state, data) do
    {:keep_state, %Data{data | settings: settings}}
  end

  def handle_event(:info, message, _state, _data) do
    Logger.error("Unhandled message: #{inspect(message, pretty: true)}")
    :keep_state_and_data
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
        data =
          if is_nil(data.last_response) do
            %Data{data | last_response: restore_last_knwon_values(vehicle, data)}
          else
            data
          end

        {:keep_state, data, {:next_event, :internal, {:update, :offline}}}

      {:ok, %Vehicle{state: "asleep"} = vehicle} ->
        data =
          if is_nil(data.last_response) do
            %Data{data | last_response: restore_last_knwon_values(vehicle, data)}
          else
            data
          end

        {:keep_state, data, {:next_event, :internal, {:update, :asleep}}}

      {:ok, %Vehicle{state: state} = vehicle} ->
        Logger.warn(
          "Error / unknown vehicle state #{inspect(state)}\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state_and_data, schedule_fetch()}

      {:error, :timeout} ->
        Logger.warn("Error / upstream timeout", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(5)}

      {:error, :closed} ->
        Logger.warn("Error / connection closed", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(5)}

      {:error, :in_service} ->
        Logger.info("Vehicle is currently in service", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(60)}

      {:error, :not_signed_in} ->
        Logger.error("Error / unauthorized")

        :ok = fuse_name(:api_error, data.car.id) |> :fuse.circuit_disable()

        # Stop polling
        {:next_state, :start, data, notify_subscribers()}

      {:error, :vehicle_not_found} ->
        Logger.error("Error / :vehicle_not_found", car_id: data.car.id)

        fuse_name = fuse_name(:vehicle_not_found, data.car.id)
        :ok = :fuse.melt(fuse_name(:api_error, data.car.id))
        :ok = :fuse.melt(fuse_name)

        with :blown <- :fuse.ask(fuse_name, :sync) do
          true = call(data.deps.vehicles, :kill)
        end

        {:keep_state_and_data, [notify_subscribers(), schedule_fetch(30)]}

      {:error, reason} ->
        Logger.error("Error / #{inspect(reason)}", car_id: data.car.id)
        :ok = fuse_name(:api_error, data.car.id) |> :fuse.melt()
        {:keep_state_and_data, [notify_subscribers(), schedule_fetch(30)]}
    end
  end

  ## notify_subscribers

  def handle_event(:internal, :notify_subscribers, state, %Data{last_response: vehicle} = data) do
    payload =
      Summary.into(vehicle, %{
        state: state,
        since: data.last_state_change,
        healthy?: healthy?(data.car.id),
        car: nil
      })

    :ok =
      call(data.deps.pubsub, :broadcast, [TeslaMate.PubSub, @topic <> "#{data.car.id}", payload])

    :keep_state_and_data
  end

  ### Update

  #### :start

  def handle_event(:internal, {:update, :asleep}, :start, data) do
    Logger.info("Start / :asleep", car_id: data.car.id)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car.id, :asleep])

    {:next_state, {:asleep, @asleep_interval}, %Data{data | last_state_change: last_state_change},
     [notify_subscribers(), schedule_fetch()]}
  end

  def handle_event(:internal, {:update, :offline}, :start, data) do
    Logger.info("Start / :offline", car_id: data.car.id)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car.id, :offline])

    {:next_state, {:offline, @asleep_interval},
     %Data{data | last_state_change: last_state_change}, [notify_subscribers(), schedule_fetch()]}
  end

  def handle_event(:internal, {:update, {:online, vehicle}} = event, :start, data) do
    Logger.info("Start / :online", car_id: data.car.id)

    {:ok, car} = call(data.deps.log, :update_car, [data.car, identify(vehicle)])

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car.id, :online])

    :ok = insert_position(vehicle, data)

    {:next_state, :online, %Data{data | car: car, last_state_change: last_state_change},
     [notify_subscribers(), {:next_event, :internal, event}]}
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

        {:next_state, {:updating, update_id},
         %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(15)]}

      %{drive_state: %Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Driving / Start", car_id: data.car.id)

        {:ok, drive_id} = call(data.deps.log, :start_drive, [data.car.id])
        :ok = insert_position(vehicle, data, drive_id: drive_id)

        {:next_state, {:driving, :available, drive_id},
         %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(@driving_interval)]}

      %{charge_state: %Charge{charging_state: charging_state, battery_level: lvl}}
      when charging_state in ["Starting", "Charging"] ->
        alias Locations.GeoFence

        position = create_position(vehicle)
        {:ok, cproc} = call(data.deps.log, :start_charging_process, [data.car.id, position])
        :ok = insert_charge(cproc, vehicle, data)

        ["Charging", "SOC: #{lvl}%", with(%GeoFence{name: name} <- cproc.geofence, do: name)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" / ")
        |> Logger.info(car_id: data.car.id)

        {:next_state, {:charging, cproc},
         %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(@charging_interval)]}

      _ ->
        try_to_suspend(vehicle, :online, data)
    end
  end

  #### :charging

  def handle_event(:internal, {:update, :offline}, {:charging, _}, data) do
    Logger.warn("Vehicle went offline while charging", car_id: data.car.id)

    {:keep_state_and_data, schedule_fetch()}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:charging, cproc}, data) do
    case vehicle.charge_state.charging_state do
      charging_state when charging_state in ["Starting", "Charging"] ->
        :ok = insert_charge(cproc, vehicle, data)

        {:next_state, {:charging, cproc}, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(@charging_interval)]}

      state ->
        :ok = insert_charge(cproc, vehicle, data)

        {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [
            cproc,
            [charging_interval: @charging_interval]
          ])

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

  def handle_event(:internal, {:update, :offline}, {:driving, {:offline, _last}, nil}, data) do
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}
  end

  def handle_event(:internal, {:update, :offline}, {:driving, {:offline, last}, drive_id}, data) do
    offline_since = parse_timestamp(last.drive_state.timestamp)

    case diff_seconds(DateTime.utc_now(), offline_since) / 60 do
      min when min >= @drive_timout_min ->
        timeout_drive(drive_id, data)

        {:next_state, {:driving, {:offline, last}, nil},
         %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}

      _min ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30)}
    end
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
        unless is_nil(id), do: timeout_drive(id, data)

        {:ok, cproc} =
          call(data.deps.log, :start_charging_process, [
            data.car.id,
            create_position(last),
            [date: DateTime.add(offline_start, 1, :second)]
          ])

        :ok = insert_charge(cproc, put_charge_defaults(last), data)
        :ok = insert_charge(cproc, put_charge_defaults(now), data)

        {:ok, %Log.ChargingProcess{charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [
            cproc,
            [date: DateTime.add(offline_end, -1, :second)]
          ])

        Logger.info("Vehicle was charged while being offline: #{added} kWh", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      not has_gained_range? and offline_min >= @drive_timout_min ->
        unless is_nil(id), do: timeout_drive(id, data)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      not is_nil(id) ->
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
         [notify_subscribers(), schedule_fetch(@driving_interval)]}

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
    case Map.get(vehicle.vehicle_state || %{}, :software_update) do
      nil ->
        Logger.warn("Update / empty payload:\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5)}

      %VehicleState.SoftwareUpdate{status: "installing"} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(15)}

      %VehicleState.SoftwareUpdate{status: "available"} = software_update ->
        {:ok, %Log.Update{}} = call(data.deps.log, :cancel_update, [update_id])

        Logger.warn("Update canceled:\n\n#{inspect(software_update, pretty: true)}",
          car_id: data.car.id
        )

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      %VehicleState.SoftwareUpdate{status: status} = software_update ->
        if status != "" do
          Logger.error("Update failed: #{status}\n\n#{inspect(software_update, pretty: true)}",
            car_id: data.car.id
          )
        end

        car_version = vehicle.vehicle_state.car_version
        {:ok, %Log.Update{}} = call(data.deps.log, :finish_update, [update_id, car_version])

        Logger.info("Update / Installed #{car_version}", car_id: data.car.id)

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

  defp identify(%Vehicle{display_name: name, vehicle_config: config}) do
    %VehicleConfig{car_type: type, trim_badging: trim_badging} = config

    trim_badging =
      with str when is_binary(str) <- trim_badging do
        String.upcase(str)
      end

    model =
      case String.downcase(type) do
        "models" <> _ -> "S"
        "model3" <> _ -> "3"
        "modelx" <> _ -> "X"
        "modely" <> _ -> "Y"
        _____________ -> nil
      end

    %{trim_badging: trim_badging, model: model, name: name}
  end

  defp restore_last_knwon_values(vehicle, data) do
    with %Vehicle{drive_state: nil, charge_state: nil, climate_state: nil} <- vehicle,
         %Log.Position{} = position <- call(data.deps.log, :get_latest_position, [data.car.id]) do
      drive = %Drive{
        latitude: position.latitude,
        longitude: position.longitude
      }

      charge = %Charge{
        ideal_battery_range: position.ideal_battery_range_km |> Convert.km_to_miles(10),
        est_battery_range: position.est_battery_range_km |> Convert.km_to_miles(10),
        battery_range: position.rated_battery_range_km |> Convert.km_to_miles(10),
        battery_level: position.battery_level
      }

      climate = %Climate{
        outside_temp: position.outside_temp,
        inside_temp: position.inside_temp
      }

      %Vehicle{vehicle | drive_state: drive, charge_state: charge, climate_state: climate}
    else
      _ -> vehicle
    end
  end

  defp fetch(%Data{car: car, deps: deps}, expected_state: expected_state) do
    reachable? =
      case expected_state do
        :online -> true
        {:driving, _, _} -> true
        {:updating, _} -> true
        {:charging, _} -> true
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
      rated_battery_range_km: Convert.miles_to_km(vehicle.charge_state.battery_range, 1),
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

  defp insert_charge(charging_process, %Vehicle{} = vehicle, data) do
    attrs = %{
      date: parse_timestamp(vehicle.charge_state.timestamp),
      battery_heater_on: vehicle.charge_state.battery_heater_on,
      battery_heater: vehicle.climate_state.battery_heater,
      battery_heater_no_power: vehicle.climate_state.battery_heater_no_power,
      battery_level: vehicle.charge_state.battery_level,
      charge_energy_added: vehicle.charge_state.charge_energy_added,
      charger_actual_current: vehicle.charge_state.charger_actual_current,
      charger_phases: vehicle.charge_state.charger_phases,
      charger_pilot_current: vehicle.charge_state.charger_pilot_current,
      charger_power: vehicle.charge_state.charger_power,
      charger_voltage: vehicle.charge_state.charger_voltage,
      conn_charge_cable: vehicle.charge_state.conn_charge_cable,
      fast_charger_present: vehicle.charge_state.fast_charger_present,
      fast_charger_brand: vehicle.charge_state.fast_charger_brand,
      fast_charger_type: vehicle.charge_state.fast_charger_type,
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
      rated_battery_range_km: Convert.miles_to_km(vehicle.charge_state.battery_range, 1),
      not_enough_power_to_heat: vehicle.charge_state.not_enough_power_to_heat,
      outside_temp: vehicle.climate_state.outside_temp
    }

    with {:ok, _} <- call(data.deps.log, :insert_charge, [charging_process, attrs]) do
      :ok
    end
  end

  defp parse_timestamp(ts) do
    DateTime.from_unix!(ts, :millisecond)
  end

  defp try_to_suspend(vehicle, current_state, %Data{car: car, settings: settings} = data) do
    idle_min = diff_seconds(DateTime.utc_now(), data.last_used) / 60
    suspend = idle_min >= settings.suspend_after_idle_min

    case can_fall_asleep(vehicle, settings) do
      {:error, :sentry_mode} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [notify_subscribers(), schedule_fetch(30)]}

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

      {:error, :shift_state} ->
        if suspend,
          do: Logger.warn("Shift state reading prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

      {:error, :temp_reading} ->
        if suspend,
          do: Logger.warn("Temperature readings prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch()}

      :ok ->
        if suspend do
          Logger.info("Suspending logging", car_id: car.id)

          {:next_state, {:suspended, current_state},
           %Data{data | last_state_change: DateTime.utc_now()},
           [notify_subscribers(), schedule_fetch(settings.suspend_min, :minutes)]}
        else
          {:keep_state_and_data, [notify_subscribers(), schedule_fetch(15)]}
        end
    end
  end

  defp can_fall_asleep(vehicle, settings) do
    alias Settings.Settings

    case {vehicle, settings} do
      {%Vehicle{vehicle_state: %VehicleState{is_user_present: true}}, _} ->
        {:error, :user_present}

      {%Vehicle{climate_state: %Climate{is_preconditioning: true}}, _} ->
        {:error, :preconditioning}

      {%Vehicle{vehicle_state: %VehicleState{sentry_mode: true}}, _} ->
        {:error, :sentry_mode}

      {%Vehicle{vehicle_state: %VehicleState{locked: false}}, %Settings{req_not_unlocked: true}} ->
        {:error, :unlocked}

      {%Vehicle{drive_state: %Drive{shift_state: shift_state}},
       %Settings{req_no_shift_state_reading: true}}
      when not is_nil(shift_state) ->
        {:error, :shift_state}

      {%Vehicle{climate_state: %Climate{outside_temp: out_t, inside_temp: in_t}},
       %Settings{req_no_temp_reading: true}}
      when not is_nil(out_t) or not is_nil(in_t) ->
        {:error, :temp_reading}

      {%Vehicle{}, %Settings{}} ->
        :ok
    end
  end

  defp timeout_drive(drive_id, %Data{} = data) do
    {:ok, %Log.Drive{distance: km, duration_min: min}} =
      call(data.deps.log, :close_drive, [drive_id])

    Logger.info("Driving / Timeout / #{round(km)} km – #{min} min", car_id: data.car.id)
  end

  defp put_charge_defaults(vehicle) do
    charge_state =
      vehicle.charge_state
      |> Map.update!(:charge_energy_added, fn
        nil -> 0
        val -> val
      end)
      |> Map.update!(:charger_power, fn
        nil -> 0
        val -> val
      end)

    Map.put(vehicle, :charge_state, charge_state)
  end

  defp fuse_name(:vehicle_not_found, car_id), do: :"#{__MODULE__}_#{car_id}_not_found"
  defp fuse_name(:api_error, car_id), do: :"#{__MODULE__}_#{car_id}_api_error"

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
