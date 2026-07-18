defmodule TeslaMate.Import do
  use GenStateMachine

  require Logger

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.{Vehicles, Repair, Log}
  alias TeslaMate.Log.{Car, State}

  alias __MODULE__.{
    Status,
    RowValidator,
    RejectedRow,
    RejectionReport,
    Checkpoint,
    Run,
    FakeApi,
    CSV
  }

  defstruct(
    path: nil,
    source_key: nil,
    files: [],
    timezone: :utc,
    error: nil,
    completed: MapSet.new(),
    rejection_report: %RejectionReport{},
    run_id: nil,
    run_timezone: nil,
    run_car_id: nil,
    date_limit: nil,
    date_limit_captured: false,
    car: nil,
    pids: %{},
    deps: %{}
  )

  alias __MODULE__, as: Data

  defmodule Status do
    defstruct(
      state: :idle,
      message: nil,
      files: [],
      rejected_rows: 0,
      rejection_examples: [],
      rejection_examples_truncated: false,
      rejection_example_limit: RejectionReport.max_examples(),
      resume_timezone: nil
    )

    def into(
          state,
          %Data{
            files: files,
            completed: completed,
            rejection_report: %RejectionReport{} = report,
            run_timezone: run_timezone
          }
        ) do
      files =
        Enum.map(files, fn file ->
          complete = MapSet.member?(completed, Checkpoint.file_id(file))

          file
          |> Map.drop([:fingerprint])
          |> Map.put(:complete, complete)
        end)

      status = %__MODULE__{
        files: files,
        rejected_rows: report.count,
        rejection_examples: report.examples,
        rejection_examples_truncated: RejectionReport.truncated?(report),
        resume_timezone: run_timezone
      }

      case state do
        {:error, reason} -> %__MODULE__{status | state: :error, message: reason}
        state when is_atom(state) -> %__MODULE__{status | state: state}
      end
    end
  end

  @name __MODULE__
  @topic "#{@name}/state"

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def run(timezone), do: GenStateMachine.call(@name, {:run, timezone})
  def running?, do: GenStateMachine.call(@name, :running?)
  def enabled?, do: is_pid(Process.whereis(@name))
  def valid_file_name?(fname), do: parse_fname(fname) != nil
  def get_status, do: GenStateMachine.call(@name, :get_status)
  def reload_directory, do: GenStateMachine.call(@name, :reload_directory)
  def discard_interrupted_run, do: GenStateMachine.call(@name, :discard_interrupted_run)
  def subscribe, do: Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :directory)

    {:ok, :idle, %Data{path: path, source_key: Checkpoint.source_key(path)},
     {:next_event, :internal, :read_directory}}
  end

  ## Calls

  @impl true
  def handle_event({:call, from}, {:run, tz}, :idle, %Data{} = data) do
    case prepare_run(data, tz) do
      {:ok, data} ->
        {:next_state, :running, data,
         [
           {:reply, from, :ok},
           {:next_event, :internal, :broadcast},
           {:next_event, :internal, :import}
         ]}

      {:error, reason} ->
        {:keep_state_and_data, {:reply, from, {:error, reason}}}
    end
  end

  def handle_event({:call, from}, {:run, _tz}, _, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :not_allowed}}}
  end

  def handle_event({:call, from}, :running?, state, _data) do
    {:keep_state_and_data, {:reply, from, state == :running}}
  end

  def handle_event({:call, from}, :get_status, state, data) do
    {:keep_state_and_data, {:reply, from, Status.into(state, data)}}
  end

  def handle_event(
        {:call, from},
        :discard_interrupted_run,
        :idle,
        %Data{run_id: run_id} = data
      )
      when is_integer(run_id) do
    discard_run(from, data)
  end

  def handle_event(
        {:call, from},
        :discard_interrupted_run,
        {:error, _reason},
        %Data{run_id: run_id} = data
      )
      when is_integer(run_id) do
    discard_run(from, data)
  end

  def handle_event({:call, from}, :discard_interrupted_run, _state, _data) do
    {:keep_state_and_data, {:reply, from, {:error, :not_allowed}}}
  end

  def handle_event({:call, from}, :reload_directory, _state, _data) do
    {:keep_state_and_data, [{:reply, from, :ok}, {:next_event, :internal, :read_directory}]}
  end

  ## Internal

  def handle_event(:internal, :broadcast, state, data) do
    :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, @topic, Status.into(state, data))
    :keep_state_and_data
  end

  def handle_event(:internal, :read_directory, :idle, %Data{path: path} = data) do
    case File.ls(path) do
      {:error, reason} ->
        {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}

      {:ok, names} ->
        case build_files(path, names) do
          {:ok, files} ->
            data = restore_active_run(%Data{data | files: files})
            {:keep_state, data, {:next_event, :internal, :broadcast}}

          {:error, reason} ->
            {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}
        end
    end
  end

  def handle_event(:internal, :read_directory, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:internal, :import, :running, %Data{files: files} = data) do
    pending = Enum.reject(files, &completed_file?(data, &1))
    Logger.info("Importing #{length(pending)} of #{length(files)} file(s) ...")

    cond do
      pending == [] ->
        complete_resumed_run(data)

      is_integer(data.run_car_id) ->
        data.run_car_id
        |> Log.get_car!()
        |> import_car()
        |> then(&start_import(data, &1))

      true ->
        case create_event_streams(data) do
          {:error, reason} ->
            {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}

          {:ok, streams} ->
            case create_car(streams, data.run_id) do
              {:error, reason, _rejection_report} ->
                report = Checkpoint.rejection_report(data.run_id, current_file_ids(data))
                data = %Data{data | rejection_report: report}

                {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}

              {:ok, car} ->
                :ok = Checkpoint.set_car(data.run_id, car.id)
                report = Checkpoint.rejection_report(data.run_id, current_file_ids(data))

                start_import(
                  %Data{data | run_car_id: car.id, rejection_report: report},
                  car
                )
            end
        end
    end
  end

  ## Info

  def handle_event(
        :info,
        {:rejected_row, %RejectedRow{} = rejected_row},
        _state,
        %Data{run_id: run_id, rejection_report: report} = data
      ) do
    case Checkpoint.record_rejection(run_id, rejected_row) do
      :inserted ->
        {:keep_state,
         %Data{data | rejection_report: RejectionReport.record(report, rejected_row)}}

      :existing ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:done, file_id},
        :running,
        %Data{run_id: run_id, completed: completed} = data
      ) do
    :ok = Checkpoint.complete_file(run_id, file_id)
    :ok = Repair.trigger_run()

    {:keep_state, %Data{data | completed: MapSet.put(completed, file_id)},
     {:next_event, :internal, :broadcast}}
  end

  def handle_event(:info, :done, :running, %Data{car: car, pids: %{api: api, veh: veh}} = data) do
    Logger.info("Import complete!")

    true = Process.exit(veh, :kill)
    true = Process.exit(api, :normal)

    :ok = Log.complete_current_state(car)
    :ok = Log.create_current_state(car)
    :ok = Repair.trigger_run()
    :ok = Checkpoint.complete_run(data.run_id)

    {:next_state, :complete, data, {:next_event, :internal, :broadcast}}
  end

  def handle_event(
        :info,
        {:import_aborted, reason},
        :running,
        %Data{pids: %{api: api, veh: veh}} = data
      ) do
    ref = Process.monitor(veh)
    true = Process.exit(veh, :kill)

    receive do
      {:DOWN, ^ref, :process, ^veh, :killed} -> :ok
    end

    :ok = GenServer.stop(api, :normal)

    {:next_state, {:error, reason}, %Data{data | pids: %{}}, {:next_event, :internal, :broadcast}}
  end

  def handle_event(:info, {:EXIT, _from, :normal}, _state, _data), do: :keep_state_and_data
  def handle_event(:info, {:EXIT, _from, :killed}, _state, _data), do: :keep_state_and_data

  def handle_event(:info, {:EXIT, from, reason}, _state, data) do
    Logger.warning("Import failed: #{inspect(reason, pretty: true)}")

    {:next_state, {:error, reason}, stop_import_processes(data, from),
     {:next_event, :internal, :broadcast}}
  end

  ## Private

  defp prepare_run(%Data{files: []}, _timezone), do: {:error, :no_files}

  defp prepare_run(%Data{source_key: source_key} = data, timezone) do
    case Checkpoint.get_active_run(source_key) do
      nil ->
        with {:ok, %Run{} = run} <- Checkpoint.start_run(source_key, timezone) do
          {:ok, apply_run(data, run)}
        end

      %Run{} = run ->
        {:ok, apply_run(data, run)}
    end
  end

  defp apply_run(%Data{} = data, %Run{} = run) do
    completed = Checkpoint.completed_files(run.id)
    report = Checkpoint.rejection_report(run.id, current_file_ids(data))

    %Data{
      data
      | timezone: run.timezone,
        completed: completed,
        rejection_report: report,
        run_id: run.id,
        run_timezone: run.timezone,
        run_car_id: run.car_id,
        date_limit: run.date_limit,
        date_limit_captured: run.date_limit_captured
    }
  end

  defp restore_active_run(%Data{source_key: source_key} = data) do
    case Checkpoint.get_active_run(source_key) do
      %Run{} = run ->
        apply_run(data, run)

      nil ->
        data
        |> clear_run()
        |> restore_last_completed_report()
    end
  end

  defp clear_run(%Data{} = data) do
    %Data{
      data
      | completed: MapSet.new(),
        rejection_report: %RejectionReport{},
        run_id: nil,
        run_timezone: nil,
        run_car_id: nil,
        date_limit: nil,
        date_limit_captured: false,
        car: nil,
        pids: %{}
    }
  end

  defp discard_run(from, %Data{run_id: run_id} = data) do
    :ok = Checkpoint.abandon_run(run_id)

    {:next_state, :idle, clear_run(data),
     [{:reply, from, :ok}, {:next_event, :internal, :broadcast}]}
  end

  defp stop_import_processes(%Data{pids: pids} = data, exited_pid) do
    pids
    |> Map.values()
    |> Enum.reject(&(&1 == exited_pid))
    |> Enum.filter(&Process.alive?/1)
    |> Enum.each(&Process.exit(&1, :kill))

    %Data{data | pids: %{}}
  end

  defp restore_last_completed_report(%Data{source_key: source_key} = data) do
    case Checkpoint.get_last_completed_run(source_key) do
      %Run{id: run_id} ->
        %Data{
          data
          | rejection_report: Checkpoint.rejection_report(run_id, current_file_ids(data))
        }

      nil ->
        data
    end
  end

  defp build_files(path, names) do
    # Content hashing is deliberately paid before status restoration. Size or mtime shortcuts
    # could mark replaced files complete, and completed-run reports use the same identity.
    names
    |> Enum.map(fn name -> %{date: parse_fname(name), path: Path.join([path, name])} end)
    |> Enum.reject(fn %{date: date} -> is_nil(date) end)
    |> Enum.reduce_while({:ok, []}, fn %{path: file_path} = file, {:ok, files} ->
      case Checkpoint.file_fingerprint(file_path) do
        {:ok, fingerprint} ->
          {:cont, {:ok, [Map.put(file, :fingerprint, fingerprint) | files]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, files} ->
        {:ok, Enum.sort_by(files, fn %{date: date, path: file_path} -> {date, file_path} end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp current_file_ids(%Data{files: files}), do: Enum.map(files, &Checkpoint.file_id/1)

  defp completed_file?(%Data{completed: completed}, file) do
    MapSet.member?(completed, Checkpoint.file_id(file))
  end

  defp import_car(%Car{} = car) do
    settings = %CarSettings{
      suspend_min: 0,
      suspend_after_idle_min: 99999,
      use_streaming_api: false,
      enabled: true
    }

    %Car{car | settings: settings}
  end

  defp original_date_limit(%Data{date_limit_captured: true} = data, _car) do
    {data.date_limit, data}
  end

  defp original_date_limit(%Data{run_id: run_id} = data, %Car{} = car) do
    date_limit =
      with %State{start_date: date} <- Log.get_earliest_state(car) do
        date
      end

    :ok = Checkpoint.capture_date_limit(run_id, date_limit)

    {date_limit,
     %Data{data | date_limit: date_limit, date_limit_captured: true, run_car_id: car.id}}
  end

  defp complete_resumed_run(%Data{run_id: run_id, run_car_id: car_id} = data) do
    Logger.info("Import complete after restoring file checkpoints")

    data =
      with car_id when is_integer(car_id) <- car_id do
        car = car_id |> Log.get_car!() |> import_car()
        :ok = Log.complete_current_state(car)
        :ok = Log.create_current_state(car)
        %Data{data | car: car}
      else
        _ -> data
      end

    :ok = Repair.trigger_run()
    :ok = Checkpoint.complete_run(run_id)

    {:next_state, :complete, data, {:next_event, :internal, :broadcast}}
  end

  defp start_import(%Data{} = data, %Car{} = car) do
    case create_event_streams(data, car) do
      {:ok, streams} ->
        start_import(data, car, streams)

      {:error, reason} ->
        {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}
    end
  end

  defp start_import(%Data{} = data, %Car{} = car, streams) do
    :ok = Log.complete_current_state(car)

    {date_limit, data} = original_date_limit(data, car)

    api_name = :"api_#{car.name}"

    {:ok, api} =
      FakeApi.start_link(
        name: api_name,
        event_streams: streams,
        date_limit: date_limit,
        pid: self()
      )

    {:ok, veh} =
      Vehicle.start_link(
        name: :"import_#{car.name}",
        car: car,
        import?: true,
        deps_api: {FakeApi, api_name}
      )

    {:keep_state, %Data{data | car: car, pids: %{veh: veh, api: api}},
     {:next_event, :internal, :broadcast}}
  end

  defp parse_fname(name) do
    case name do
      <<m::binary-size(2), y::binary-size(4), ".csv"::bitstring>> ->
        parse_date(y, m)

      <<"TeslaFi"::bitstring, m::binary-size(2), y::binary-size(4), ".csv"::bitstring>> ->
        parse_date(y, m)

      <<"TeslaFi"::bitstring, m::binary-size(1), y::binary-size(4), ".csv"::bitstring>> ->
        parse_date(y, m)

      _ ->
        nil
    end
  end

  defp parse_date(year, month) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month) do
      [year, month]
    else
      _ -> nil
    end
  end

  defp create_event_streams(
         %Data{files: files, timezone: tz, completed: completed},
         car \\ nil
       ) do
    alias TeslaApi.Vehicle.State.Drive
    alias TeslaApi.Vehicle, as: Veh

    try do
      event_streams =
        files
        |> Enum.reject(fn file -> MapSet.member?(completed, Checkpoint.file_id(file)) end)
        |> Enum.sort_by(fn %{date: date, path: path} -> {date, path} end)
        |> Enum.map(fn %{path: path, fingerprint: fingerprint} = file ->
          path
          |> File.stream!(read_ahead: 64 * 4096)
          |> CSV.parse()
          |> case do
            {:error, :unsupported_delimiter} ->
              raise "Unsupported delimiter"

            {:error, :no_contents} ->
              {Checkpoint.file_id(file), Stream.map([], & &1)}

            {:ok, rows} ->
              stream =
                rows
                |> Task.async_stream(
                  fn
                    {:ok, row_number, row} ->
                      case RowValidator.parse(row, tz) do
                        {:ok, vehicle} ->
                          classify_vehicle(
                            vehicle,
                            car,
                            path,
                            row_number,
                            fingerprint
                          )

                        {:error, reason, fields} ->
                          {:reject,
                           RejectedRow.new(path, row_number, reason, fields, fingerprint)}
                      end

                    {:error, row_number, reason, fields} ->
                      {:reject, RejectedRow.new(path, row_number, reason, fields, fingerprint)}
                  end,
                  timeout: :infinity,
                  ordered: true
                )
                |> Stream.map(fn {:ok, event} -> event end)
                |> Stream.filter(fn
                  {:reject, %RejectedRow{}} ->
                    true

                  {:vehicle, %Veh{state: "unknown"}} ->
                    false

                  {:vehicle, %Veh{drive_state: %Drive{timestamp: nil}}} ->
                    false

                  {:vehicle_changed, %Veh{} = v} ->
                    Logger.warning(
                      "'#{path}' contains data for more than one vehicle: #{car.name}" <>
                        " -> #{v.display_name}!"
                    )

                    throw(:vehicle_changed)

                  {:vehicle, %Veh{state: "online", drive_state: %Drive{} = d}} ->
                    d.latitude != nil and d.longitude != nil

                  {:vehicle, %Veh{}} ->
                    true
                end)

              {Checkpoint.file_id(file), stream}
          end
        end)

      {:ok, event_streams}
    rescue
      e in File.Error -> {:error, e.reason}
      e -> {:error, e}
    end
  end

  defp classify_vehicle(vehicle, nil, _path, _row_number, _fingerprint),
    do: {:vehicle, vehicle}

  defp classify_vehicle(
         %TeslaApi.Vehicle{vin: vin, vehicle_id: vehicle_id} = vehicle,
         %Car{} = car,
         path,
         row_number,
         fingerprint
       ) do
    # Some TeslaFi variants omit VINs and use a configured vehicle ID fallback. A differing
    # VIN and vehicle ID together establish a change; a lone VIN conflict is quarantined.
    cond do
      vin == nil or vin == car.vin ->
        {:vehicle, vehicle}

      vehicle_id != nil and vehicle_id != car.vid ->
        {:vehicle_changed, vehicle}

      true ->
        {:reject, RejectedRow.new(path, row_number, :invalid_fields, ["vin"], fingerprint)}
    end
  end

  defp create_car(streams, run_id), do: create_car(streams, run_id, %RejectionReport{})

  defp create_car([], _run_id, %RejectionReport{} = report),
    do: {:error, :vehicle_data_incomplete, report}

  defp create_car(
         [{_file, %Stream{} = stream} | rest],
         run_id,
         %RejectionReport{} = report
       ) do
    alias TeslaApi.Vehicle, as: Veh

    stream
    |> Enum.reduce_while(report, fn
      {:vehicle, %Veh{} = vehicle}, _report
      when vehicle.vin != nil and vehicle.vehicle_id != nil and vehicle.id != nil ->
        {:halt, {:vehicle, vehicle}}

      {:vehicle, %Veh{}}, report ->
        {:cont, report}

      {:reject, %RejectedRow{} = rejected_row}, report ->
        _ = Checkpoint.record_rejection(run_id, rejected_row)
        {:cont, RejectionReport.record(report, rejected_row)}
    end)
    |> case do
      %RejectionReport{} = report ->
        create_car(rest, run_id, report)

      {:vehicle, vehicle} ->
        car = Vehicles.create_or_update!(vehicle)

        {:ok, import_car(car)}
    end
  end
end
