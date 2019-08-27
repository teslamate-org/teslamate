defmodule TeslaMate.Mapping do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]
  alias TeslaMate.Log.Position
  alias TeslaMate.Log

  defstruct [:client, :blocked_on, :deps]
  alias __MODULE__, as: State

  @name __MODULE__

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_elevation(name \\ @name, coordinates) do
    GenServer.call(name, {:get_elevation, coordinates}, 1000)
  end

  # TODO
  # * Add Docker Volume for caches
  # * Grafana: m to ft

  # Callbacks

  @impl true
  def init(opts) do
    client = SRTM.Client.new(cache_path())

    deps = %{
      srtm: Keyword.get(opts, :deps_srtm, SRTM),
      log: Keyword.get(opts, :deps_log, Log)
    }

    {:ok, %State{client: client, deps: deps}, {:continue, {:add_elevation_to_positions, 0}}}
  end

  @impl true
  def handle_continue({:add_elevation_to_positions, min_id}, state) do
    case call(state.deps.log, :get_positions_without_elevation, [min_id]) |> Enum.reverse() do
      [%Position{id: next_min_id} | _] = positions ->
        {:noreply, %State{state | blocked_on: :update_positions},
         {:continue, {:update_positions, positions, next_min_id}}}

      [] ->
        Process.send_after(self(), :add_elevation_to_positions, :timer.hours(6))
        {:noreply, state}
    end
  end

  def handle_continue({:update_positions, positions, next_min_id}, %State{} = state) do
    state =
      Enum.reduce(positions, state, fn %Position{latitude: lat, longitude: lng} = pos, state ->
        with {:ok, el, client} <- do_get_elevation({lat, lng}, state),
             {:ok, _pos} <- call(state.deps.log, :update_position, [pos, %{elevation: el}]) do
          %State{state | client: client}
        else
          {:error, reason} ->
            log_warning(reason)
            state
        end
      end)

    {:noreply, %State{state | blocked_on: nil},
     {:continue, {:add_elevation_to_positions, next_min_id}}}
  end

  @impl true
  def handle_call({:get_elevation, {_, _}}, _from, %State{blocked_on: blocker} = state)
      when is_reference(blocker) or blocker == :update_positions do
    {:reply, {:ok, nil}, state}
  end

  def handle_call({:get_elevation, {lat, lng}}, _from, %State{} = state) do
    task = Task.async(fn -> do_get_elevation({lat, lng}, state) end)

    case Task.yield(task, 50) do
      {:ok, {:ok, elevation, client}} ->
        {:reply, elevation, %State{state | client: client}}

      {:ok, {:error, :unavailable}} ->
        {:reply, nil, state}

      {:ok, {:error, reason}} ->
        log_warning(reason)
        {:reply, nil, state}

      nil ->
        {:reply, nil, %State{state | blocked_on: task.ref}}
    end
  end

  @impl true
  def handle_info({task, result}, %State{blocked_on: task} = state) when is_reference(task) do
    case result do
      {:ok, _elevation, %SRTM.Client{} = client} ->
        {:noreply, %State{state | client: client, blocked_on: nil}}

      {:error, reason} ->
        log_warning(reason)
        {:noreply, %State{state | blocked_on: nil}}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info(:add_elevation_to_positions, state) do
    {:noreply, state, {:continue, {:add_elevation_to_positions, 0}}}
  end

  # Private

  defp do_get_elevation({lat, lng}, %State{client: client, deps: %{srtm: srtm}} = state) do
    case :fuse.ask(@name, :sync) do
      :ok ->
        with {:error, reason} <- call(srtm, :get_elevation, [client, lat, lng]) do
          :fuse.melt(@name)
          {:error, reason}
        end

      :blown ->
        {:error, :unavailable}

      {:error, :not_found} ->
        :fuse.install(@name, {{:standard, 2, :timer.minutes(2)}, {:reset, :timer.minutes(5)}})
        do_get_elevation({lat, lng}, state)
    end
  end

  defp log_warning(reason), do: Logger.warn("Elevation query failed: #{inspect(reason)}")

  defp cache_path, do: Application.fetch_env!(:teslamate, :srtm_cache)
end
