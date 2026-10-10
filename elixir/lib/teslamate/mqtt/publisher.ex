defmodule TeslaMate.Mqtt.Publisher do
  use GenServer

  @name __MODULE__
  @timeout :timer.seconds(10)
  @publish_timeout round(@timeout * 0.95)

  defstruct client_id: nil,
            refs: %{}

  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def publish(topic, msg \\ nil, opts \\ []) do
    GenServer.call(@name, {:publish, topic, msg, opts}, @timeout)
  catch
    :exit, {:timeout, _call} ->
      {:error, :timeout}

    :exit, {reason, _call} when reason in [:noproc, :normal, :shutdown] ->
      {:error, :publisher_unavailable}

    :exit, {{:shutdown, _reason}, _call} ->
      {:error, :publisher_unavailable}
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{client_id: Keyword.fetch!(opts, :client_id)}}
  end

  @impl true
  def handle_call({:publish, topic, msg, opts}, from, %State{client_id: id} = state) do
    case Keyword.get(opts, :qos, 0) do
      qos when qos in [0, 1, 2] ->
        case Keyword.get(opts, :timeout, @publish_timeout) do
          timeout when is_integer(timeout) and timeout >= 0 ->
            timeout = min(timeout, @publish_timeout)

            do_publish(
              id,
              topic,
              msg,
              Keyword.put(opts, :timeout, timeout),
              qos,
              from,
              timeout,
              state
            )

          timeout ->
            {:reply, {:error, {:invalid_timeout, timeout}}, state}
        end

      qos ->
        {:reply, {:error, {:invalid_qos, qos}}, state}
    end
  end

  @impl true
  def handle_info({{Tortoise311, id}, ref, result}, %State{client_id: id, refs: refs} = state) do
    case Map.pop(refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {{from, timer}, refs} ->
        Process.cancel_timer(timer)
        GenServer.reply(from, result)
        {:noreply, %State{state | refs: refs}}
    end
  end

  def handle_info({{Tortoise311, _id}, _ref, _result}, state), do: {:noreply, state}

  def handle_info({:publish_timeout, ref}, %State{refs: refs} = state) do
    case Map.pop(refs, ref) do
      {nil, _refs} ->
        {:noreply, state}

      {{from, _timer}, refs} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %State{state | refs: refs}}
    end
  end

  defp do_publish(id, topic, msg, opts, qos, from, timeout, %State{refs: refs} = state) do
    case Tortoise311.publish(id, topic, msg, opts) do
      :ok when qos == 0 ->
        {:reply, :ok, state}

      {:ok, ref} when qos in [1, 2] ->
        timer = Process.send_after(self(), {:publish_timeout, ref}, timeout)
        {:noreply, %State{state | refs: Map.put(refs, ref, {from, timer})}}

      {:error, _reason} = error ->
        {:reply, error, state}

      result ->
        {:reply, {:error, {:unexpected_publish_result, result}}, state}
    end
  end
end
