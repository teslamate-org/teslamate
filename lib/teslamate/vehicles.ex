defmodule TeslaMate.Vehicles do
  use Supervisor

  require Logger

  alias TeslaMate.Log
  alias __MODULE__.{Vehicle, Identification}

  @name __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  defdelegate summary(id), to: Vehicle
  defdelegate resume_logging(id), to: Vehicle
  defdelegate suspend_logging(id), to: Vehicle
  defdelegate subscribe(id), to: Vehicle

  @impl true
  def init(opts) do
    children =
      opts
      |> Keyword.get_lazy(:vehicles, &list_vehicles!/0)
      |> Enum.map(&{Vehicle, car: create_new!(&1)})

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 60)
  end

  defp list_vehicles! do
    {:ok, vehicles} = TeslaMate.Api.list_vehicles()
    vehicles
  end

  defp create_new!(%TeslaApi.Vehicle{} = vehicle) do
    Logger.info("Found car '#{vehicle.display_name}'")

    {:ok, car} =
      case Log.get_car_by_eid(vehicle.id) do
        nil ->
          properties = Identification.properties(vehicle)

          Log.create_car(%{
            eid: vehicle.id,
            vid: vehicle.vehicle_id,
            model: properties.model,
            efficiency: properties.efficiency
          })

        car ->
          {:ok, car}
      end

    car
  end
end
