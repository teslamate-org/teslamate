defmodule ApiMock do
  use GenServer

  defstruct [:pid, :events]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_vehicle(name, id), do: GenServer.call(name, {:get_vehicle, id})
  def get_vehicle_with_state(name, id), do: GenServer.call(name, {:get_vehicle_with_state, id})

  def wake_up(name, id), do: GenServer.call(name, {:wake_up, id})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), events: Keyword.fetch!(opts, :events)}}
  end

  @impl true
  def handle_call({action, _id}, _from, %State{events: [event | []]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, event, state}
  end

  def handle_call({action, _id}, _from, %State{events: [event | events]} = state)
      when action in [:get_vehicle, :get_vehicle_with_state] do
    {:reply, event, %State{state | events: events}}
  end

  def handle_call({:wake_up, _id} = event, _from, %State{pid: pid} = state) do
    send(pid, {:api, event})
    {:reply, :ok, state}
  end
end
