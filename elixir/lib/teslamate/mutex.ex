defmodule TeslaMate.Mutex do
  @moduledoc """
  Runs functions one at a time, each in its calling process.

  Callers wait for their turn in the order they asked, without polling. The
  lock follows the holder's lifetime: it is released when the function
  returns or raises, or when the holder dies. A caller that dies while
  waiting leaves the queue. So a holder that is shut down never blocks the
  callers behind it.

  A holder must not run the same mutex again: it would wait for itself.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.fetch!(opts, :name))
  end

  def run(mutex, fun) when is_function(fun, 0) do
    ref = GenServer.call(mutex, :acquire, :infinity)

    try do
      fun.()
    after
      GenServer.cast(mutex, {:release, ref})
    end
  end

  # Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{holder: nil, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, {pid, _tag} = from, %{holder: nil} = state) do
    ref = Process.monitor(pid)
    GenServer.reply(from, ref)
    {:noreply, %{state | holder: ref}}
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
        GenServer.reply(from, ref)
        %{state | holder: ref, waiting: waiting}

      {:empty, waiting} ->
        %{state | holder: nil, waiting: waiting}
    end
  end
end
