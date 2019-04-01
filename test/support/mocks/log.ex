defmodule LogMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def start_state(name, state), do: GenServer.call(name, {:start_state, state})

  def start_drive_state(name), do: GenServer.call(name, :start_drive_state)
  def close_drive_state(name), do: GenServer.call(name, :close_drive_state)

  def start_charging_state(name), do: GenServer.call(name, :start_charging_state)
  def close_charging_state(name), do: GenServer.call(name, :close_charging_state)

  def insert_position(name, attrs), do: GenServer.call(name, {:insert_position, attrs})
  def insert_charge(name, attrs), do: GenServer.call(name, {:insert_charge, attrs})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call(action, _from, %State{pid: pid} = state) do
    send(pid, action)
    {:reply, :ok, state}
  end
end
