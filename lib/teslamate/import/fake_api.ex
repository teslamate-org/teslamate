defmodule TeslaMate.Import.FakeApi do
  use GenServer

  require Logger

  alias TeslaApi.Vehicle

  defmodule State do
    defstruct pid: nil,
              from: nil,
              events: [],
              event_chunks: {%{}, _idx = nil, _max_idx = nil},
              event_streams: [],
              current_chunk: nil,
              date_limit: nil
  end

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_vehicle(name, _id) do
    GenServer.call(name, :get_vehicle, :infinity)
  end

  def get_vehicle_with_state(name, _id) do
    GenServer.call(name, :get_vehicle_with_state, :infinity)
  end

  def stream(_name, _vid, _receiver) do
    {:ok, nil}
  end

  # Callbacks

  @impl true
  def init(opts) do
    pid = Keyword.fetch!(opts, :pid)
    event_streams = Keyword.fetch!(opts, :event_streams)
    date_limit = Keyword.fetch!(opts, :date_limit)

    date_limit_ts =
      with %DateTime{} <- date_limit do
        DateTime.to_unix(date_limit) * 1000
      end

    {:ok, %State{pid: pid, event_streams: event_streams, date_limit: date_limit_ts}}
  end

  @impl true
  def handle_call(_action, from, %State{} = state) do
    case pop(state) do
      {:error, :chunk_not_yet_received, state} ->
        {:noreply, %State{state | from: from}}

      {:done, state} ->
        processing_complete(state)
        {:noreply, state}

      {:event, %Vehicle{} = vehicle, state}
      when vehicle.drive_state.timestamp >= state.date_limit ->
        processing_complete(state)
        {:noreply, state}

      {:event, %Vehicle{} = vehicle, state} ->
        {:reply, {:ok, vehicle}, state}
    end
  end

  @impl true
  def handle_info({:processed_events, max_idx}, %State{} = state) do
    {:noreply, %State{state | event_chunks: set_max_chunk_idx(state.event_chunks, max_idx)}}
  end

  def handle_info({:events, events, idx}, %State{from: nil} = state) do
    {:noreply, %State{state | event_chunks: insert_event_chunk(state.event_chunks, idx, events)}}
  end

  def handle_info({:events, events, idx}, %State{from: from} = state) do
    state = %State{
      state
      | event_chunks: insert_event_chunk(state.event_chunks, idx, events),
        from: nil
    }

    case pop(state) do
      {:done, state} ->
        processing_complete(state)
        {:noreply, state}

      {:event, %Vehicle{} = vehicle, state}
      when vehicle.drive_state.timestamp >= state.date_limit ->
        processing_complete(state)
        {:noreply, state}

      {:event, %Vehicle{} = vehicle, state} ->
        GenServer.reply(from, {:ok, vehicle})
        {:noreply, state}
    end
  end

  ## Private

  defp pop(%State{events: [], event_chunks: {chunks, i, i}, event_streams: []} = state)
       when is_number(i) and chunks == %{} do
    {:done, state}
  end

  defp pop(%State{events: [], event_chunks: {_, i, i}, event_streams: [{c, s} | streams]} = state) do
    if state.current_chunk != nil, do: send(state.pid, {:done, state.current_chunk})

    state = %State{state | event_streams: streams, current_chunk: c}
    parent = self()

    spawn_link(fn ->
      s
      |> Stream.chunk_every(500)
      |> Stream.with_index()
      |> Enum.reduce(-1, fn {event_chunk, idx}, _ ->
        send(parent, {:events, event_chunk, idx})
        idx
      end)
      |> case do
        -1 -> send(parent, :no_events)
        max_idx -> send(parent, {:processed_events, max_idx})
      end
    end)

    receive do
      :no_events ->
        Logger.warning("Processed empty chunk: #{inspect(c)}")
        pop(%State{state | events: [], event_chunks: {%{}, nil, nil}})

      {:events, [event | events], 0} ->
        {:event, event, %State{state | events: events, event_chunks: {%{}, 0, nil}}}
    end
  end

  defp pop(%State{events: [], event_chunks: {event_chunks, idx, max_idx}} = state) do
    case Map.pop(event_chunks, new_idx = idx + 1) do
      {nil, _event_chunks} ->
        {:error, :chunk_not_yet_received, state}

      {events, event_chunks} ->
        pop(%State{state | events: events, event_chunks: {event_chunks, new_idx, max_idx}})
    end
  end

  defp pop(%State{events: [event | events]} = state) do
    {:event, event, %State{state | events: events}}
  end

  defp insert_event_chunk({chunks, chunk_idx, chunk_max_idx}, idx, events) do
    {Map.put(chunks, idx, events), chunk_idx, chunk_max_idx}
  end

  defp set_max_chunk_idx({chunks, chunk_idx, _}, chunk_max_idx) do
    {chunks, chunk_idx, chunk_max_idx}
  end

  defp processing_complete(%State{} = state) do
    send(state.pid, {:done, state.current_chunk})
    send(state.pid, :done)
  end
end
