defmodule ApiMock do
  use GenServer

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

  def sign_in(name, tokens), do: GenServer.call(name, {:sign_in, tokens})

  # Callbacks

  @impl true
  def init(opts) do
    state = %State{
      pid: Keyword.fetch!(opts, :pid),
      events: Keyword.get(opts, :events, [])
    }

    {:ok, state}
  end

  @impl true
  def handle_call({action, _id}, _from, %State{events: [event | []]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, exec(event, action), state}
  end

  def handle_call({action, _id}, _from, %State{events: [event | events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, exec(event, action), %State{state | events: events}}
  end

  def handle_call({:sign_in, _tokens} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, :ok, state}
  end

  def handle_call({:stream, _vid, _receiver} = event, _from, %State{pid: pid} = state) do
    send(pid, {ApiMock, event})
    {:reply, {:ok, pid}, state}
  end

  # Events tagged with :get_vehicle or :get_vehicle_with_state may only be
  # consumed by that API call, allowing tests to pin which endpoint was used.
  defp exec({expected_action, event}, action)
       when expected_action in [:get_vehicle, :get_vehicle_with_state] do
    if expected_action != action do
      raise "expected #{inspect(expected_action)} to be called, but got #{inspect(action)}"
    end

    exec(event, action)
  end

  defp exec(event, _action) when is_function(event), do: event.()
  defp exec(event, _action), do: event
end
