defmodule TeslaMate.Mqtt.Publisher do
  use GenServer

  require Logger

  @name __MODULE__
  @timeout :timer.seconds(10)

  defstruct client_id: nil,
            refs: %{}

  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def publish(topic, msg \\ nil, opts \\ []) do
    GenServer.call(@name, {:publish, topic, msg, opts}, @timeout)
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{client_id: Keyword.fetch!(opts, :client_id)}}
  end

  @impl true
  def handle_call({:publish, topic, msg, opts}, from, %State{client_id: id, refs: refs} = state) do
    opts = Keyword.put_new(opts, :timeout, round(@timeout * 0.95))

    case Keyword.get(opts, :qos, 0) do
      0 ->
        :ok = Tortoise.publish(id, topic, msg, opts)
        {:reply, :ok, state}

      _ ->
        {:ok, ref} = Tortoise.publish(id, topic, msg, opts)
        {:noreply, %State{state | refs: Map.put(refs, ref, from)}}
    end
  end

  @impl true
  def handle_info({{Tortoise, id}, ref, result}, %State{client_id: id, refs: refs} = state) do
    {from, refs} = Map.pop(refs, ref)
    GenServer.reply(from, result)
    {:noreply, %State{state | refs: refs}}
  end
end
