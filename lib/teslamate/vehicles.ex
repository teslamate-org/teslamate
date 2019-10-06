defmodule TeslaMate.Vehicles do
  use Supervisor

  require Logger

  alias __MODULE__.Vehicle
  alias TeslaMate.Log.Car
  alias TeslaMate.Log

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
      |> Enum.map(&{Keyword.get(opts, :vehicle, Vehicle), car: create_or_update!(&1)})

    Supervisor.init(children,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end

  def kill do
    Logger.warn("Restarting #{__MODULE__} supervisor")
    __MODULE__ |> Process.whereis() |> Process.exit(:kill)
  end

  def restart do
    with :ok <- Supervisor.stop(@name, :normal),
         :ok <- block_until_started(250) do
      :ok
    end
  end

  defp block_until_started(0), do: {:error, :restart_failed}

  defp block_until_started(retries) when retries > 0 do
    with pid when is_pid(pid) <- Process.whereis(@name),
         true <- Process.alive?(pid) do
      :ok
    else
      _ ->
        :timer.sleep(10)
        block_until_started(retries - 1)
    end
  end

  defp list_vehicles! do
    case TeslaMate.Api.list_vehicles() do
      {:error, :not_signed_in} -> fallback_vehicles()
      {:ok, []} -> fallback_vehicles()
      {:ok, vehicles} -> vehicles
    end
  end

  defp fallback_vehicles do
    vehicles =
      Log.list_cars()
      |> Enum.map(&%TeslaApi.Vehicle{id: &1.eid, vin: &1.vin, vehicle_id: &1.vid})

    if vehicles != [] do
      Logger.warn("Using fallback vehicles:\n\n#{inspect(vehicles, pretty: true)}")
    end

    vehicles
  end

  defp create_or_update!(%TeslaApi.Vehicle{} = vehicle) do
    Logger.info("Found '#{vehicle.display_name}'")

    {:ok, car} =
      with nil <- Log.get_car_by(vin: vehicle.vin),
           nil <- Log.get_car_by(vid: vehicle.vehicle_id),
           nil <- Log.get_car_by(eid: vehicle.id) do
        %Car{}
      end
      |> Car.changeset(%{
        name: vehicle.display_name,
        eid: vehicle.id,
        vid: vehicle.vehicle_id,
        vin: vehicle.vin
      })
      |> Log.create_or_update_car()

    car
  end
end
