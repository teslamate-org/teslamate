defmodule ApiMock do
  use GenServer

  alias TeslaMate.Auth.Credentials

  defmodule State do
    defstruct [:pid, :events]
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_vehicle(name, id), do: GenServer.call(name, {:get_vehicle, id})
  def get_vehicle_with_state(name, id), do: GenServer.call(name, {:get_vehicle_with_state, id})
  def stream(name, vid, receiver), do: GenServer.call(name, {:stream, vid, receiver})

  def sign_in(name, credentials), do: GenServer.call(name, {:sign_in, credentials})

  def sign_in(name, device_id, passcode, ctx),
    do: GenServer.call(name, {:sign_in, device_id, passcode, ctx})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), events: Keyword.get(opts, :events, [])}}
  end

  @impl true
  def handle_call({action, _id}, _from, %State{events: [event | []]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, exec(event), state}
  end

  def handle_call({action, _id}, _from, %State{events: [event | events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, exec(event), %State{state | events: events}}
  end

  def handle_call({:sign_in, %Credentials{email: "mfa"}} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    devices = [%{"id" => "000", "name" => "Device #1"}, %{"id" => "111", "name" => "Device #2"}]
    {:reply, {:ok, {:mfa, devices, %TeslaApi.Auth.MFA.Ctx{}}}, state}
  end

  def handle_call({:sign_in, %Credentials{email: "error"}}, _from, %State{} = state) do
    {:reply, {:error, %TeslaApi.Error{reason: :unknown, env: nil}}, state}
  end

  def handle_call({:sign_in, _credentials} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, :ok, state}
  end

  def handle_call({:sign_in, "error", _code, _ctx} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, {:error, %TeslaApi.Error{reason: :unknown, env: nil}}, state}
  end

  def handle_call({:sign_in, _device_id, _code, _ctx} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, :ok, state}
  end

  def handle_call({:stream, _vid, _receiver} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, {:ok, pid}, state}
  end

  defp exec(event) when is_function(event), do: event.()
  defp exec(event), do: event
end
