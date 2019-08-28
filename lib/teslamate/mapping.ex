defmodule TeslaMate.Mapping do
  use GenStateMachine

  require Logger
  import Core.Dependency, only: [call: 3]
  alias TeslaMate.Log.Position
  alias TeslaMate.Log

  defstruct [:client, :timeout, :deps, :name]
  alias __MODULE__, as: Data

  @name __MODULE__

  # API

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_elevation(name \\ @name, coordinates) do
    GenStateMachine.call(name, {:get_elevation, coordinates}, 2000)
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, client} = SRTM.Client.new(cache_path())

    timeout = Keyword.get(opts, :timeout, 50)
    name = Keyword.get(opts, :name, @name)

    deps = %{
      srtm: Keyword.get(opts, :deps_srtm, SRTM),
      log: Keyword.get(opts, :deps_log, Log)
    }

    {:ok, _ref} = :timer.send_interval(:timer.hours(3), self(), :purge_srtm_in_memory_cache)

    {:ok, :ready, %Data{client: client, timeout: timeout, deps: deps, name: name},
     {:next_event, :internal, {:fetch_positions, 0}}}
  end

  ## Call

  @impl true
  def handle_event({:call, from}, {:get_elevation, {lat, lng}}, :ready, %Data{} = data) do
    task = Task.async(fn -> do_get_elevation({lat, lng}, data) end)

    case Task.yield(task, data.timeout) do
      {:ok, {:ok, elevation, client}} ->
        {:keep_state, %Data{data | client: client}, {:reply, from, elevation}}

      {:ok, {:error, :unavailable}} ->
        {:keep_state_and_data, {:reply, from, nil}}

      {:ok, {:error, reason}} ->
        log_warning(reason)
        {:keep_state_and_data, {:reply, from, nil}}

      nil ->
        {:next_state, {:waiting, task.ref}, data, {:reply, from, nil}}
    end
  end

  def handle_event({:call, from}, {:get_elevation, _coords}, _state, _data) do
    {:keep_state_and_data, {:reply, from, nil}}
  end

  ## Internal

  def handle_event(event, {:fetch_positions, min_id}, :ready, %Data{} = data)
      when event in [:internal, :state_timeout] do
    case call(data.deps.log, :get_positions_without_elevation, [min_id, [limit: 100]]) do
      {[], nil} ->
        {:keep_state_and_data, schedule_fetch()}

      {positions, next} ->
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, positions, next, nil}, data}
    end
  end

  ## Cast

  def handle_event(:cast, :process, {:update, [], next, nil}, data) do
    {:next_state, :ready, data, {:next_event, :internal, {:fetch_positions, next}}}
  end

  def handle_event(:cast, :process, {:update, [%Position{} = p | rest], next, nil}, data) do
    task = Task.async(fn -> do_get_elevation({p.latitude, p.longitude}, data) end)

    case Task.yield(task, data.timeout) do
      {:ok, {:ok, elevation, client}} ->
        {:ok, _pos} = call(data.deps.log, :update_position, [p, %{elevation: elevation}])
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, rest, next, nil}, %Data{data | client: client}}

      {:ok, {:error, :unavailable}} ->
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, rest, next, nil}, data}

      {:ok, {:error, reason}} ->
        log_warning(reason)
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, rest, next, nil}, data}

      nil ->
        {:next_state, {:update, [p | rest], next, task.ref}, data}
    end
  end

  ## Info

  def handle_event(:info, {ref, result}, {:waiting, ref}, data) do
    case result do
      {:ok, _elevation, %SRTM.Client{} = client} ->
        {:next_state, :ready, %Data{data | client: client}, schedule_fetch()}

      {:error, reason} ->
        log_warning(reason)
        {:next_state, :ready, data, schedule_fetch()}
    end
  end

  def handle_event(:info, {ref, result}, {:update, [%Position{} = p | rest], next, ref}, data) do
    case result do
      {:ok, elevation, %SRTM.Client{} = client} ->
        {:ok, _pos} = call(data.deps.log, :update_position, [p, %{elevation: elevation}])
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, rest, next, nil}, %Data{data | client: client}}

      {:error, reason} ->
        log_warning(reason)
        :ok = GenStateMachine.cast(self(), :process)
        {:next_state, {:update, rest, next, nil}, data}
    end
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, :purge_srtm_in_memory_cache, _state, %Data{client: client} = data) do
    {:ok, client} = SRTM.Client.purge_in_memory_cache(client, keep: 2)
    {:keep_state, %Data{data | client: client}}
  end

  # Private

  defp do_get_elevation({lat, lng}, %Data{client: client, deps: %{srtm: srtm}, name: name} = data) do
    case :fuse.ask(name, :sync) do
      :ok ->
        with {:error, reason} <- call(srtm, :get_elevation, [client, lat, lng]) do
          :fuse.melt(name)
          {:error, reason}
        end

      :blown ->
        {:error, :unavailable}

      {:error, :not_found} ->
        :fuse.install(name, {{:standard, 2, :timer.minutes(2)}, {:reset, :timer.minutes(5)}})
        do_get_elevation({lat, lng}, data)
    end
  end

  defp schedule_fetch do
    {:state_timeout, :timer.hours(6), {:fetch_positions, 0}}
  end

  defp log_warning(reason) do
    Logger.warn("Elevation query failed: #{inspect(reason)}")
  end

  defp cache_path do
    Application.fetch_env!(:teslamate, :srtm_cache)
  end
end
