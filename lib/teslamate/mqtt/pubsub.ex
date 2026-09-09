defmodule TeslaMate.Mqtt.PubSub do
  @moduledoc """
  Keeps one `VehicleSubscriber` running per logged vehicle.

  The set of vehicles changes at runtime: signing in or out, toggling data
  collection and reloading the vehicle list all restart `TeslaMate.Vehicles`.
  This server subscribes to those reloads and reconciles its subscribers with
  the current vehicle list, so MQTT topics and Home Assistant discovery follow
  without a container restart.
  """
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias __MODULE__.VehicleSubscriber
  alias __MODULE__.HomeAssistant
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
    # Linked to this server: it goes down with it, and its children are the
    # subscribers this server reconciles.
    {:ok, supervisor} = Supervisor.start_link([], strategy: :one_for_one)
    :ok = Vehicles.subscribe()

    state = %State{
      supervisor: supervisor,
      opts: opts,
      deps: %{vehicles: Keyword.get(opts, :deps_vehicles, Vehicles)}
    }

    {:ok, sync(state)}
  end

  @impl true
  def handle_info({Vehicles, :reloaded}, %State{} = state) do
    {:noreply, sync(state)}
  end

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

  defp sync(%State{supervisor: supervisor, opts: opts, deps: deps} = state) do
    vehicles = call(deps.vehicles, :list, [])
    wanted = MapSet.new(vehicles, & &1.car.id)

    running =
      supervisor
      |> Supervisor.which_children()
      |> MapSet.new(fn {car_id, _pid, _type, _modules} -> car_id end)

    for car_id <- MapSet.difference(running, wanted) do
      :ok = Supervisor.terminate_child(supervisor, car_id)
      :ok = Supervisor.delete_child(supervisor, car_id)
    end

    subscriber_opts = Keyword.take(opts, @subscriber_opts)

    for car_id <- MapSet.difference(wanted, running) do
      spec =
        Supervisor.child_spec({VehicleSubscriber, Keyword.put(subscriber_opts, :car_id, car_id)},
          id: car_id
        )

      {:ok, _pid} = Supervisor.start_child(supervisor, spec)
    end

    if Keyword.get(opts, :discovery, false) do
      # Runs concurrently with the subscribers starting up, so it may fire
      # before the MQTT connection is established. Failures are only logged;
      # since the cleanup is idempotent and repeated on every sync, a missed
      # run is corrected on the next one.
      Task.start(fn -> clear_removed_vehicles(vehicles, opts) end)
    end

    state
  end
end
