defmodule MqttPublisherMock do
  use GenServer

  defstruct [:pid]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def publish(name, topic, msg, opts), do: GenServer.call(name, {:publish, topic, msg, opts})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid)}}
  end

  @impl true
  def handle_call({:publish, _topic, _msg, _opts} = action, _from, %State{pid: pid} = state) do
    send(pid, {MqttPublisherMock, action})
    {:reply, :ok, state}
  end
end
