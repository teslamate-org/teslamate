defmodule VehiclesMock do
  use GenServer

  defstruct [:pid, summaries: []]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def list(name), do: GenServer.call(name, :list)
  def set_summaries(name, summaries), do: GenServer.call(name, {:set_summaries, summaries})

  def kill(name), do: GenServer.call(name, :kill)
  def restart(name), do: GenServer.call(name, :restart)

  def subscribe_to_summary(name, car_id) do
    GenServer.call(name, {:subscribe_to_summary, car_id})
  end

  # Callbacks

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), summaries: Keyword.get(opts, :summaries, [])}}
  end

  @impl true
  def handle_call({:subscribe_to_summary, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, {VehiclesMock, action})
    {:reply, :ok, state}
  end

  def handle_call(:list, _from, %State{summaries: summaries} = state) do
    {:reply, summaries, state}
  end

  def handle_call({:set_summaries, summaries}, _from, %State{} = state) do
    {:reply, :ok, %State{state | summaries: summaries}}
  end

  def handle_call(:kill, _from, %State{pid: pid} = state) do
    send(pid, {VehiclesMock, :kill})
    {:reply, true, state}
  end

  def handle_call(:restart, _from, %State{pid: pid} = state) do
    send(pid, {VehiclesMock, :restart})
    {:reply, :ok, state}
  end
end
