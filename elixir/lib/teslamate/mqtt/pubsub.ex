defmodule TeslaMate.Mqtt.PubSub do
  @moduledoc """
  Keeps one `VehicleSubscriber` running per logged vehicle.

  The subscribers are built from the vehicle list at start-up. Vehicles added
  later by `TeslaMate.Vehicles.discover/0` announce themselves with
  `{TeslaMate.Vehicles, :vehicles_changed}`; this process then starts the
  missing subscribers, which publish the new car's topics and its Home
  Assistant discovery config. Running subscribers are untouched, and the
  Home Assistant cleanup for removed cars runs at start-up only: a discovery
  can only add vehicles.
  """
  use GenServer, shutdown: :infinity

  require Logger
  import Core.Dependency, only: [call: 3]

  alias __MODULE__.HomeAssistant
  alias __MODULE__.VehicleSubscriber
  alias TeslaMate.Log
  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles
  alias TeslaMate.Vehicles.Vehicle.Summary

  defstruct [:supervisor, :opts, :deps]
  alias __MODULE__, as: State

  @subscriber_opts [
    :namespace,
    :discovery,
    :discovery_base_url,
    :discovery_prefix,
    :deps_vehicles,
    :deps_publisher
  ]

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    :ok = Vehicles.subscribe()

    deps = %{vehicles: Keyword.get(opts, :deps_vehicles, Vehicles)}
    vehicles = call(deps.vehicles, :list, [])

    if Keyword.get(opts, :discovery, false) do
      # Runs concurrently with the subscribers starting up, so it may fire
      # before the MQTT connection is established. Failures are only logged;
      # since the cleanup is idempotent and repeated on every start, a missed
      # run is corrected on the next restart.
      Task.start(fn -> clear_removed_vehicles(vehicles, opts) end)
    end

    {:ok, supervisor} =
      vehicles
      |> Enum.map(&subscriber_spec(&1.car.id, opts))
      |> Supervisor.start_link(strategy: :one_for_one)

    {:ok, %State{supervisor: supervisor, opts: opts, deps: deps}}
  end

  @impl true
  def handle_info({Vehicles, :vehicles_changed}, %State{} = state) do
    {:noreply, start_missing_subscribers(state)}
  end

  def handle_info({:EXIT, supervisor, reason}, %State{supervisor: supervisor} = state) do
    {:stop, reason, %State{state | supervisor: nil}}
  end

  @impl true
  def terminate(reason, %State{supervisor: supervisor}) when is_pid(supervisor) do
    Supervisor.stop(supervisor, reason)
  end

  def terminate(_reason, %State{supervisor: nil}), do: :ok

  @doc """
  Clears Home Assistant discovery configs for cars that are no longer
  tracked by a vehicle process, e.g. because they were removed from the
  Tesla account or because logging was disabled, so their entities are
  removed from Home Assistant.
  """
  @spec clear_removed_vehicles([Summary.t()], keyword()) :: :ok
  def clear_removed_vehicles(vehicles, opts) do
    publisher = Keyword.get(opts, :deps_publisher, Publisher)
    active_ids = Enum.map(vehicles, & &1.car.id)
    clear_opts = Keyword.take(opts, [:namespace, :discovery_prefix])

    Log.list_cars()
    |> Enum.reject(&(&1.id in active_ids))
    |> Enum.each(fn car ->
      case HomeAssistant.clear(car.id, clear_opts, publisher) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("MQTT HA discovery cleanup failed: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # Private

  defp start_missing_subscribers(%State{supervisor: supervisor, opts: opts, deps: deps} = state) do
    for %Summary{car: %{id: car_id}} <- call(deps.vehicles, :list, []) do
      case Supervisor.start_child(supervisor, subscriber_spec(car_id, opts)) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          Logger.warning("MQTT subscriber for car #{car_id} failed: #{inspect(reason)}")
      end
    end

    state
  end

  defp subscriber_spec(car_id, opts) do
    opts = opts |> Keyword.take(@subscriber_opts) |> Keyword.put(:car_id, car_id)
    Supervisor.child_spec({VehicleSubscriber, opts}, id: car_id)
  end
end
