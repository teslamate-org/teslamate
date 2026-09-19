defmodule SettingsMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def subscribe_to_changes(name, car) do
    GenServer.call(name, {:subscribe_to_changes, car})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true

  def handle_call({:subscribe_to_changes = event, _car}, _from, %State{pid: pid} = state) do
    send(pid, {__MODULE__, event})
    {:reply, :ok, state}
  end
end
