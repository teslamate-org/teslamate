defmodule LocationsMock do
  use GenServer

  defstruct [:pid, :blacklist, :whitelist]
  alias __MODULE__, as: State

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Log.Car

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def may_fall_asleep_at?(name, car, position) do
    GenServer.call(name, {:may_fall_asleep_at?, car, position})
  end

  def find_geofence(name, point) do
    GenServer.call(name, {:find_geofence, point})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok,
     %State{
       pid: Keyword.fetch!(opts, :pid),
       blacklist: Keyword.fetch!(opts, :blacklist),
       whitelist: Keyword.fetch!(opts, :whitelist)
     }}
  end

  @impl true
  def handle_call({:may_fall_asleep_at?, %Car{settings: settings}, position}, _from, state) do
    %{latitude: lat, longitude: lng} = position

    response =
      case settings do
        %CarSettings{sleep_mode_enabled: true} ->
          Enum.find(state.blacklist, &match?({^lat, ^lng}, &1)) == nil

        %CarSettings{sleep_mode_enabled: false} ->
          Enum.find(state.whitelist, &match?({^lat, ^lng}, &1)) != nil
      end

    {:reply, {:ok, response}, state}
  end

  def handle_call({:find_geofence, %{latitude: 90, longitude: 45}}, _from, state) do
    geofence = %GeoFence{id: 0, name: "South Pole", latitude: 90, longitude: 45, radius: 100}
    {:reply, geofence, state}
  end

  def handle_call({:find_geofence, %{latitude: _, longitude: _}}, _from, state) do
    {:reply, nil, state}
  end
end
