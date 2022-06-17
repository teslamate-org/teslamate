defmodule TeslaMate.Vehicles.Vehicle do
  use GenStateMachine

  require Logger

  alias __MODULE__.Summary
  alias TeslaMate.{Vehicles, Api, Log, Locations, Settings, Convert, Repo, Terrain}
  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.Car

  alias TeslaApi.Vehicle.State.{Climate, VehicleState, Drive, Charge, VehicleConfig}
  alias TeslaApi.{Stream, Vehicle}

  import Core.Dependency, only: [call: 3, call: 2]

  defmodule Data do
    defstruct car: nil,
              last_used: nil,
              last_response: nil,
              last_state_change: nil,
              elevation: nil,
              geofence: nil,
              deps: %{},
              task: nil,
              import?: false,
              stream_pid: nil
  end

  @asleep_interval 30
  @driving_interval 2.5

  @drive_timout_min 15

  # Static

  def identify(%Vehicle{display_name: name, vehicle_config: config}) do
    case config do
      %VehicleConfig{
        car_type: type,
        trim_badging: trim_badging,
        exterior_color: exterior_color,
        wheel_type: wheel_type,
        spoiler_type: spoiler_type
      } ->
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
              "lychee" -> "S"
              "tamarind" -> "X"
              _ -> nil
            end
          end

        marketing_name =
          case {model, trim_badging, type} do
            {"S", "100D", "lychee"} -> "LR"
            {"S", "P100D", "lychee"} -> "Plaid"
            {"3", "P74D", _} -> "LR AWD Performance"
            {"3", "74D", _} -> "LR AWD"
            {"3", "74", _} -> "LR"
            {"3", "62", _} -> "MR"
            {"3", "50", _} -> "SR+"
            {"X", "100D", "tamarind"} -> "LR"
            {"X", "P100D", "tamarind"} -> "Plaid"
            {"Y", "P74D", _} -> "LR AWD Performance"
            {"Y", "74D", _} -> "LR AWD"
            {_model, _trim, _type} -> nil
          end

        {:ok,
         %{
           model: model,
           name: name,
           trim_badging: trim_badging,
           marketing_name: marketing_name,
           exterior_color: exterior_color,
           spoiler_type: spoiler_type,
           wheel_type: wheel_type
         }}

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
    %Car{settings: %CarSettings{}} = car = Keyword.fetch!(opts, :car)

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
        elevation: data.elevation,
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
     [{:reply, from, :ok}, broadcast_summary(), schedule_fetch(1, data)]}
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

  def handle_event({:call, from}, :suspend_logging, _online, %Data{car: car} = data) do
    with {:ok, vehicle} <- fetch_strict(car.eid, data.deps),
         :ok <- can_fall_asleep(vehicle, data) do
      Logger.info("Suspending logging [Triggered manually]", car_id: car.id)

      {:ok, _pos} = call(data.deps.log, :insert_position, [car, create_position(vehicle, data)])

      suspend_min =
        case {data.car.settings, streaming?(data)} do
          {%CarSettings{use_streaming_api: true}, true} -> 30
          {%CarSettings{suspend_min: s}, _} -> s
        end

      {:next_state, {:suspended, :online},
       %Data{data | last_state_change: DateTime.utc_now(), last_response: vehicle, task: nil},
       [
         {:reply, from, :ok},
         broadcast_fetch(false),
         broadcast_summary(),
         schedule_fetch(suspend_min, :minutes, data)
       ]}
    else
      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}
    end
  end

  ## Info

  def handle_event(:info, {ref, fetch_result}, state, %Data{task: %Task{ref: ref}} = data)
      when is_reference(ref) do
    data = %Data{data | task: nil}

    case fetch_result do
      {:ok, %Vehicle{state: "online"} = vehicle} ->
        case {vehicle, data} do
          {%Vehicle{drive_state: %Drive{timestamp: now}},
           %Data{last_response: %Vehicle{drive_state: %Drive{timestamp: last}}}}
          when is_number(now) and is_number(last) and now < last ->
            drive_states = %{now: vehicle.drive_state, last: data.last_response.drive_state}

            Logger.warning(
              "Discarded stale fetch result: #{inspect(drive_states, pretty: true)}",
              car_id: data.car.id
            )

            {:keep_state, data, [broadcast_fetch(false), schedule_fetch(0, data)]}

          {%Vehicle{
             drive_state: %Drive{},
             charge_state: %Charge{},
             climate_state: %Climate{},
             vehicle_state: %VehicleState{},
             vehicle_config: %VehicleConfig{}
           }, %Data{}} ->
            {:keep_state, %Data{data | last_response: vehicle},
             [broadcast_fetch(false), {:next_event, :internal, {:update, {:online, vehicle}}}]}

          {%Vehicle{}, %Data{}} ->
            Logger.warning("Discarded incomplete fetch result", car_id: data.car.id)
            {:keep_state, data, [broadcast_fetch(false), schedule_fetch(data)]}
        end

      {:ok, %Vehicle{state: state} = vehicle} when state in ["offline", "asleep"] ->
        data =
          with %Data{last_response: nil} <- data do
            {last_response, geofence} = restore_last_knwon_values(vehicle, data)
            %Data{data | last_response: last_response, geofence: geofence}
          end

        {:keep_state, data,
         [
           broadcast_fetch(false),
           {:next_event, :internal, {:update, {String.to_existing_atom(state), vehicle}}}
         ]}

      {:ok, %Vehicle{state: state} = vehicle} ->
        Logger.warning(
          "Error / unknown vehicle state #{inspect(state)}\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state, data, [broadcast_fetch(false), schedule_fetch(data)]}

      {:error, :closed} ->
        Logger.warning("Error / connection closed", car_id: data.car.id)
        {:keep_state, data, [broadcast_fetch(false), schedule_fetch(5, data)]}

      {:error, :vehicle_in_service} ->
        Logger.info("Vehicle is currently in service", car_id: data.car.id)

        case state do
          {:driving, _, %Log.Drive{} = drive} ->
            {:ok, %Log.Drive{distance: km, duration_min: min}} =
              call(data.deps.log, :close_drive, [drive])

            :ok = disconnect_stream(data)

            Logger.info("Driving / Aborted / #{km && round(km)} km – #{min} min",
              car_id: data.car.id
            )

            {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
             [broadcast_fetch(false), broadcast_summary(), schedule_fetch(60, data)]}

          _ ->
            {:keep_state, data, [broadcast_fetch(false), schedule_fetch(60, data)]}
        end

      {:error, :not_signed_in} ->
        Logger.error("Error / not_signed_in", car_id: data.car.id)

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

        unless reason in [:timeout, :unauthorized] do
          :ok = fuse_name(:api_error, data.car.id) |> :fuse.melt()
        end

        interval =
          case state do
            {:driving, _, _} -> 10
            {:charging, _} -> 15
            :online -> 20
            _ -> 30
          end

        {:keep_state, data,
         [broadcast_fetch(false), broadcast_summary(), schedule_fetch(interval, data)]}
    end
  end

  ### Streaming API

  #### Online

  def handle_event(:info, {:stream, %Stream.Data{} = stream_data}, :online, data) do
    stale_stream_data? = stale?(stream_data, data.last_response)

    case stream_data do
      %Stream.Data{} when stale_stream_data? ->
        Logger.warn("Received stale stream data: #{inspect(stream_data)}", car_id: data.car.id)
        :keep_state_and_data

      %Stream.Data{shift_state: shift_state} when shift_state in ~w(D N R) ->
        Logger.info("Start of drive initiated by: #{inspect(stream_data)}")

        %{elevation: elevation} = position = create_position(stream_data, data)
        {drive, data} = start_drive(position, data)

        vehicle = merge(data.last_response, stream_data, time: true)

        {:next_state, {:driving, :available, drive},
         %Data{data | last_response: vehicle, elevation: elevation},
         [broadcast_summary(), schedule_fetch(0, data)]}

      %Stream.Data{shift_state: nil, power: power} when is_number(power) and power < 0 ->
        Logger.info("Charging detected: #{power} kW", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(0, data)}

      %Stream.Data{} ->
        Logger.debug(inspect(stream_data), car_id: data.car.id)
        :keep_state_and_data
    end
  end

  #### Driving

  def handle_event(:info, {:stream, %Stream.Data{} = stream_data}, {:driving, status, drv}, data) do
    case {status, stream_data} do
      {:available, %Stream.Data{shift_state: shift_state}} when shift_state in ~w(D N R) ->
        {:ok, %{elevation: elevation}} =
          call(data.deps.log, :insert_position, [drv, create_position(stream_data, data)])

        vehicle = merge(data.last_response, stream_data)
        now = DateTime.utc_now()

        {:keep_state, %Data{data | last_used: now, last_response: vehicle, elevation: elevation},
         broadcast_summary()}

      {_status, %Stream.Data{}} ->
        {:keep_state_and_data, schedule_fetch(0, data)}
    end
  end

  #### Suspended

  def handle_event(:info, {:stream, %Stream.Data{} = stream_data}, {:suspended, prev_state}, data) do
    stale_stream_data? = stale?(stream_data, data.last_response)

    case stream_data do
      %Stream.Data{} when stale_stream_data? ->
        Logger.warn("Received stale stream data: #{inspect(stream_data)}", car_id: data.car.id)
        :keep_state_and_data

      %Stream.Data{shift_state: shift_state} when shift_state in ~w(D N R) ->
        Logger.info("Start of drive initiated by: #{inspect(stream_data)}")

        %{elevation: elevation} = position = create_position(stream_data, data)
        {drive, data} = start_drive(position, data)

        vehicle = merge(data.last_response, stream_data, time: true)

        {:next_state, {:driving, :available, drive},
         %Data{data | last_response: vehicle, elevation: elevation},
         [broadcast_summary(), schedule_fetch(0, data)]}

      %Stream.Data{shift_state: s, power: power}
      when s in [nil, "P"] and is_number(power) and power < 0 ->
        Logger.info("Charging detected: #{power} kW", car_id: data.car.id)
        {:next_state, prev_state, data, schedule_fetch(0, data)}

      %Stream.Data{} ->
        Logger.debug(inspect(stream_data), car_id: data.car.id)
        :keep_state_and_data
    end
  end

  def handle_event(:info, {:stream, :inactive}, {:suspended, _prev_state}, data) do
    Logger.info("Fetching vehicle state ...", car_id: data.car.id)
    {:keep_state_and_data, {:next_event, :internal, :fetch_state}}
  end

  def handle_event(:info, {_ref, {state, %Vehicle{}} = event}, {:suspended, _}, data)
      when state in [:asleep, :offline] do
    {:next_state, :start, data, {:next_event, :internal, {:update, event}}}
  end

  def handle_event(:info, {_ref, {:online, %Vehicle{}}}, {:suspended, _}, _data) do
    :keep_state_and_data
  end

  #### Rest

  def handle_event(:info, {:stream, msg}, _state, data)
      when msg in [:too_many_disconnects, :tokens_expired] do
    Logger.info("Creating new connection … ", car_id: data.car.id)

    ref = Process.monitor(data.stream_pid)
    :ok = disconnect_stream(data)

    receive do
      {:DOWN, ^ref, :process, _object, _reason} -> :ok
    after
      1000 -> :continue
    end

    {:ok, pid} = connect_stream(data)

    {:keep_state, %Data{data | stream_pid: pid}}
  end

  def handle_event(:info, {:stream, stream_data}, _state, data) do
    Logger.info("Received stream data: #{inspect(stream_data)}", car_id: data.car.id)
    :keep_state_and_data
  end

  ###

  def handle_event(:info, {ref, result}, _state, data) when is_reference(ref) do
    unless match?({:ok, %Vehicle{}}, result) do
      Logger.info("Unhandled fetch result: #{inspect(result, pretty: true)}", car_id: data.car.id)
    end

    :keep_state_and_data
  end

  def handle_event(:info, {:DOWN, r, :process, _, :normal}, _, %Data{task: %Task{ref: r}} = data) do
    Logger.warning("Cleared data.task!", car_id: data.car.id)
    {:keep_state, %Data{data | task: nil}}
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, %CarSettings{} = settings, state, data) do
    Logger.debug("Received settings: #{inspect(settings, pretty: true)}", car_id: data.car.id)

    state =
      case state do
        s when is_tuple(s) -> elem(s, 0)
        s when is_atom(s) -> s
      end

    stream_pid =
      case {settings, state, data} do
        {%CarSettings{use_streaming_api: false}, _state, %Data{stream_pid: pid}}
        when is_pid(pid) ->
          :ok = disconnect_stream(data)
          nil

        {%CarSettings{use_streaming_api: true}, _state, %Data{stream_pid: pid}}
        when is_pid(pid) ->
          pid

        {%CarSettings{use_streaming_api: true}, state, %Data{stream_pid: nil}}
        when state in [:online, :driving, :suspended] ->
          {:ok, pid} = connect_stream(data)
          pid

        {%CarSettings{}, _state, %Data{}} ->
          nil
      end

    {:keep_state,
     %Data{data | car: Map.put(data.car, :settings, settings), stream_pid: stream_pid}}
  end

  def handle_event(:info, message, _state, data) do
    Logger.info("Unhandled message: #{inspect(message, pretty: true)}", car_id: data.car.id)
    :keep_state_and_data
  end

  ## Internal Events

  ### Fetch

  @impl true
  def handle_event(event, :fetch, state, %Data{task: nil} = data)
      when event in [:state_timeout, :internal] do
    task =
      Task.async(fn ->
        fetch(data, expected_state: state)
      end)

    {:keep_state, %Data{data | task: task}, broadcast_fetch(true)}
  end

  def handle_event(event, :fetch, _state, %Data{task: %Task{}} = data)
      when event in [:state_timeout, :internal] do
    Logger.info("Fetch already in progress ...", car_id: data.car.id)
    :keep_state_and_data
  end

  def handle_event(:internal, :fetch_state, _state, %Data{car: car} = data) do
    Task.async(fn ->
      with {:ok, %Vehicle{state: state} = vehicle} when is_binary(state) <-
             call(data.deps.api, :get_vehicle, [car.eid]) do
        {String.to_existing_atom(state), vehicle}
      end
    end)

    :keep_state_and_data
  end

  ### Broadcast Summary

  def handle_event(:internal, :broadcast_summary, state, %Data{last_response: vehicle} = data) do
    payload =
      Summary.into(vehicle, %{
        state: state,
        since: data.last_state_change,
        healthy?: healthy?(data.car.id),
        elevation: data.elevation,
        geofence: data.geofence,
        car: data.car
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

  def handle_event({:timeout, :store_position}, :store_position, state, data)
      when state == :online or (is_tuple(state) and elem(state, 0) == :charging) do
    Logger.debug("Storing position ...", car_id: data.car.id)

    {:ok, _pos} =
      call(data.deps.log, :insert_position, [data.car, create_position(data.last_response, data)])

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

    :ok = disconnect_stream(data)

    {:next_state, {:asleep, @asleep_interval},
     %Data{data | last_state_change: last_state_change, stream_pid: nil},
     [broadcast_summary(), schedule_fetch(data)]}
  end

  def handle_event(:internal, {:update, {:offline, vehicle}}, :start, data) do
    Logger.info("Start / :offline", car_id: data.car.id)

    {:ok, %Log.State{start_date: last_state_change}} =
      call(data.deps.log, :start_state, [data.car, :offline, date_opts(vehicle)])

    :ok = disconnect_stream(data)

    {:next_state, {:offline, @asleep_interval},
     %Data{data | last_state_change: last_state_change, stream_pid: nil},
     [broadcast_summary(), schedule_fetch(data)]}
  end

  def handle_event(:internal, {:update, {:online, vehicle}} = evt, :start, data) do
    Logger.info("Start / :online", car_id: data.car.id)

    {:ok, attrs} = identify(vehicle)

    opts =
      case data do
        %Data{import?: true} -> [preload: []]
        %Data{} -> [preload: [:settings]]
      end

    {:ok, {car, last_state_change, geofence}} =
      Repo.transaction(fn ->
        {:ok, car} = call(data.deps.log, :update_car, [data.car, attrs, opts])

        synchronize_updates(vehicle, data)

        {:ok, %Log.State{start_date: last_state_change}} =
          call(data.deps.log, :start_state, [car, :online, date_opts(vehicle)])

        {:ok, pos} = call(data.deps.log, :insert_position, [car, create_position(vehicle, data)])
        geofence = call(data.deps.locations, :find_geofence, [pos])

        {car, last_state_change, geofence}
      end)

    stream_pid =
      case data do
        %Data{stream_pid: nil, car: %Car{settings: %CarSettings{use_streaming_api: true}}} ->
          {:ok, pid} = connect_stream(data)
          pid

        %Data{stream_pid: pid} when is_pid(pid) ->
          pid

        %Data{} ->
          nil
      end

    {:next_state, :online,
     %Data{
       data
       | car: car,
         last_state_change: last_state_change,
         geofence: geofence,
         stream_pid: stream_pid
     }, [broadcast_summary(), {:next_event, :internal, evt}, schedule_position_storing()]}
  end

  #### :online

  def handle_event(:internal, {:update, {event, _vehicle}}, :online, data)
      when event in [:offline, :asleep] do
    {:next_state, :start, data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, state, data)
      when state == :online or (is_tuple(state) and elem(state, 0) == :suspended) do
    alias TeslaApi.Vehicle, as: V

    if match?({:suspended, _}, state) do
      duration_str =
        DateTime.utc_now()
        |> diff_seconds(data.last_used)
        |> Convert.sec_to_str()
        |> Enum.reject(&String.ends_with?(&1, "s"))
        |> Enum.join(" ")

      Logger.info("Vehicle is still online. Falling asleep for: #{duration_str}",
        car_id: data.car.id
      )
    end

    case vehicle do
      %V{vehicle_state: %VehicleState{timestamp: ts, software_update: %{status: "installing"}}} ->
        Logger.info("Update / Start", car_id: data.car.id)

        {:ok, update} =
          call(data.deps.log, :start_update, [data.car, [date: parse_timestamp(ts)]])

        :ok = disconnect_stream(data)

        {:next_state, {:updating, update},
         %Data{
           data
           | last_state_change: DateTime.utc_now(),
             last_used: DateTime.utc_now(),
             stream_pid: nil
         }, [broadcast_summary(), schedule_fetch(15, data)]}

      %V{drive_state: %Drive{shift_state: shift_state}} when shift_state in ~w(D N R) ->
        Logger.info("Start of drive initiated by: #{inspect(vehicle.drive_state)}")

        {drive, data} = start_drive(create_position(vehicle, data), data)

        {:next_state, {:driving, :available, drive}, data,
         [broadcast_summary(), schedule_fetch(@driving_interval, data)]}

      %V{charge_state: %Charge{charging_state: charging_state, battery_level: lvl}}
      when charging_state in ["Starting", "Charging"] ->
        position = create_position(vehicle, data)

        {:ok, cproc} =
          Repo.transaction(fn ->
            {:ok, cproc} =
              call(data.deps.log, :start_charging_process, [
                data.car,
                position,
                [lookup_address: !data.import?]
              ])

            :ok = insert_charge(cproc, vehicle, data)

            cproc
          end)

        ["Charging", "SOC: #{lvl}%", with(%GeoFence{name: name} <- cproc.geofence, do: name)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" / ")
        |> Logger.info(car_id: data.car.id)

        :ok = disconnect_stream(data)

        {:next_state, {:charging, cproc},
         %Data{
           data
           | last_state_change: DateTime.utc_now(),
             last_used: DateTime.utc_now(),
             stream_pid: nil
         }, [broadcast_summary(), schedule_fetch(5, data), schedule_position_storing()]}

      _ ->
        try_to_suspend(vehicle, state, data)
    end
  end

  #### :suspended

  def handle_event(:internal, {:update, {state, _}} = event, {:suspended, _}, data)
      when state in [:asleep, :offline] do
    {:next_state, :start, data, {:next_event, :internal, event}}
  end

  #### :charging

  def handle_event(:internal, {:update, {:offline, _vehicle}}, {:charging, _}, data) do
    Logger.warning("Vehicle went offline while charging", car_id: data.car.id)

    {:keep_state_and_data, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:asleep, _vehicle}} = event, {:charging, cproc}, data) do
    Logger.warning("Vehicle went asleep while charging (?)", car_id: data.car.id)

    {:ok, _} = call(data.deps.log, :complete_charging_process, [cproc])
    Logger.info("Charging / Aborted", car_id: data.car.id)

    {:next_state, :start, data, {:next_event, :internal, event}}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:charging, cproc}, data) do
    data = %Data{data | last_used: DateTime.utc_now()}

    case vehicle do
      %Vehicle{charge_state: %Charge{charging_state: charging_state}}
      when charging_state in ["Starting", "Charging"] ->
        :ok = insert_charge(cproc, vehicle, data)

        interval =
          vehicle.charge_state
          |> Map.get(:charger_power)
          |> determince_interval()

        {:next_state, {:charging, cproc}, data,
         [broadcast_summary(), schedule_fetch(interval, data)]}

      %Vehicle{charge_state: %Charge{charging_state: state}} ->
        Repo.transaction(fn ->
          {:ok, _} =
            call(data.deps.log, :insert_position, [data.car, create_position(vehicle, data)])

          :ok = insert_charge(cproc, vehicle, data)

          {:ok, %Log.ChargingProcess{duration_min: duration, charge_energy_added: added}} =
            call(data.deps.log, :complete_charging_process, [cproc])

          Logger.info("Charging / #{state} / #{added} kWh – #{duration} min", car_id: data.car.id)
        end)

        {:next_state, :start, data, {:next_event, :internal, {:update, {:online, vehicle}}}}
    end
  end

  #### :driving

  #### msg: :offline

  def handle_event(:internal, {:update, {:offline, _}}, {:driving, :available, drive}, data) do
    Logger.warning("Vehicle went offline while driving", car_id: data.car.id)

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
     %Data{data | last_used: DateTime.utc_now()}, [broadcast_summary(), schedule_fetch(30, data)]}
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
         %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(30, data)]}

      _min ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(30, data)}
    end
  end

  def handle_event(:internal, {:update, {:online, now}}, {:driving, {:offline, last}, drv}, data) do
    offline_start = parse_timestamp(last.drive_state.timestamp)
    offline_end = parse_timestamp(now.drive_state.timestamp)

    offline_min = DateTime.diff(offline_end, offline_start, :second) / 60

    has_gained_range? =
      nil not in [now.charge_state.ideal_battery_range, last.charge_state.ideal_battery_range] and
        now.charge_state.ideal_battery_range - last.charge_state.ideal_battery_range > 5

    Logger.info("Vehicle came back online after #{round(offline_min)} min", car_id: data.car.id)

    cond do
      has_gained_range? and offline_min >= 5 ->
        unless is_nil(drv), do: timeout_drive(drv, data)

        {:ok, %Log.ChargingProcess{charge_energy_added: added}} =
          Repo.transaction(fn ->
            {:ok, cproc} =
              call(data.deps.log, :start_charging_process, [
                data.car,
                create_position(last, data),
                [lookup_address: !data.import?]
              ])

            :ok = insert_charge(cproc, put_charge_defaults(last), data)
            :ok = insert_charge(cproc, put_charge_defaults(now), data)
            {:ok, cproc} = call(data.deps.log, :complete_charging_process, [cproc])

            cproc
          end)

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
    interval = if streaming?(data), do: 15, else: @driving_interval

    case vehicle do
      %Vehicle{drive_state: %Drive{shift_state: shift_state}} when shift_state in ~w(D N R) ->
        geofence =
          Repo.checkout(fn ->
            {:ok, pos} =
              call(data.deps.log, :insert_position, [drv, create_position(vehicle, data)])

            call(data.deps.locations, :find_geofence, [pos])
          end)

        {:keep_state, %Data{data | last_used: DateTime.utc_now(), geofence: geofence},
         [broadcast_summary(), schedule_fetch(interval, data)]}

      %Vehicle{drive_state: %Drive{shift_state: shift_state}} when shift_state in [nil, "P"] ->
        {:ok, {%Log.Drive{distance: km, duration_min: min}, geofence}} =
          Repo.transaction(fn ->
            {:ok, pos} =
              call(data.deps.log, :insert_position, [drv, create_position(vehicle, data)])

            geofence = call(data.deps.locations, :find_geofence, [pos])

            {:ok, drive} =
              call(data.deps.log, :close_drive, [drv, [lookup_address: !data.import?]])

            {drive, geofence}
          end)

        Logger.info("End of drive initiated by: #{inspect(vehicle.drive_state)}")
        Logger.info("Driving / Ended / #{km && round(km)} km – #{min} min", car_id: data.car.id)

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now(), geofence: geofence},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      %Vehicle{drive_state: nil} ->
        Logger.warning("drive_state is nil!", car_id: data.car.id)
        {:keep_state_and_data, schedule_fetch(interval, data)}
    end
  end

  #### :updating

  def handle_event(:internal, {:update, {:offline, _}}, {:updating, _update_id}, data) do
    Logger.warning("Vehicle went offline while updating", car_id: data.car.id)
    {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(data)}
  end

  def handle_event(:internal, {:update, {:online, vehicle}}, {:updating, update}, data) do
    alias VehicleState.SoftwareUpdate, as: SW

    case vehicle.vehicle_state do
      nil ->
        Logger.warning("Update / empty vehicle_state", car_id: data.car.id)
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}

      %VehicleState{software_update: nil} ->
        Logger.warning("Update / empty payload:\n\n#{inspect(vehicle, pretty: true)}",
          car_id: data.car.id
        )

        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(5, data)}

      %VehicleState{software_update: %SW{status: "installing"}} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()}, schedule_fetch(15, data)}

      %VehicleState{software_update: %SW{status: "available"} = update} ->
        {:ok, %Log.Update{}} = call(data.deps.log, :cancel_update, [update])

        Logger.warning("Update canceled:\n\n#{inspect(update, pretty: true)}",
          car_id: data.car.id
        )

        {:next_state, :start, %Data{data | last_used: DateTime.utc_now()},
         {:next_event, :internal, {:update, {:online, vehicle}}}}

      %VehicleState{timestamp: ts, car_version: vsn, software_update: %SW{} = software_update} ->
        if software_update.status != "" and
             not (software_update.status == "downloading" and software_update.install_perc == 100) do
          Logger.error(
            """
            Unexpected update status: #{software_update.status}

            #{inspect(software_update, pretty: true)}
            """,
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
    {:keep_state_and_data, [schedule_fetch(@asleep_interval, data), broadcast_summary()]}
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

  # Private

  defp restore_last_knwon_values(vehicle, data) do
    with %Vehicle{drive_state: nil, charge_state: nil, climate_state: nil} <- vehicle,
         %Log.Position{} = position <- call(data.deps.log, :get_latest_position, [data.car]) do
      drive = %Drive{
        latitude: position.latitude,
        longitude: position.longitude,
        shift_state: :unknown
      }

      to_miles = fn km ->
        with km when not is_nil(km) <- km do
          km |> Convert.km_to_miles(2) |> Decimal.to_float()
        end
      end

      charge = %Charge{
        ideal_battery_range: to_miles.(position.ideal_battery_range_km),
        est_battery_range: to_miles.(position.est_battery_range_km),
        battery_range: to_miles.(position.rated_battery_range_km),
        battery_level: position.battery_level,
        usable_battery_level: position.usable_battery_level,
        charge_energy_added: :unknown,
        charger_actual_current: :unknown,
        charger_phases: :unknown,
        charger_power: :unknown,
        charger_voltage: :unknown,
        charge_port_door_open: :unknown,
        scheduled_charging_start_time: :unknown,
        time_to_full_charge: :unknown
      }

      climate = %Climate{
        outside_temp: position.outside_temp,
        inside_temp: position.inside_temp
      }

      vehicle_state = %VehicleState{
        odometer: position.odometer |> Convert.km_to_miles(6),
        car_version:
          case call(data.deps.log, :get_latest_update, [data.car]) do
            %Log.Update{version: version} -> version
            _ -> nil
          end
      }

      vehicle = %Vehicle{
        vehicle
        | drive_state: drive,
          charge_state: charge,
          climate_state: climate,
          vehicle_state: vehicle_state
      }

      geofence = call(data.deps.locations, :find_geofence, [position])

      {vehicle, geofence}
    else
      _ -> {vehicle, nil}
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

  defp fetch_strict(id, deps) do
    alias Vehicle, as: V

    case call(deps.api, :get_vehicle_with_state, [id]) do
      {:ok, %V{drive_state: %Drive{}, charge_state: %Charge{}, climate_state: %Climate{}} = v} ->
        {:ok, v}

      {:ok, %V{}} ->
        {:error, :gateway_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @terrain (case Mix.env() do
              :test -> TerrainMock
              _ -> Terrain
            end)

  defp create_position(%Vehicle{} = vehicle, %Data{car: car}) do
    position = %{
      date: parse_timestamp(vehicle.drive_state.timestamp),
      latitude: vehicle.drive_state.latitude,
      longitude: vehicle.drive_state.longitude,
      speed: Convert.mph_to_kmh(vehicle.drive_state.speed),
      power: vehicle.drive_state.power,
      battery_level: vehicle.charge_state.battery_level,
      usable_battery_level: vehicle.charge_state.usable_battery_level,
      outside_temp: vehicle.climate_state.outside_temp,
      inside_temp: vehicle.climate_state.inside_temp,
      odometer: Convert.miles_to_km(vehicle.vehicle_state.odometer, 6),
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 2),
      est_battery_range_km: Convert.miles_to_km(vehicle.charge_state.est_battery_range, 2),
      rated_battery_range_km: Convert.miles_to_km(vehicle.charge_state.battery_range, 2),
      fan_status: vehicle.climate_state.fan_status,
      is_climate_on: vehicle.climate_state.is_climate_on,
      driver_temp_setting: vehicle.climate_state.driver_temp_setting,
      passenger_temp_setting: vehicle.climate_state.passenger_temp_setting,
      is_rear_defroster_on: vehicle.climate_state.is_rear_defroster_on,
      is_front_defroster_on: vehicle.climate_state.is_front_defroster_on,
      battery_heater_on: vehicle.charge_state.battery_heater_on,
      battery_heater: vehicle.climate_state.battery_heater,
      battery_heater_no_power: vehicle.climate_state.battery_heater_no_power,
      tpms_pressure_fl: vehicle.vehicle_state.tpms_pressure_fl,
      tpms_pressure_fr: vehicle.vehicle_state.tpms_pressure_fr,
      tpms_pressure_rl: vehicle.vehicle_state.tpms_pressure_rl,
      tpms_pressure_rr: vehicle.vehicle_state.tpms_pressure_rr
    }

    elevation =
      case car do
        %Car{settings: %CarSettings{use_streaming_api: true}} -> nil
        %Car{} -> @terrain.get_elevation({position.latitude, position.longitude})
      end

    Map.put(position, :elevation, elevation)
  end

  defp create_position(%Stream.Data{} = stream_data, %Data{}) do
    %{
      date: stream_data.time,
      latitude: stream_data.est_lat,
      longitude: stream_data.est_lng,
      power: stream_data.power,
      speed: Convert.mph_to_kmh(stream_data.speed),
      battery_level: stream_data.soc,
      elevation: stream_data.elevation,
      odometer: Convert.miles_to_km(stream_data.odometer, 6)
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
      ideal_battery_range_km: Convert.miles_to_km(vehicle.charge_state.ideal_battery_range, 2),
      rated_battery_range_km: Convert.miles_to_km(vehicle.charge_state.battery_range, 2),
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

        Logger.warning("Invalid charge data: #{inspect(errors, pretty: true)}",
          car_id: data.car.id
        )

      {:ok, _charge} ->
        :ok
    end
  end

  defp try_to_suspend(vehicle, current_state, %Data{car: car} = data) do
    {suspend_after_idle_min, suspend_min, i} =
      case {car.settings, streaming?(data)} do
        {%CarSettings{use_streaming_api: true}, true} -> {3, 30, 2}
        {%CarSettings{suspend_after_idle_min: i, suspend_min: s}, _} -> {i, s, 1}
      end

    suspend? = diff_seconds(DateTime.utc_now(), data.last_used) / 60 >= suspend_after_idle_min

    case can_fall_asleep(vehicle, data) do
      {:error, :sentry_mode} ->
        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(30 * i, data)]}

      {:error, :preconditioning} ->
        if suspend?, do: Logger.warning("Preconditioning ...", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(30 * i, data)]}

      {:error, :user_present} ->
        if suspend?, do: Logger.warning("User present ...", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(15, data)]}

      {:error, :downloading_update} ->
        if suspend?, do: Logger.warning("Downloading update ...", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(15 * i, data)]}

      {:error, :doors_open} ->
        if suspend?, do: Logger.warning("Doors open ...", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(15 * i, data)]}

      {:error, :trunk_open} ->
        if suspend?, do: Logger.warning("Trunk open ...", car_id: car.id)

        {:keep_state, %Data{data | last_used: DateTime.utc_now()},
         [broadcast_summary(), schedule_fetch(15 * i, data)]}

      {:error, :unlocked} ->
        if suspend?, do: Logger.warning("Unlocked ...", car_id: car.id)
        {:keep_state_and_data, [broadcast_summary(), schedule_fetch(15 * i, data)]}

      :ok ->
        if suspend? do
          {:ok, _pos} =
            call(data.deps.log, :insert_position, [car, create_position(vehicle, data)])

          events = [broadcast_summary(), schedule_fetch(suspend_min, :minutes, data)]

          case current_state do
            {:suspended, _} ->
              {:keep_state_and_data, events}

            _ ->
              Logger.info("Suspending logging", car_id: car.id)

              {:next_state, {:suspended, current_state},
               %Data{data | last_state_change: DateTime.utc_now()}, events}
          end
        else
          {:keep_state_and_data, [broadcast_summary(), schedule_fetch(15 * i, data)]}
        end
    end
  end

  defp can_fall_asleep(vehicle, %Data{car: car}) do
    case {vehicle, car.settings} do
      {%Vehicle{vehicle_state: %VehicleState{is_user_present: true}}, _} ->
        {:error, :user_present}

      {%Vehicle{climate_state: %Climate{is_preconditioning: true}}, _} ->
        {:error, :preconditioning}

      {%Vehicle{vehicle_state: %VehicleState{sentry_mode: true}}, _} ->
        {:error, :sentry_mode}

      {%Vehicle{
         vehicle_state: %VehicleState{
           software_update: %VehicleState.SoftwareUpdate{
             status: "downloading",
             download_perc: download_percentage
           }
         }
       }, _}
      when download_percentage < 100 ->
        {:error, :downloading_update}

      {%Vehicle{vehicle_state: %VehicleState{df: df, pf: pf, dr: dr, pr: pr}}, _}
      when is_number(df) and is_number(pf) and is_number(dr) and is_number(pr) and
             (df > 0 or pf > 0 or dr > 0 or pr > 0) ->
        {:error, :doors_open}

      {%Vehicle{vehicle_state: %VehicleState{ft: ft, rt: rt}}, _}
      when is_number(ft) and is_number(rt) and (ft > 0 or rt > 0) ->
        {:error, :trunk_open}

      {%Vehicle{vehicle_state: %VehicleState{locked: false}},
       %CarSettings{req_not_unlocked: true}} ->
        {:error, :unlocked}

      {%Vehicle{}, %CarSettings{}} ->
        :ok
    end
  end

  defp start_drive(position, %Data{car: car, deps: deps} = data) do
    Logger.info("Driving / Start", car_id: car.id)

    {:ok, {drive, geofence}} =
      Repo.transaction(fn ->
        {:ok, drive} = call(deps.log, :start_drive, [car])
        {:ok, pos} = call(deps.log, :insert_position, [drive, position])
        geofence = call(deps.locations, :find_geofence, [pos])
        {drive, geofence}
      end)

    now = DateTime.utc_now()
    data = %Data{data | last_state_change: now, last_used: now, geofence: geofence}

    {drive, data}
  end

  defp timeout_drive(drive, %Data{} = data) do
    {:ok, %Log.Drive{distance: km, duration_min: min}} =
      call(data.deps.log, :close_drive, [drive, [lookup_address: !data.import?]])

    Logger.info("Driving / Timeout / #{km && round(km)} km – #{min} min", car_id: data.car.id)
  end

  defp merge(%Vehicle{} = vehicle, %Stream.Data{} = stream_data, opts \\ []) do
    timestamp =
      if Keyword.get(opts, :time, false) do
        DateTime.to_unix(stream_data.time, :millisecond)
      else
        vehicle.drive_state.timestamp
      end

    %Vehicle{
      vehicle
      | drive_state: %Drive{
          vehicle.drive_state
          | timestamp: timestamp,
            latitude: stream_data.est_lat,
            longitude: stream_data.est_lng,
            speed: stream_data.speed,
            power: stream_data.power,
            heading: stream_data.est_heading,
            shift_state: stream_data.shift_state
        },
        charge_state: %Charge{
          vehicle.charge_state
          | battery_level: stream_data.soc
        },
        vehicle_state: %VehicleState{
          vehicle.vehicle_state
          | odometer: stream_data.odometer
        }
    }
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

  defp synchronize_updates(%Vehicle{vehicle_state: vehicle_state}, %Data{car: car} = data) do
    case vehicle_state do
      %VehicleState{timestamp: ts, car_version: vsn} when is_binary(vsn) ->
        case call(data.deps.log, :get_latest_update, [car]) do
          nil ->
            {:ok, _} =
              call(data.deps.log, :insert_missed_update, [car, vsn, [date: parse_timestamp(ts)]])

          %Log.Update{version: last_vsn} when is_binary(last_vsn) ->
            if normalize_version(last_vsn) < normalize_version(vsn) do
              Logger.info("Logged missing software udpate: #{vsn}", car_id: car.id)

              {:ok, _} =
                call(data.deps.log, :insert_missed_update, [car, vsn, [date: parse_timestamp(ts)]])
            end

          %Log.Update{version: nil} ->
            nil
        end

      error ->
        Logger.warning("Unexpected software version: #{inspect(error, pretty: true)}",
          car_id: car.id
        )
    end
  end

  defp normalize_version(vsn) when is_binary(vsn) do
    vsn
    |> String.split(" ", parts: 2)
    |> hd()
    |> String.split(".")
    |> Enum.map(&String.pad_leading(&1, 4, "0"))
  end

  defp stale?(%Stream.Data{} = stream_data, %Vehicle{} = last_response) do
    last_response_time =
      case last_response do
        %Vehicle{drive_state: %Drive{timestamp: t}} when is_number(t) -> parse_timestamp(t)
        %Vehicle{drive_state: %Drive{timestamp: %DateTime{} = t}} -> t
        _ -> nil
      end

    last_response_time != nil and DateTime.compare(last_response_time, stream_data.time) == :gt
  end

  defp streaming?(%Data{stream_pid: pid}), do: is_pid(pid) and Process.alive?(pid)

  defp connect_stream(%Data{car: car} = data) do
    Logger.info("Connecting ...", car_id: car.id)

    me = self()

    call(data.deps.api, :stream, [
      data.car.vid,
      fn stream_data -> send(me, {:stream, stream_data}) end
    ])
  end

  defp disconnect_stream(%Data{stream_pid: nil}), do: :ok

  defp disconnect_stream(%Data{stream_pid: pid} = data) when is_pid(pid) do
    Logger.info("Disconnecting ...", car_id: data.car.id)
    Stream.disconnect(pid)
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

  defp parse_timestamp(ts), do: DateTime.from_unix!(ts, :millisecond)

  defp schedule_fetch(%Data{} = data), do: schedule_fetch(10, :seconds, data)
  defp schedule_fetch(n, %Data{} = data), do: schedule_fetch(n, :seconds, data)

  defp schedule_fetch(_n, _unit, %Data{import?: true}), do: {:state_timeout, 0, :fetch}
  defp schedule_fetch(n, unit, _), do: {:state_timeout, fetch_timeout(n, unit), :fetch}

  case(Mix.env()) do
    :test -> defp fetch_timeout(n, _), do: round(n)
    _ -> defp fetch_timeout(n, unit), do: round(apply(:timer, unit, [n]))
  end

  case(Mix.env()) do
    :test -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :millisecond)
    _ -> defp diff_seconds(a, b), do: DateTime.diff(a, b, :second)
  end
end
