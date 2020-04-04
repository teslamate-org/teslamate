defmodule LocationsMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  alias TeslaMate.Locations.GeoFence

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def find_geofence(name, point) do
    GenServer.call(name, {:find_geofence, point})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:find_geofence, %{latitude: 90, longitude: 45}}, _from, state) do
    geofence = %GeoFence{id: 0, name: "South Pole", latitude: 90, longitude: 45, radius: 100}
    {:reply, geofence, state}
  end

  def handle_call({:find_geofence, %{latitude: _, longitude: _}}, _from, state) do
    {:reply, nil, state}
  end
end
