defmodule TeslaMate.Mutex do
  @moduledoc """
  Runs functions one at a time, each in its calling process.

  Callers wait for their turn in the order they asked, without polling. The
  lock follows the holder's lifetime: it is released when the function
  returns or raises, or when the holder dies. A caller that dies while
  waiting leaves the queue. So a holder that is shut down never blocks the
  callers behind it.

  A holder must not run the same mutex again: it would wait for itself.

  ## Options

    * `:name` - required, the name of the mutex
    * `:interval` - the least time in milliseconds between the starts of two
      functions, for all callers together (default: 0). A caller whose turn
      comes earlier waits in its own process before it runs the function.
      A holder that dies still counts as started.
    * `:clock` - returns the time in milliseconds the interval is measured in
      (default: the monotonic time)
    * `:pause` - waits the given milliseconds (default: `Process.sleep/1`)
  """

  use GenServer

  # Several mutexes run side by side: each one by its name.
  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :name)}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def run(mutex, fun) when is_function(fun, 0) do
    {ref, wait} = GenServer.call(mutex, :acquire, :infinity)

    try do
      wait.()
      fun.()
    after
      GenServer.cast(mutex, {:release, ref})
    end
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok,
     %{
       holder: nil,
       waiting: :queue.new(),
       interval: Keyword.get(opts, :interval, 0),
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
       pause: Keyword.get(opts, :pause, &Process.sleep/1),
       next_start: nil
     }}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag} = from, %{holder: nil} = state) do
    ref = Process.monitor(pid)
    {:noreply, grant(from, ref, state)}
  end

  def handle_call(:acquire, {pid, _tag} = from, state) do
    ref = Process.monitor(pid)
    {:noreply, %{state | waiting: :queue.in({from, ref}, state.waiting)}}
  end

  @impl true
  def handle_cast({:release, ref}, %{holder: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, grant_next(state)}
  end

  # Only after a restart of the mutex: the holder had acquired it before.
  def handle_cast({:release, _ref}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{holder: ref} = state) do
    {:noreply, grant_next(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    waiting = :queue.filter(fn {_from, waiting_ref} -> waiting_ref != ref end, state.waiting)
    {:noreply, %{state | waiting: waiting}}
  end

  defp grant_next(state) do
    case :queue.out(state.waiting) do
      {{:value, {from, ref}}, waiting} ->
        grant(from, ref, %{state | waiting: waiting})

      {:empty, waiting} ->
        %{state | holder: nil, waiting: waiting}
    end
  end

  # The holder starts once the interval since the previous start has passed:
  # the start is counted here, so it counts even if the holder dies.
  defp grant(from, ref, state) do
    %{clock: clock, pause: pause} = state
    now = clock.()
    ms = max((state.next_start || now) - now, 0)
    wait = if ms > 0, do: fn -> pause.(ms) end, else: fn -> :ok end
    GenServer.reply(from, {ref, wait})
    %{state | holder: ref, next_start: now + ms + state.interval}
  end
end
