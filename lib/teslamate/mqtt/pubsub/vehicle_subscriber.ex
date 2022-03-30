defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriber do
  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Mqtt.Publisher
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Locations.GeoFence
  alias TeslaMate.Vehicles

  defstruct [:car_id, :last_summary, :deps, :namespace]
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
    namespace = Keyword.fetch!(opts, :namespace)

    deps = %{
      vehicles: Keyword.get(opts, :deps_vehicles, Vehicles),
      publisher: Keyword.get(opts, :deps_publisher, Publisher)
    }

    :ok = call(deps.vehicles, :subscribe_to_summary, [car_id])

    {:ok, %State{car_id: car_id, namespace: namespace, deps: deps}}
  end

  @impl true
  def handle_info(summary, %State{last_summary: summary} = state) do
    {:noreply, state}
  end

  @always_published ~w(charge_energy_added charger_actual_current charger_phases
                       charger_power charger_voltage scheduled_charging_start_time
                       time_to_full_charge shift_state geofence trim_badging)a

  def handle_info(%Summary{} = summary, state) do
    summary
    |> Map.from_struct()
    |> Map.drop([:car])
    |> Stream.reject(&match?({_key, :unknown}, &1))
    |> Stream.filter(fn {key, value} ->
      (key in @always_published or value != nil) and
        (state.last_summary == nil or Map.get(state.last_summary, key) != value)
    end)
    |> Stream.map(fn
      {key = :geofence, %GeoFence{name: name}} -> {key, name}
      {key = :geofence, nil} -> {key, Application.get_env(:teslamate, :default_geofence)}
      {key, val} -> {key, val}
    end)
    |> Task.async_stream(&publish(&1, state),
      max_concurrency: 10,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.each(fn
      {_, reason} when reason != :ok ->
        Logger.warning("MQTT publishing failed: #{inspect(reason)}")

      _ok ->
        nil
    end)

    {:noreply, %State{state | last_summary: summary}}
  end

  defp publish({key, value}, %State{car_id: car_id, namespace: namespace, deps: deps}) do
    topic =
      ["teslamate", namespace, "cars", car_id, key]
      |> Enum.reject(&is_nil(&1))
      |> Enum.join("/")

    call(deps.publisher, :publish, [topic, to_str(value), [retain: true, qos: 1]])
  end

  defp to_str(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp to_str(value), do: to_string(value)
end
