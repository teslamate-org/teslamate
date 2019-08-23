defmodule TeslaMate.Vehicles do
  use Supervisor

  require Logger

  alias __MODULE__.{Vehicle, Identification}
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
    Log.list_cars()
    |> Enum.map(&%TeslaApi.Vehicle{id: &1.eid})
  end

  defp create_or_update!(%TeslaApi.Vehicle{} = vehicle) do
    %{model: model, version: version, efficiency: efficiency} = Identification.properties(vehicle)

    Logger.info("Found Model #{version}: '#{vehicle.display_name}'")

    {:ok, car} =
      with nil <- Log.get_car_by_eid(vehicle.id) do
        %Car{eid: vehicle.id, vid: vehicle.vehicle_id}
      end
      |> Car.changeset(%{
        name: vehicle.display_name,
        model: model,
        efficiency: efficiency,
        version: version,
        vin: vehicle.vin
      })
      |> Log.create_or_update_car()

    car
  end
end
