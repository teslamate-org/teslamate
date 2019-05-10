defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles

  defstruct [:car_id, :last_summary]
  alias __MODULE__, as: State

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    :ok = Vehicles.subscribe(car_id)
    {:ok, %State{car_id: car_id}}
  end

  @impl true
  def handle_info(summary, %State{last_summary: summary} = state) do
    {:noreply, state}
  end

  def handle_info(summary, %State{car_id: car_id} = state) do
    summary
    |> Map.from_struct()
    |> Stream.filter(fn {_key, value} -> not is_nil(value) end)
    |> Task.async_stream(
      fn {key, value} ->
        Publisher.publish("teslamate/cars/#{car_id}/#{key}", to_string(value),
          retain: true,
          qos: 1
        )
      end,
      max_concurrency: 10,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {_, reason} when reason != :ok -> Logger.warn("MQTT publishing failed: #{inspect(reason)}")
      _ok -> nil
    end)

    {:noreply, state}
  end
end
