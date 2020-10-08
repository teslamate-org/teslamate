defmodule TeslaMate.Import.FakeApi do
  use GenServer

  require Logger

  alias TeslaApi.Vehicle.State.Drive
  alias TeslaApi.Vehicle

  defstruct(pid: nil, events: [], event_streams: [], current_chunk: nil, date_limit: nil)
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name), fullsweep_after: 10)
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

    {:ok, _ref} = :timer.send_interval(:timer.minutes(2), self(), :garbage_collect)

    {:ok, %State{pid: pid, event_streams: event_streams, date_limit: date_limit_ts}}
  end

  @impl true
  def handle_call(_action, _from, %State{date_limit: date_limit} = state) do
    case pop(state) do
      {:done, state} ->
        send(state.pid, {:done, state.current_chunk})
        send(state.pid, :done)
        {:noreply, state}

      {{:ok, %Vehicle{drive_state: %Drive{timestamp: ts}}}, state}
      when ts >= date_limit ->
        send(state.pid, {:done, state.current_chunk})
        send(state.pid, :done)
        {:noreply, state}

      {{:ok, %Vehicle{}} = event, state} ->
        {:reply, event, state}
    end
  end

  @impl true
  def handle_info(:garbage_collect, state) do
    :erlang.garbage_collect(self())
    {:noreply, state}
  end

  ## Private

  def pop(%State{events: [], event_streams: []} = state) do
    {:done, state}
  end

  def pop(%State{events: [], event_streams: [{chunk, s} | streams]} = state) do
    if state.current_chunk != nil, do: send(state.pid, {:done, state.current_chunk})

    case Enum.into(s, []) do
      [event | events] ->
        {event, %State{state | events: events, event_streams: streams, current_chunk: chunk}}

      [] ->
        Logger.warning("Processed empty chunk: #{inspect(chunk)}")
        pop(%State{state | events: [], event_streams: streams, current_chunk: chunk})
    end
  end

  def pop(%State{events: [event | events]} = state) do
    {event, %State{state | events: events}}
  end
end
