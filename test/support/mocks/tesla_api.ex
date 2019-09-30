defmodule TeslaApi.AuthMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def refresh(name, auth), do: GenServer.call(name, {:refresh, auth})
  def login(name, email, password), do: GenServer.call(name, {:login, email, password})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call(
        {:refresh, %{token: nil, refresh_token: nil}} = event,
        _from,
        %State{pid: pid} = state
      ) do
    send(pid, {TeslaApi.AuthMock, event})
    {:reply, {:error, %TeslaApi.Error{error: :induced_error}}, state}
  end

  def handle_call(event, _from, %State{pid: pid} = state) do
    send(pid, {TeslaApi.AuthMock, event})
    {:reply, {:ok, %TeslaApi.Auth{token: "$token", expires_in: 10_000_000}}, state}
  end
end

defmodule TeslaApi.VehicleMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get(name, auth, id) do
    GenServer.call(name, {:get, auth, id})
  end

  def get_with_state(name, auth, id) do
    GenServer.call(name, {:get_with_state, auth, id})
  end

  def list(name, auth) do
    GenServer.call(name, {:list, auth})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:get, _auth, id} = event, _from, %State{pid: pid} = state) do
    send(pid, {TeslaApi.VehicleMock, event})
    {:reply, {:ok, %TeslaApi.Vehicle{id: id}}, state}
  end

  def handle_call({:get_with_state, _auth, id} = event, _from, %State{pid: pid} = state) do
    send(pid, {TeslaApi.VehicleMock, event})
    {:reply, {:ok, %TeslaApi.Vehicle{id: id}}, state}
  end

  def handle_call({:list, _auth} = event, _from, %State{pid: pid} = state) do
    send(pid, {TeslaApi.VehicleMock, event})
    {:reply, {:ok, [%TeslaApi.Vehicle{}]}, state}
  end
end
