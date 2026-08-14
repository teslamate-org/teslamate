defmodule TeslaMate.Mqtt.PubSub do
  use Supervisor

  require Logger

  alias __MODULE__.VehicleSubscriber
  alias __MODULE__.HomeAssistant
  alias TeslaMate.Log
  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles
  alias TeslaMate.Vehicles.Vehicle.Summary

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    subscriber_opts =
      opts
      |> Keyword.take([:namespace, :discovery, :discovery_base_url, :discovery_prefix])

    vehicles = Vehicles.list()

    if Keyword.get(opts, :discovery, false) do
      # Runs concurrently with the supervised children starting up, so it may
      # fire before the MQTT connection is established. Failures are only
      # logged; since the cleanup is idempotent and repeated on every start,
      # a missed run is corrected on the next restart.
      Task.start(fn -> clear_removed_vehicles(vehicles, opts) end)
    end

    children =
      vehicles
      |> Enum.map(&{VehicleSubscriber, Keyword.merge(subscriber_opts, car_id: &1.car.id)})

    Supervisor.init(children, strategy: :one_for_one)
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
end
