defmodule TeslaMate.Mqtt.Publisher do
  use GenServer

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
  def handle_call({:publish, topic, msg, opts}, from, %State{client_id: id} = state) do
    opts = Keyword.put_new(opts, :timeout, round(@timeout * 0.95))

    case Keyword.get(opts, :qos, 0) do
      qos when qos in [0, 1, 2] ->
        do_publish(id, topic, msg, opts, qos, from, state)

      qos ->
        {:reply, {:error, {:invalid_qos, qos}}, state}
    end
  end

  @impl true
  def handle_info({{Tortoise311, id}, ref, result}, %State{client_id: id, refs: refs} = state) do
    case Map.pop(refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {from, refs} ->
        GenServer.reply(from, result)
        {:noreply, %State{state | refs: refs}}
    end
  end

  def handle_info({{Tortoise311, _id}, _ref, _result}, state), do: {:noreply, state}

  defp do_publish(id, topic, msg, opts, qos, from, %State{refs: refs} = state) do
    case Tortoise311.publish(id, topic, msg, opts) do
      :ok when qos == 0 ->
        {:reply, :ok, state}

      {:ok, ref} when qos in [1, 2] ->
        {:noreply, %State{state | refs: Map.put(refs, ref, from)}}

      {:error, _reason} = error ->
        {:reply, error, state}

      result ->
        {:reply, {:error, {:unexpected_publish_result, result}}, state}
    end
  end
end
