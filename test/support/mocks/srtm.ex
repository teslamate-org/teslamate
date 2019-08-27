defmodule SRTMMock do
  use GenServer

  defstruct [:pid, :responses]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_elevation(name, client, lat, lng) do
    GenServer.call(name, {:get_elevation, client, lat, lng})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), responses: Keyword.fetch!(opts, :responses)}}
  end

  @impl true
  def handle_call({:get_elevation, client, lat, lng} = action, _, %State{responses: r} = state) do
    send(state.pid, {SRTM, action})

    response =
      with {:ok, elevation} <- Map.fetch!(r, {lat, lng}).() do
        {:ok, elevation, client}
      end

    {:reply, response, state}
  end
end
