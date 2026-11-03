defmodule TeslaMate.Terrain do
  use GenStateMachine

  require Logger
  import Core.Dependency, only: [call: 3]

  defstruct [:timeout, :deps, :name, :tasks]
  alias __MODULE__, as: Data

  @name __MODULE__

  # How long a caller of get_elevation/2 waits for Terrain. One lookup takes at
  # most the lookup timeout (100 ms by default): a slower one is answered
  # :timeout and finishes in the background. The 2000 ms leave room for the
  # lookups queued before the call, those of other cars and of
  # TeslaMate.Terrain.Repair. A caller still waiting after that gets
  # {:error, :timeout}, as for a slow lookup, and Terrain's late answer is
  # dropped.
  @call_timeout 2000

  # API

  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @doc """
  The terrain elevation at the coordinates: `{:ok, elevation}`, or `{:ok, nil}`
  where the terrain has no data, or `{:error, reason}` when the lookup cannot
  answer — not ready (`:unavailable`), too slow (`:timeout`) or failed.
  """
  def get_elevation(name \\ @name, coordinates) do
    GenStateMachine.call(name, {:get_elevation, coordinates}, @call_timeout)
  catch
    # The answer that comes later is dropped: the call's alias is gone.
    :exit, {:timeout, _call} -> {:error, :timeout}
    # Terrain is not running, during a restart say.
    :exit, {:noproc, _call} -> {:error, :unavailable}
  end

  @doc """
  The terrain elevation at the coordinates like `get_elevation/2`, for adding
  it to stored positions (`TeslaMate.Terrain.Repair`), which nobody waits for:
  waits for a slow lookup to finish, and for a pending one to finish first,
  instead of answering `:timeout`. Like `get_elevation/2`, it answers
  `:unavailable` when Terrain is not ready or not running.
  """
  def await_elevation(name \\ @name, coordinates) do
    GenStateMachine.call(name, {:await_elevation, coordinates}, :infinity)
  catch
    # Terrain is not running, during a restart say.
    :exit, {:noproc, _call} -> {:error, :unavailable}
  end

  # Callbacks

  @impl true
  def init(opts) do
    # The lookups run under a task supervisor of Terrain's own, not linked
    # to Terrain: a lookup that crashes, on a corrupt cache file say, is a
    # failed lookup, not the end of the service every vehicle shares. The
    # supervisor is linked to Terrain, so it goes when Terrain goes.
    {:ok, tasks} = Task.Supervisor.start_link()

    data = %Data{
      timeout: Keyword.get(opts, :timeout, 100),
      name: Keyword.get(opts, :name, @name),
      deps: %{srtm: Keyword.get(opts, :deps_srtm, SRTM)},
      tasks: tasks
    }

    case Keyword.get(opts, :disabled, false) do
      false -> {:ok, :ready, data}
      true -> {:ok, :disabled, data}
    end
  end

  ## Call

  # One lookup at a time: a slow one is waited for in {:waiting, ref, from},
  # where from is the caller of await_elevation/2 that gets the answer, or nil
  # when get_elevation/2 got :timeout instead.
  @impl true
  def handle_event({:call, from}, {request, {lat, lng}}, :ready, %Data{} = data)
      when request in [:get_elevation, :await_elevation] do
    task = Task.Supervisor.async_nolink(data.tasks, fn -> do_get_elevation({lat, lng}, data) end)

    case Task.yield(task, data.timeout) do
      {:ok, {:ok, elevation}} ->
        {:keep_state_and_data, {:reply, from, {:ok, elevation}}}

      {:ok, {:error, :unavailable}} ->
        {:keep_state_and_data, {:reply, from, {:error, :unavailable}}}

      {:ok, {:error, reason}} ->
        log_warning(reason)
        {:keep_state_and_data, {:reply, from, {:error, reason}}}

      {:exit, reason} ->
        {:keep_state_and_data, {:reply, from, crashed(reason, data)}}

      nil ->
        Logger.info("Querying location for elevation takes longer than #{data.timeout}ms ...")

        case request do
          :get_elevation ->
            {:next_state, {:waiting, task.ref, nil}, data, {:reply, from, {:error, :timeout}}}

          :await_elevation ->
            {:next_state, {:waiting, task.ref, from}, data}
        end
    end
  end

  def handle_event(
        {:call, _from},
        {:await_elevation, _coords},
        {:waiting, _ref, _awaiting},
        _data
      ) do
    {:keep_state_and_data, :postpone}
  end

  def handle_event({:call, from}, {request, _coords}, _state, _data)
      when request in [:get_elevation, :await_elevation] do
    {:keep_state_and_data, {:reply, from, {:error, :unavailable}}}
  end

  ## Info

  def handle_event(:info, {ref, result}, {:waiting, ref, from}, data) do
    case result do
      {:ok, elevation} -> Logger.debug("Received delayed SRTM message: #{elevation}m")
      {:error, reason} -> log_warning(reason)
    end

    finish_waiting(from, result, data)
  end

  def handle_event(:info, {:DOWN, ref, :process, _pid, reason}, {:waiting, ref, from}, data)
      when reason != :normal do
    finish_waiting(from, crashed(reason, data), data)
  end

  def handle_event(:info, {:DOWN, _ref, :process, _pid, :normal}, _state, _data) do
    :keep_state_and_data
  end

  def handle_event(:info, :garbage_collect, _state, _data) do
    :erlang.garbage_collect(self())
    :keep_state_and_data
  end

  # Private

  defp do_get_elevation({lat, lng}, %Data{deps: %{srtm: srtm}, name: name} = data) do
    case :fuse.ask(name, :sync) do
      :ok ->
        with {:error, reason} <-
               call(srtm, :get_elevation, [lat, lng, [disk_cache_path: cache_path()]]) do
          :fuse.melt(name)
          {:error, reason}
        end

      :blown ->
        {:error, :unavailable}

      {:error, :not_found} ->
        Logger.debug("Installing circuit-breaker #{inspect(name)} ...")
        :fuse.install(name, {{:standard, 2, :timer.minutes(3)}, {:reset, :timer.minutes(15)}})
        do_get_elevation({lat, lng}, data)
    end
  end

  # The slow lookup is over: its caller, if it awaits it, gets the result.
  defp finish_waiting(nil, _result, data), do: {:next_state, :ready, data}
  defp finish_waiting(from, result, data), do: {:next_state, :ready, data, {:reply, from, result}}

  # A crashed lookup failed like any other: it melts the circuit breaker.
  defp crashed(reason, %Data{name: name}) do
    :fuse.melt(name)
    log_warning(reason)
    {:error, reason}
  end

  defp log_warning(reason) do
    Logger.warning("Elevation query failed: #{inspect(reason)}")
  end

  defp cache_path do
    Application.fetch_env!(:teslamate, :srtm_cache)
  end
end
