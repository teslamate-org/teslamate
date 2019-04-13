defmodule PubSubMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def broadcast(name, server, topic, message) do
    GenServer.call(name, {:broadcast, server, topic, message})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true

  def handle_call({:broadcast, _, _, _} = event, _from, %State{pid: pid} = state) do
    send(pid, {:pubsub, event})
    {:reply, :ok, state}
  end
end
