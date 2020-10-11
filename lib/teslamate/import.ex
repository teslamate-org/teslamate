defmodule TeslaMate.Import do
  use GenStateMachine

  require Logger

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.{Vehicles, Repair, Log}
  alias TeslaMate.Log.{Car, State}

  alias __MODULE__.{Status, LineParser, FakeApi, CSV}

  defstruct(
    path: nil,
    files: [],
    timezone: :utc,
    error: nil,
    completed: MapSet.new(),
    car: nil,
    pids: %{},
    deps: %{}
  )

  alias __MODULE__, as: Data

  defmodule Status do
    defstruct(state: :idle, message: nil, files: [])

    def into(state, %Data{files: files, completed: completed}) do
      files =
        Enum.map(files, fn %{date: date} = file ->
          complete = MapSet.member?(completed, date)
          Map.put(file, :complete, complete)
        end)

      case state do
        {:error, reason} -> %__MODULE__{state: :error, message: reason, files: files}
        state when is_atom(state) -> %__MODULE__{state: state, files: files}
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
  def get_status, do: GenStateMachine.call(@name, :get_status)
  def reload_directory, do: GenStateMachine.call(@name, :reload_directory)
  def subscribe, do: Phoenix.PubSub.subscribe(TeslaMate.PubSub, @topic)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :directory)
    {:ok, :idle, %Data{path: path}, {:next_event, :internal, :read_directory}}
  end

  ## Calls

  @impl true
  def handle_event({:call, from}, {:run, tz}, :idle, data) do
    {:next_state, :running, %Data{data | timezone: tz},
     [
       {:reply, from, :ok},
       {:next_event, :internal, :broadcast},
       {:next_event, :internal, :import}
     ]}
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
        {:next_state, {:error, reason}, {:next_event, :internal, :broadcast}}

      {:ok, files} ->
        files =
          files
          |> Enum.map(fn n -> %{date: parse_fname(n), path: Path.join([path, n])} end)
          |> Enum.reject(fn %{date: date} -> is_nil(date) end)
          |> Enum.sort_by(fn %{date: date} -> date end)

        {:keep_state, %Data{data | files: files}, {:next_event, :internal, :broadcast}}
    end
  end

  def handle_event(:internal, :read_directory, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:internal, :import, :running, %Data{files: files} = data) do
    Logger.info("Importing #{length(files)} file(s) ...")

    case create_event_streams(data) do
      {:error, reason} ->
        {:next_state, {:error, reason}, {:next_event, :internal, :broadcast}}

      {:ok, streams} ->
        car = create_car(streams)

        :ok = Log.complete_current_state(car)

        date_limit =
          with %State{start_date: date} <- Log.get_earliest_state(car) do
            date
          end

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
  end

  ## Info

  def handle_event(:info, {:done, chunk}, :running, %Data{completed: completed} = data) do
    :ok = Repair.trigger_run()

    {:keep_state, %Data{data | completed: MapSet.put(completed, chunk)},
     {:next_event, :internal, :broadcast}}
  end

  def handle_event(:info, :done, :running, %Data{car: car, pids: %{api: api, veh: veh}} = data) do
    Logger.info("Import complete!")

    true = Process.exit(veh, :kill)
    true = Process.exit(api, :normal)

    :ok = Log.complete_current_state(car)
    :ok = Log.create_current_state(car)
    :ok = Repair.trigger_run()

    {:next_state, :complete, data, {:next_event, :internal, :broadcast}}
  end

  def handle_event(:info, {:EXIT, _from, :normal}, _state, _data), do: :keep_state_and_data
  def handle_event(:info, {:EXIT, _from, :killed}, _state, _data), do: :keep_state_and_data

  def handle_event(:info, {:EXIT, _from, reason}, _state, data) do
    Logger.warning("Import failed: #{inspect(reason, pretty: true)}")
    {:next_state, {:error, reason}, data, {:next_event, :internal, :broadcast}}
  end

  ## Private

  defp parse_fname(name) do
    case name do
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

  defp create_event_streams(%Data{files: files, timezone: tz}) do
    alias TeslaApi.Vehicle.State.Drive
    alias TeslaApi.Vehicle, as: Veh

    try do
      event_streams =
        files
        |> Enum.sort_by(fn %{date: date} -> date end)
        |> Enum.map(fn %{date: date, path: path} ->
          path
          |> File.stream!(read_ahead: 64 * 4096)
          |> CSV.parse()
          |> case do
            {:error, :unsupported_delimiter} ->
              raise "Unsupported delimiter"

            {:error, :no_contents} ->
              {date, Stream.map([], & &1)}

            {:ok, rows} ->
              stream =
                rows
                |> Task.async_stream(&LineParser.parse(&1, tz), timeout: :infinity, ordered: true)
                |> Stream.map(fn {:ok, vehicle} -> vehicle end)
                |> Stream.filter(fn
                  %Veh{state: "unknown"} ->
                    false

                  %Veh{drive_state: %Drive{timestamp: nil}} ->
                    false

                  %Veh{state: "online", drive_state: %Drive{} = d} ->
                    d.latitude != nil and d.longitude != nil

                  %Veh{} ->
                    true
                end)

              {date, stream}
          end
        end)

      {:ok, event_streams}
    rescue
      e in File.Error -> {:error, e.reason}
      e -> {:error, e}
    end
  end

  defp create_car([]), do: raise("vehicle data is incomplete")

  defp create_car([{_date, %Stream{} = stream} | rest]) do
    alias TeslaApi.Vehicle, as: Veh

    stream
    |> Enum.find(fn %Veh{} = v -> v.vin != nil and v.vehicle_id != nil and v.id != nil end)
    |> case do
      nil ->
        create_car(rest)

      vehicle ->
        car = Vehicles.create_or_update!(vehicle)

        settings = %CarSettings{
          suspend_min: 0,
          suspend_after_idle_min: 99999,
          use_streaming_api: false
        }

        %Car{car | settings: settings}
    end
  end
end
