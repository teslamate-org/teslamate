defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles

  @retained [:state, :ideal_battery_range_km, :battery_level]

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Callbacks

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    :ok = Vehicles.subscribe(car_id)
    {:ok, car_id}
  end

  @impl true
  def handle_info(summary, car_id) do
    stream =
      summary
      |> Map.from_struct()
      |> Task.async_stream(
        fn {key, value} ->
          Publisher.publish("teslamate/cars/#{car_id}/#{key}", to_string(value),
            retain: key in @retained,
            qos: 1
          )
        end,
        max_concurrency: 10,
        ordered: false
      )

    for {:ok, result} <- stream do
      if result != :ok, do: Logger.warn("MQTT publishing failed: #{inspect(result)}")
    end

    {:noreply, car_id}
  end
end
