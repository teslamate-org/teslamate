defmodule TeslaMate.Characterization.Vehicles do
  @moduledoc """
  Stand-in for `TeslaMate.Vehicles` inside a characterization replay.

  Production `Vehicles.kill/0` terminates the `Vehicles` supervisor and with
  it every vehicle process, which the supervisor tree then restarts. A replay
  runs exactly one vehicle under the test supervisor, so `kill` terminates
  that vehicle process — the effect on the vehicle under replay is the same
  (`Process.exit(pid, :kill)`, restarted by its `:permanent` child spec when
  the scenario declares `expect_restart`). `restart` and
  `subscribe_to_summary` only notify the collector, like `VehiclesMock`.
  """

  use GenServer

  defstruct [:pid, :vehicle]
  alias __MODULE__, as: State

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def kill(name), do: GenServer.call(name, :kill)
  def restart(name), do: GenServer.call(name, :restart)

  def subscribe_to_summary(name, car_id) do
    GenServer.call(name, {:subscribe_to_summary, car_id})
  end

  @impl true
  def init(opts) do
    {:ok, %State{pid: Keyword.fetch!(opts, :pid), vehicle: Keyword.fetch!(opts, :vehicle)}}
  end

  @impl true
  def handle_call(:kill, _from, %State{pid: pid, vehicle: vehicle} = state) do
    send(pid, {__MODULE__, :kill})

    case Process.whereis(vehicle) do
      nil -> :ok
      vehicle_pid -> Process.exit(vehicle_pid, :kill)
    end

    {:reply, true, state}
  end

  def handle_call(:restart, _from, %State{pid: pid} = state) do
    send(pid, {__MODULE__, :restart})
    {:reply, :ok, state}
  end

  def handle_call({:subscribe_to_summary, _car_id} = action, _from, %State{pid: pid} = state) do
    send(pid, {__MODULE__, action})
    {:reply, :ok, state}
  end
end
