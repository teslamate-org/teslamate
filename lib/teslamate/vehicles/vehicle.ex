defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Summary
  alias TeslaMate.{Vehicles, Api, Log, Locations, Settings, Convert}
  alias TeslaMate.Settings.CarSettings

  alias TeslaApi.Vehicle.State.{Climate, VehicleState, Drive, Charge, VehicleConfig}
  alias TeslaApi.Vehicle

  import Core.Dependency, only: [call: 3, call: 2]

  defstruct car: nil,
            last_used: nil,
            last_response: nil,
            last_state_change: nil,
            geofence: nil,
            deps: %{},
            task: nil,
            import?: false

  alias __MODULE__, as: Data

  @asleep_interval 30
  @driving_interval 2.5

  @drive_timout_min 15

  # Static

  def identify(%Vehicle{display_name: name, vehicle_config: config}) do
    case config do
      %VehicleConfig{car_type: type, trim_badging: trim_badging} ->
        trim_badging =
          with str when is_binary(str) <- trim_badging do
            String.upcase(str)
          end

        model =
          with str when is_binary(str) <- type do
            case String.downcase(str) do
              "models" <> _ -> "S"
              "model3" <> _ -> "3"
              "modelx" <> _ -> "X"
              "modely" <> _ -> "Y"
              _____________ -> nil
            end
          end

        {:ok, %{trim_badging: trim_badging, model: model, name: name}}

      nil ->
        {:error, :vehicle_config_not_available}
    end
  end

  # API

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

  def subscribe_to_summary(car_id) do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, summary_topic(car_id))
  end

  def subscribe_to_fetch(car_id) do
    Phoenix.PubSub.subscribe(TeslaMate.PubSub, fetch_topic(car_id))
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

  def busy?(car_id), do: GenStateMachine.call(:"#{car_id}", :busy?)

  def suspend_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :suspend_logging)
  end

  def resume_logging(car_id) do
    GenStateMachine.call(:"#{car_id}", :resume_logging)
  end

  # Callbacks

  @impl true
  def init(opts) do
    %Log.Car{settings: %CarSettings{}} = car = Keyword.fetch!(opts, :car)

    deps = %{
      log: Keyword.get(opts, :deps_log, Log),
      api: Keyword.get(opts, :deps_api, Api),
      settings: Keyword.get(opts, :deps_settings, Settings),
      locations: Keyword.get(opts, :deps_locations, Locations),
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      pubsub: Keyword.get(opts, :deps_pubsub, Phoenix.PubSub)
    }

    last_state_change =
      with %Log.State{start_date: date} <- call(deps.log, :get_current_state, [car]) do
        date
      end

    data = %Data{
      car: car,
      last_used: DateTime.utc_now(),
      last_state_change: last_state_change,
      deps: deps,
      import?: Keyword.get(opts, :import?, false)
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

    :ok = call(deps.settings, :subscribe_to_changes, [car])

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
        geofence: data.geofence,
        car: data.car
      })

    {:keep_state_and_data, {:reply, from, summary}}
  end

  ### Busy?

  def handle_event({:call, from}, :busy?, _state, %Data{task: task}) do
    {:keep_state_and_data, {:reply, from, task != nil}}
  end

  ### resume_logging

  def handle_event({:call, from}, :resume_logging, {:suspended, prev_state}, data) do
    Logger.info("Resuming logging", car_id: data.car.id)

    {:next_state, prev_state,
     %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
     [{:reply, from, :ok}, broadcast_summary(), schedule_fetch(5, data)]}
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

  def handle_event({:call, from}, :suspend_logging, _online, data) do
    with {:ok, %Vehicle{} = vehicle} <- fetch(data, expected_state: :online),
         :ok <- can_fall_asleep(vehicle, data) do
      Logger.info("Suspending logging [Triggered manually]", car_id: data.car.id)

      {:ok, _pos} = call(data.deps.log, :insert_position, [data.car, create_position(vehicle)])

      {:next_state, {:suspended, :online},
       %Data{data | last_state_change: DateTime.utc_now(), last_response: vehicle, task: nil},
       [
         {:reply, from, :ok},
         broadcast_fetch(false),
         broadcast_summary(),
         schedule_fetch(data.car.settings.suspend_min, :minutes, data)
       ]}
    else
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      {:ok, state} ->
        {:keep_state_and_data, {:reply, from, {:error, state}}}
    end
  end

  ## Info

  def handle_event(:info, {ref, fetch_result}, state, %Data{task: %Task{ref: ref}} = data)
      when is_reference(ref) do
    data = %Data{data | task: nil}

    case fetch_result do
      {:ok, %Vehicle{state: "online"} = vehicle} ->
        {:keep_state, %Data{data | last_response: vehicle},
         [broadcast_fetch(false), {:next_event, :internal, {:update, {:online, vehicle}}}]}

      {:ok, %Vehicle{state: "offline"} = vehicle} ->
        data =
          if is_nil(data.last_response) do
            %Data{data | last_response: restore_last_knwon_values(vehicle, data)}
          else
            data
          end

        {:keep_state, data,
         [broadcast_fetch(false), {:next_event, :internal, {:update, {:offline, vehicle}}}]}

      {:ok, %Vehicle{state: "asleep"} = vehicle} ->
        data =
          if is_nil(data.last_response) do
            %Data{data | last_response: restore_last_knwon_values(vehicle, data)}
          else
            data
          end

        {:keep_state, data,
         [broadcast_fetch(false), {:next_event, :internal, {:update, {:asleep, vehicle}}}]}

      {:ok, %Vehicle{state: state} = vehicle} ->
        Logger.warn(
          "Error / unknown vehicle state #{inspect(state)}\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state, data, [broadcast_fetch(false), schedule_fetch(data)]}

      {:error, :closed} ->
        Logger.warn("Error / connection closed", car_id: data.car.id)
        {:keep_state, data, [broadcast_fetch(false), schedule_fetch(5, data)]}

      {:error, :vehicle_in_service} ->
        Logger.info("Vehicle is currently in service", car_id: data.car.id)
        {:keep_state, data, [broadcast_fetch(false), schedule_fetch(60, data)]}

      {:error, :not_signed_in} ->
        Logger.error("Error / unauthorized")

        :ok = fuse_name(:api_error, data.car.id) |> :fuse.circuit_disable()

        # Stop polling
        {:next_state, :start, data, [broadcast_fetch(false), broadcast_summary()]}

      {:error, :vehicle_not_found} ->
        Logger.error("Error / :vehicle_not_found", car_id: data.car.id)

        fuse_name = fuse_name(:vehicle_not_found, data.car.id)
        :ok = :fuse.melt(fuse_name(:api_error, data.car.id))
        :ok = :fuse.melt(fuse_name)

        with :blown <- :fuse.ask(fuse_name, :sync) do
          true = call(data.deps.vehicles, :kill)
        end

        {:keep_state, data,
         [broadcast_fetch(false), broadcast_summary(), schedule_fetch(30, data)]}

      {:error, reason} ->
        Logger.error("Error / #{inspect(reason)}", car_id: data.car.id)

        unless reason == :timeout do
          :ok = fuse_name(:api_error, data.car.id) |> :fuse.melt()
        end

        interval =
          case state do
            {:driving, _, _} -> 1
            {:charging, _} -> 5
            :online -> 15
            _ -> 30
          end

        {:keep_state, data,
         [broadcast_fetch(false), broadcast_summary(), schedule_fetch(interval, data)]}
    end
  end

  def handle_event(:info, {ref, result}, _state, _data) when is_reference(ref) do
    Logger.debug("Unhandled fetch result: #{inspect(result, pretty: true)}")
    :keep_state_and_data
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, %CarSettings{} = settings, _state, data) do
    Logger.debug("Received settings: #{inspect(settings, pretty: true)}")
    {:keep_state, %Data{data | car: Map.put(data.car, :settings, settings)}}
  end

  def handle_event(:info, message, _state, _data) do
    Logger.debug("Unhandled message: #{inspect(message, pretty: true)}")
    :keep_state_and_data
  end

  ## Internal Events

  ### Fetch

  @impl true
  def handle_event(event, :fetch, state, data) when event in [:state_timeout, :internal] do
    task =
      Task.async(fn ->
        fetch(data, expected_state: state)
      end)

    {:keep_state, %Data{data | task: task}, broadcast_fetch(true)}
  end

  ### Broadcast Summary

  def handle_event(:internal, :broadcast_summary, state, %Data{last_response: vehicle} = data) do
    payload =
      Summary.into(vehicle, %{
        state: state,
        since: data.last_state_change,
        healthy?: healthy?(data.car.id),
        geofence: data.geofence,
        car: nil
      })

    :ok =
      call(data.deps.pubsub, :broadcast, [TeslaMate.PubSub, summary_topic(data.car.id), payload])

    :keep_state_and_data
  end

  ### Broadcast Fetch

  def handle_event(:internal, {:broadcast_fetch, status}, _state, data) do
    :ok =
      call(data.deps.pubsub, :broadcast, [
        TeslaMate.PubSub,
        fetch_topic(data.car.id),
        {:status, status}
      ])

    :keep_state_and_data
  end

  ### Store Position

  def handle_event({:timeout, :store_position}, :store_position, :online, data) do
    Logger.debug("Storing position ...")

    {:ok, _pos} =
      call(data.deps.log, :insert_position, [data.car, create_position(data.last_response)])

    {:keep_state_and_data, schedule_position_storing()}
  end

  def handle_event({:timeout, :store_position}, :store_position, _state, _data) do
    :keep_state_and_data
  end

  ### Update

  #### :start

  def handle_event(:internal, {:update, {:asleep, vehicle}}, :start, data) do
    Logger.info("Start / :asleep", car_id: data.car.id)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car, :asleep, date_opts(vehicle)])

    {:next_state, {:asleep, @asleep_interval}, %Data{data | last_state_change: last_state_change},
     [broadcast_summary(), schedule_fetch(data)]}
  end

  def handle_event(:internal, {:update, {:offline, vehicle}}, :start, data) do
    Logger.info("Start / :offline", car_id: data.car.id)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car, :offline, date_opts(vehicle)])

    {:next_state, {:offline, @asleep_interval},
     %Data{data | last_state_change: last_state_change},
     [broadcast_summary(), schedule_fetch(data)]}
  end

  def handle_event(:internal, {:update, {:online, vehicle}} = evt, :start, data) do
    Logger.info("Start / :online", car_id: data.car.id)

    {:ok, attrs} = identify(vehicle)
    {:ok, car} = call(data.deps.log, :update_car, [data.car, attrs])
    :ok = synchronize_updates(vehicle, data)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [car, :online, date_opts(vehicle)])

    {:ok, pos} = call(data.deps.log, :insert_position, [car, create_position(vehicle)])
    geofence = call(data.deps.locations, :find_geofence, [pos])

    {:next_state, :online,
     %Data{data | car: car, last_state_change: last_state_change, geofence: geofence},
     [broadcast_summary(), {:next_event, :internal, evt}, schedule_position_storing()]}
  end

  #### :online

  def handle_event(:internal, {:update, {event, _vehicle}}, :online, data)
      when event in [:offline, :asleep] do
    {:next_state, :start, data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, :online, data) do
    alias TeslaApi.Vehicle, as: V

    case vehicle do
      %V{vehicle_state: %VehicleState{timestamp: ts, software_update: %{status: "installing"}}} ->
        Logger.info("Update / Start", car_id: data.car.id)

        {:ok, update} =
          call(data.deps.log, :start_update, [data.car, [date: parse_timestamp(ts)]])

        {:next_state, {:updating, update},
         %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(15, data)]}

      %V{drive_state: %Drive{shift_state: shift_state}}
      when shift_state in ["D", "N", "R"] ->
        Logger.info("Driving / Start", car_id: data.car.id)

        {:ok, drive} = call(data.deps.log, :start_drive, [data.car])
        {:ok, pos} = call(data.deps.log, :insert_position, [drive, create_position(vehicle)])
        geofence = call(data.deps.locations, :find_geofence, [pos])

        now = DateTime.utc_now()

        {:next_state, {:driving, :available, drive},
         %Data{data | last_state_change: now, last_used: now, geofence: geofence},
         [broadcast_summary(), schedule_fetch(@driving_interval, data)]}

      %V{charge_state: %Charge{charging_state: charging_state, battery_level: lvl}}
      when charging_state in ["Starting", "Charging"] ->
        alias Locations.GeoFence

        position = create_position(vehicle)

        {:ok, cproc} =
          call(data.deps.log, :start_charging_process, [
            data.car,
            position,
            [lookup_address: !data.import?]
          ])

        :ok = insert_charge(cproc, vehicle, data)

        ["Charging", "SOC: #{lvl}%", with(%GeoFence{name: name} <- cproc.geofence, do: name)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" / ")
        |> Logger.info(car_id: data.car.id)

        {:next_state, {:charging, cproc},
         %Data{data | last_state_change: DateTime.utc_now(), last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(5, data)]}

      _ ->
        try_to_suspend(vehicle, :online, data)
    end
  end

  #### :charging

  def handle_event(:internal, {:update, {:offline, _vehicle}}, {:charging, _}, data) do
    Logger.warn("Vehicle went offline while charging", car_id: data.car.id)

    {:keep_state_and_data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:charging, cproc}, data) do
    case vehicle.charge_state.charging_state do
      charging_state when charging_state in ["Starting", "Charging"] ->
        :ok = insert_charge(cproc, vehicle, data)

        interval =
          vehicle.charge_state
          |> Map.get(:charger_power)
          |> determince_interval()

        {:next_state, {:charging, cproc}, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(interval, data)]}

      state ->
        {:ok, _pos} = call(data.deps.log, :insert_position, [data.car, create_position(vehicle)])
        :ok = insert_charge(cproc, vehicle, data)

        {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [cproc])

        Logger.info("Charging / #{state} / #{added} kWh – #{duration} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :driving

  #### msg: :offline

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, :available, drive}, data) do
    Logger.warn("Vehicle went offline while driving", car_id: data.car.id)

    {:next_state, {:driving, {:unavailable, 0}, drive},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}
  end

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, {:unavailable, n}, drv}, data)
      when n < 15 do
    {:next_state, {:driving, {:unavailable, n + 1}, drv},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}
  end

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, {:unavailable, _n}, drv}, data) do
    {:next_state, {:driving, {:offline, data.last_response}, drv},
     %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}
  end

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, {:offline, _last}, nil}, data) do
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}
  end

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, {:offline, last}, drive}, data) do
    offline_since = parse_timestamp(last.drive_state.timestamp)

    case diff_seconds(DateTime.utc_now(), offline_since) / 60 do
      min when min >= @drive_timout_min ->
        timeout_drive(drive, data)

        {:next_state, {:driving, {:offline, last}, nil},
         %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}

      _min ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}
    end
  end

  def handle_event(:internal, {:update, {:online, now}}, {:driving, {:offline, last}, drv}, data) do
    offline_start = parse_timestamp(last.drive_state.timestamp)
    offline_end = parse_timestamp(now.drive_state.timestamp)

    offline_min = DateTime.diff(offline_end, offline_start, :second) / 60

    has_gained_range? =
      now.charge_state.ideal_battery_range - last.charge_state.ideal_battery_range > 5

    Logger.info("Vehicle came back online after #{round(offline_min)} min", car_id: data.car.id)

    cond do
      has_gained_range? and offline_min >= 5 ->
        unless is_nil(drv), do: timeout_drive(drv, data)

        {:ok, cproc} =
          call(data.deps.log, :start_charging_process, [
            data.car,
            create_position(last),
            [lookup_address: !data.import?]
          ])

        :ok = insert_charge(cproc, put_charge_defaults(last), data)
        :ok = insert_charge(cproc, put_charge_defaults(now), data)

        {:ok, %Log.ChargingProcess{charge_energy_added: added}} =
          call(data.deps.log, :complete_charging_process, [cproc])

        Logger.info("Vehicle was charged while being offline: #{added} kWh", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      not has_gained_range? and offline_min >= @drive_timout_min ->
        unless is_nil(drv), do: timeout_drive(drv, data)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}

      not is_nil(drv) ->
        {:next_state, {:driving, :available, drv}, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, now}}}}
    end
  end

  #### msg: asleep

  def handle_event(:internal, {:update, {:asleep, _vehicle}}, {:driving, _, drv}, data) do
    unless is_nil(drv), do: timeout_drive(drv, data)
    {:next_state, :start, data, schedule_fetch(data)}
  end

  #### msg: :online

  def handle_event(:internal, {:update, {:online, _} = e}, {:driving, {:unavailable, _}, drv}, d) do
    Logger.info("Vehicle is back online", car_id: d.car.id)

    {:next_state, {:driving, :available, drv}, %Data{d | last_used: DateTime.utc_now()},
     {:next_event, :internal, {:update, e}}}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:driving, :available, drv}, data) do
    case get(vehicle, [:drive_state, :shift_state]) do
      shift_state when shift_state in ["D", "R", "N"] ->
        {:ok, pos} = call(data.deps.log, :insert_position, [drv, create_position(vehicle)])
        geofence = call(data.deps.locations, :find_geofence, [pos])

        {:next_state, {:driving, :available, drv},
         %Data{data | last_used: DateTime.utc_now(), geofence: geofence},
         [broadcast_summary(), schedule_fetch(@driving_interval, data)]}

      shift_state when is_nil(shift_state) or shift_state == "P" ->
        {:ok, %Log.Drive{distance: km, duration_min: min}} =
          call(data.deps.log, :close_drive, [drv, [lookup_address: !data.import?]])

        Logger.info("Driving / Ended / #{km && round(km)} km – #{min} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :updating

  def handle_event(:internal, {:update, {:offline, _}}, {:updating, _update_id}, data) do
    Logger.warn("Vehicle went offline while updating", car_id: data.car.id)
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:updating, update}, data) do
    alias VehicleState.SoftwareUpdate, as: SW

    case vehicle.vehicle_state do
      nil ->
        Logger.warn("Update / empty vehicle_state", car_id: data.car.id)
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}

      %VehicleState{software_update: nil} ->
        Logger.warn("Update / empty payload:\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}

      %VehicleState{software_update: %SW{status: "installing"}} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(15, data)}

      %VehicleState{software_update: %SW{status: "available"} = update} ->
        {:ok, %Log.Update{}} = call(data.deps.log, :cancel_update, [update])

        Logger.warn("Update canceled:\n\n#{inspect(update, pretty: true)}",
          car_id: data.car.id
        )

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      %VehicleState{timestamp: ts, car_version: vsn, software_update: %SW{} = software_update} ->
        if software_update.status != "" do
          Logger.error(
            "Unexpected update status: #{software_update.status}\n\n#{
              inspect(software_update, pretty: true)
            }",
            car_id: data.car.id
          )
        end

        {:ok, %Log.Update{}} =
          call(data.deps.log, :finish_update, [update, vsn, [date: parse_timestamp(ts)]])

        Logger.info("Update / Installed #{vsn}", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :asleep / :offline

  def handle_event(:internal, {:update, {state, _}}, {state, @asleep_interval}, data)
      when state in [:asleep, :offline] do
    {:keep_state_and_data, schedule_fetch(@asleep_interval, data)}
  end

  def handle_event(:internal, {:update, {state, _}}, {state, interval}, data)
      when state in [:asleep, :offline] do
    {:next_state, {state, min(interval * 2, @asleep_interval)}, data,
     schedule_fetch(interval, data)}
  end

  def handle_event(:internal, {:update, {:offline, _}}, {:asleep, _interval}, data) do
    {:next_state, :start, data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:asleep, _}}, {:offline, _interval}, data) do
    {:next_state, :start, data, schedule_fetch(data)}
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

  def handle_event(:internal, {:update, {:offline, _}}, {:suspended, _}, data) do
    {:next_state, :start, data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:asleep, _}}, {:suspended, _}, data) do
    {:next_state, :start, data, schedule_fetch(data)}
  end

  # Private

  defp restore_last_knwon_values(vehicle, data) do
    with %Vehicle{drive_state: nil, charge_state: nil, climate_state: nil} <- vehicle,
         %Log.Position{} = position <- call(data.deps.log, :get_latest_position, [data.car]) do
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

  defp create_position(%Vehicle{} = vehicle) do
    %{
      date: parse_timestamp(vehicle.drive_state.timestamp),
      latitude: vehicle.drive_state.latitude,
      longitude: vehicle.drive_state.longitude,
      speed: Convert.mph_to_kmh(vehicle.drive_state.speed),
      power: with(n when is_number(n) <- vehicle.drive_state.power, do: n * 1.0),
      battery_level: vehicle.charge_state.battery_level,
      usable_battery_level: vehicle.charge_state.usable_battery_level,
      outside_temp: vehicle.climate_state.outside_temp,
      inside_temp: vehicle.climate_state.inside_temp,
      odometer: Convert.miles_to_km(vehicle.vehicle_state.odometer, 6),
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 1),
      est_battery_range_km: Convert.miles_to_km(vehicle.charge_state.est_battery_range, 1),
      rated_battery_range_km: Convert.miles_to_km(vehicle.charge_state.battery_range, 1),
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
      usable_battery_level: vehicle.charge_state.usable_battery_level,
      charge_energy_added: vehicle.charge_state.charge_energy_added,
      charger_actual_current: vehicle.charge_state.charger_actual_current,
      charger_phases: vehicle.charge_state.charger_phases,
      charger_pilot_current: vehicle.charge_state.charger_pilot_current,
      charger_power: vehicle.charge_state.charger_power || 0,
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

    case call(data.deps.log, :insert_charge, [charging_process, attrs]) do
      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
            Enum.reduce(opts, message, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        Logger.warn("Invalid charge data: #{inspect(errors, pretty: true)}", car_id: data.car.id)

      {:ok, _charge} ->
        :ok
    end
  end

  defp parse_timestamp(ts) do
    DateTime.from_unix!(ts, :millisecond)
  end

  defp try_to_suspend(vehicle, current_state, %Data{car: %{settings: settings} = car} = data) do
    idle_min = diff_seconds(DateTime.utc_now(), data.last_used) / 60
    suspend = idle_min >= settings.suspend_after_idle_min

    case can_fall_asleep(vehicle, data) do
      {:error, reason} when reason in [:sleep_mode_disabled, :sleep_mode_disabled_at_location] ->
        {:keep_state_and_data, [broadcast_summary(), schedule_fetch(30, data)]}

      {:error, :sentry_mode} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(30, data)]}

      {:error, :preconditioning} ->
        if suspend, do: Logger.warn("Preconditioning prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}

      {:error, :user_present} ->
        if suspend, do: Logger.warn("Present user prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(data)}

      {:error, :unlocked} ->
        if suspend,
          do: Logger.warn("Vehicle cannot to go to sleep because it is unlocked", car_id: car.id)

        {:keep_state_and_data, [broadcast_summary(), schedule_fetch(data)]}

      {:error, :shift_state} ->
        if suspend,
          do: Logger.warn("Shift state reading prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(data)}

      {:error, :temp_reading} ->
        if suspend,
          do: Logger.warn("Temperature readings prevents car to go to sleep", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(data)}

      :ok ->
        if suspend do
          Logger.info("Suspending logging", car_id: car.id)

          {:ok, _pos} = call(data.deps.log, :insert_position, [car, create_position(vehicle)])

          {:next_state, {:suspended, current_state},
           %Data{data | last_state_change: DateTime.utc_now()},
           [broadcast_summary(), schedule_fetch(settings.suspend_min, :minutes, data)]}
        else
          {:keep_state_and_data, [broadcast_summary(), schedule_fetch(15, data)]}
        end
    end
  end

  defp can_fall_asleep(vehicle, %Data{car: car, deps: deps}) do
    {:ok, may_fall_asleep} =
      call(deps.locations, :may_fall_asleep_at?, [car, vehicle.drive_state])

    case {vehicle, car.settings, may_fall_asleep} do
      {%Vehicle{}, %CarSettings{sleep_mode_enabled: false}, false} ->
        {:error, :sleep_mode_disabled}

      {%Vehicle{}, %CarSettings{sleep_mode_enabled: true}, false} ->
        {:error, :sleep_mode_disabled_at_location}

      {%Vehicle{vehicle_state: %VehicleState{is_user_present: true}}, _, true} ->
        {:error, :user_present}

      {%Vehicle{climate_state: %Climate{is_preconditioning: true}}, _, true} ->
        {:error, :preconditioning}

      {%Vehicle{vehicle_state: %VehicleState{sentry_mode: true}}, _, true} ->
        {:error, :sentry_mode}

      {%Vehicle{vehicle_state: %VehicleState{locked: false}},
       %CarSettings{req_not_unlocked: true}, true} ->
        {:error, :unlocked}

      {%Vehicle{drive_state: %Drive{shift_state: shift_state}},
       %CarSettings{req_no_shift_state_reading: true}, true}
      when not is_nil(shift_state) ->
        {:error, :shift_state}

      {%Vehicle{climate_state: %Climate{outside_temp: out_t, inside_temp: in_t}},
       %CarSettings{req_no_temp_reading: true}, true}
      when not is_nil(out_t) or not is_nil(in_t) ->
        {:error, :temp_reading}

      {%Vehicle{}, %CarSettings{}, true} ->
        :ok
    end
  end

  defp timeout_drive(drive, %Data{} = data) do
    {:ok, %Log.Drive{distance: km, duration_min: min}} =
      call(data.deps.log, :close_drive, [drive, [lookup_address: !data.import?]])

    Logger.info("Driving / Timeout / #{km && round(km)} km – #{min} min", car_id: data.car.id)
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

  def synchronize_updates(%Vehicle{vehicle_state: vehicle_state}, data) do
    case vehicle_state do
      %VehicleState{timestamp: ts, car_version: vsn} when is_binary(vsn) ->
        insert_update = fn ->
          call(data.deps.log, :insert_missed_update, [data.car, vsn, [date: parse_timestamp(ts)]])
        end

        case call(data.deps.log, :get_latest_update, [data.car]) do
          %Log.Update{version: last_vsn} when last_vsn < vsn ->
            with {:ok, _update} <- insert_update.() do
              Logger.info("Logged missing software udpate: #{vsn}", car_id: data.car.id)
              :ok
            end

          nil ->
            with {:ok, _update} <- insert_update.(), do: :ok

          _ ->
            Logger.debug("No missed updates", car_id: data.car.id)
            :ok
        end

      vehicle_state ->
        Logger.warn("Unexpected software version: #{inspect(vehicle_state, pretty: true)}",
          car_id: data.car.id
        )

        :ok
    end
  end

  defp summary_topic(car_id) when is_number(car_id), do: "#{__MODULE__}/summary/#{car_id}"
  defp fetch_topic(car_id) when is_number(car_id), do: "#{__MODULE__}/fetch/#{car_id}"

  defp determince_interval(n) when is_nil(n) or n <= 0, do: 5
  defp determince_interval(n), do: round(250 / n) |> min(20) |> max(5)

  defp fuse_name(:vehicle_not_found, car_id), do: :"#{__MODULE__}_#{car_id}_not_found"
  defp fuse_name(:api_error, car_id), do: :"#{__MODULE__}_#{car_id}_api_error"

  defp broadcast_summary, do: {:next_event, :internal, :broadcast_summary}
  defp broadcast_fetch(status), do: {:next_event, :internal, {:broadcast_fetch, status}}

  defp schedule_position_storing do
    {{:timeout, :store_position}, :timer.minutes(5), :store_position}
  end

  defp date_opts(%Vehicle{drive_state: %Drive{timestamp: nil}}), do: []
  defp date_opts(%Vehicle{drive_state: %Drive{timestamp: ts}}), do: [date: parse_timestamp(ts)]
  defp date_opts(%Vehicle{}), do: []

  defp schedule_fetch(%Data{} = data), do: schedule_fetch(10, :seconds, data)
  defp schedule_fetch(n, %Data{} = data), do: schedule_fetch(n, :seconds, data)

  defp schedule_fetch(_n, _unit, %Data{import?: true}), do: {:state_timeout, 0, :fetch}
  if Mix.env() == :test, do: defp(schedule_fetch(n, _, _), do: {:state_timeout, round(n), :fetch})
  defp schedule_fetch(n, unit, _), do: {:state_timeout, round(apply(:timer, unit, [n])), :fetch}

  case(Mix.env()) do
    :test -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :millisecond)
    _____ -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :second)
  end

  defp get(struct, keys) do
    Enum.reduce(keys, struct, fn key, acc -> if acc, do: Map.get(acc, key) end)
  end
end
