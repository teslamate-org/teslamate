defmodule LocationsMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  alias TeslaMate.Locations.{Address, GeoFence}

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def subscribe_to_geofences(_name), do: :ok

  def find_geofence(name, point) do
    GenServer.call(name, {:find_geofence, point})
  end

  # Tells the calling process about each lookup, and whether it held a DB
  # connection meanwhile: the lookup queries Nominatim, which takes a while.
  def find_address(name, point) do
    GenServer.call(name, {:find_address, point, checked_out?: TeslaMate.Repo.checked_out?()})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:find_geofence, %{latitude: 90, longitude: 45.01}}, _from, state) do
    geofence = %GeoFence{id: 1, name: "Garage", latitude: 90, longitude: 45.01, radius: 20}
    {:reply, geofence, state}
  end

  def handle_call({:find_geofence, %{latitude: 90, longitude: 45}}, _from, state) do
    geofence = %GeoFence{id: 0, name: "South Pole", latitude: 90, longitude: 45, radius: 100}
    {:reply, geofence, state}
  end

  def handle_call({:find_geofence, %{latitude: _, longitude: _}}, _from, state) do
    {:reply, nil, state}
  end

  def handle_call({:find_address, %{latitude: 99.9, longitude: 99.9}, _} = action, _from, state) do
    send(state.pid, action)
    {:reply, {:error, :induced_error}, state}
  end

  def handle_call({:find_address, %{latitude: _, longitude: _}, _} = action, _from, state) do
    send(state.pid, action)
    {:reply, {:ok, %Address{id: 1}}, state}
  end
end
