defmodule SRTMMock do
  use GenServer

  defstruct [:pid, :responses]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_elevation(name, lat, lng, opts \\ []) do
    GenServer.call(name, {:get_elevation, lat, lng, opts})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), responses: Keyword.fetch!(opts, :responses)}}
  end

  @impl true
  def handle_call({:get_elevation, lat, lng, opts}, _, %State{responses: r} = state) do
    lat = with %Decimal{} <- lat, do: Decimal.to_float(lat)
    lng = with %Decimal{} <- lng, do: Decimal.to_float(lng)

    send(state.pid, {SRTM, {:get_elevation, lat, lng, opts}})

    response =
      with {:ok, elevation} <- Map.fetch!(r, {lat, lng}).() do
        {:ok, elevation}
      end

    {:reply, response, state}
  end
end
