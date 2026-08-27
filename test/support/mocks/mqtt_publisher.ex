defmodule MqttPublisherMock do
  use GenServer

  defstruct [:pid, responses: %{}]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def publish(name, topic, msg, opts), do: GenServer.call(name, {:publish, topic, msg, opts})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok,
     %State{
       pid: Keyword.fetch!(opts, :pid),
       responses: Keyword.get(opts, :responses, %{})
     }}
  end

  @impl true
  def handle_call(
        {:publish, topic, _msg, _opts} = action,
        _from,
        %State{pid: pid, responses: responses} = state
      ) do
    send(pid, {MqttPublisherMock, action})

    {response, responses} =
      case Map.get(responses, topic, []) do
        [response | rest] -> {response, Map.put(responses, topic, rest)}
        [] -> {:ok, responses}
      end

    {:reply, response, %{state | responses: responses}}
  end
end
