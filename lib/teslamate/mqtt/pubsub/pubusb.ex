defmodule TeslaMate.Mqtt.PubSub do
  use Supervisor

  alias __MODULE__.VehicleSubscriber
  alias TeslaMate.Log

  # API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      Log.list_cars()
      |> Enum.map(&{VehicleSubscriber, car_id: &1.id})

    Supervisor.init(children, strategy: :one_for_one)
  end
end
