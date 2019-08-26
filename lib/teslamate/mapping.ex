defmodule TeslaMate.Mapping do
  use GenServer

  require Logger

  @name __MODULE__

  defstruct [:client, :blocked_on, :get_elevation]

  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_elevation(name \\ @name, coordinates) do
    GenServer.call(name, {:get_elevation, coordinates}, 5000)
  end

  # Callbacks

  @impl true
  def init(opts) do
    get_elevation = Keyword.get(opts, :get_elevation, &SRTM.get_elevation/3)
    client = SRTM.Client.new(cache_path())

    {:ok, %State{client: client, get_elevation: get_elevation}}
  end

  @impl true
  def handle_call({:get_elevation, {_, _}}, _from, %State{blocked_on: task} = state)
      when is_reference(task) do
    {:reply, {:ok, nil}, state}
  end

  def handle_call({:get_elevation, {lat, lng}}, _from, %State{client: client} = state) do
    task = Task.async(fn -> state.get_elevation.(client, lat, lng) end)

    case Task.yield(task, 100) do
      {:ok, {:ok, elevation, client}} ->
        {:reply, {:ok, elevation}, %State{state | client: client}}

      {:ok, {:error, reason}} ->
        {:reply, {:error, reason}, state}

      nil ->
        {:reply, {:ok, nil}, %State{state | blocked_on: task.ref}}
    end
  end

  @impl true
  def handle_info({task, result}, %State{blocked_on: task} = state) when is_reference(task) do
    case result do
      {:ok, _elevation, %SRTM.Client{} = client} ->
        {:noreply, %State{state | client: client, blocked_on: nil}}

      {:error, reason} ->
        Logger.warn("Failed to query elevation: #{inspect(reason)}")
        {:noreply, %State{state | blocked_on: nil}}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  defp cache_path, do: Application.fetch_env!(:teslamate, :srtm_cache)
end
