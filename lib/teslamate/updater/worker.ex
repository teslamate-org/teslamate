defmodule TeslaMate.Updater.Worker do
  use GenServer
  alias TeslaMate.Updater

  @name __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  def get_update(name \\ @name) do
    GenServer.call(name, :get_update, 50)
  catch
    :exit, {:timeout, _} -> nil
    :exit, {:noproc, _} -> nil
  end

  @impl GenServer
  def init(opts) do
    {:ok, state} = Updater.init(opts)

    check_after = opts[:check_after] || :timer.minutes(5)
    interval = opts[:interval] || :timer.hours(72)

    {:ok, _} = :timer.send_interval(interval, :check_for_updates)

    case check_after do
      0 ->
        {:ok, state, {:continue, :check_for_updates}}

      t when is_number(t) and 0 < t ->
        Process.send_after(self(), :check_for_updates, t)
        {:ok, state}
    end
  end

  @impl GenServer
  def handle_continue(:check_for_updates, state) do
    new_state = Updater.check_for_updates(state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:check_for_updates, state) do
    {:noreply, state, {:continue, :check_for_updates}}
  end

  @impl GenServer
  def handle_call(:get_update, _from, state) do
    update = Updater.get_update(state)

    {:reply, update, state}
  end
end
