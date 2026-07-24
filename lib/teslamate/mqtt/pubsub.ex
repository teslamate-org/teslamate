defmodule TeslaMate.Mqtt.PubSub do
  use Supervisor

  alias __MODULE__.VehicleSubscriber
  alias TeslaMate.Vehicles

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    subscriber_opts =
      opts
      |> Keyword.take([:namespace, :discovery, :discovery_base_url, :discovery_prefix])

    children =
      Vehicles.list()
      |> Enum.map(&{VehicleSubscriber, Keyword.merge(subscriber_opts, car_id: &1.car.id)})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
