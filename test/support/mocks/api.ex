defmodule ApiMock do
  use GenServer

  defmodule State do
    defstruct [:pid, :events, :captcha]
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_vehicle(name, id), do: GenServer.call(name, {:get_vehicle, id})
  def get_vehicle_with_state(name, id), do: GenServer.call(name, {:get_vehicle_with_state, id})
  def stream(name, vid, receiver), do: GenServer.call(name, {:stream, vid, receiver})

  def sign_in(name, tokens), do: GenServer.call(name, {:sign_in, tokens})

  # Callbacks

  @impl true
  def init(opts) do
    state = %State{
      pid: Keyword.fetch!(opts, :pid),
      events: Keyword.get(opts, :events, []),
      captcha: Keyword.get(opts, :captcha, true)
    }

    {:ok, state}
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

  def handle_call({:sign_in, {email, password}}, _from, %State{captcha: false} = state) do
    send(state.pid, {ApiMock, :sign_in, email, password})
    {:reply, :ok, state}
  end

  def handle_call({:sign_in, {email, password}}, _from, %State{captcha: true} = state) do
    callback = fn
      "mfa" = captcha ->
        send(state.pid, {ApiMock, :sign_in_callback, email, password, captcha})
        :ok

        devices = [
          %{"id" => "000", "name" => "Device #1"},
          %{"id" => "111", "name" => "Device #2"}
        ]

        callback = fn device_id, passcode ->
          send(state.pid, {ApiMock, :mfa_callback, [device_id, passcode]})
          :ok
        end

        {:ok, {:mfa, devices, callback}}

      captcha ->
        send(state.pid, {ApiMock, :sign_in_callback, email, password, captcha})
        :ok
    end

    captcha = ~S(<svg xmlns="http://www.w3.org/2000/svg">)

    {:reply, {:ok, {:captcha, captcha, callback}}, state}
  end

  def handle_call({:sign_in, _tokens} = event, _from, %State{pid: pid} = state) do
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
