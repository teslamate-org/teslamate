defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles

  defstruct [:car_id, :last_summary, :deps]
  alias __MODULE__, as: State

  def child_spec(arg) do
    %{
      id: :"#{__MODULE__}#{Keyword.fetch!(arg, :car_id)}",
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    car_id = Keyword.fetch!(opts, :car_id)

    deps = %{
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      publisher: Keyword.get(opts, :deps_publisher, Publisher)
    }

    :ok = call(deps.vehicles, :subscribe, [car_id])

    {:ok, %State{car_id: car_id, deps: deps}}
  end

  @impl true
  def handle_info(summary, %State{last_summary: summary} = state) do
    {:noreply, state}
  end

  def handle_info(summary, %State{car_id: car_id} = state) do
    summary
    |> Map.from_struct()
    |> Stream.reject(fn {key, _value} -> key in [:latitude, :longitude] end)
    |> Stream.filter(fn {key, value} ->
      key == :scheduled_charging_start_time or not is_nil(value)
    end)
    |> Task.async_stream(
      fn {key, value} ->
        call(state.deps.publisher, :publish, [
          "teslamate/cars/#{car_id}/#{key}",
          to_string(value),
          [retain: true, qos: 1]
        ])
      end,
      max_concurrency: 10,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {_, reason} when reason != :ok -> Logger.warn("MQTT publishing failed: #{inspect(reason)}")
      _ok -> nil
    end)

    {:noreply, %State{state | last_summary: summary}}
  end
end
