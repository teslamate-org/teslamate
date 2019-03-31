defmodule TeslaMate.Vehicles do
  use Supervisor

  alias __MODULE__.Vehicle

  @name __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(opts) do
    vehicles =
      Keyword.get_lazy(opts, :vehicles, fn ->
        {:ok, vehicles} = TeslaMate.Api.list_vehicles()
        vehicles
      end)

    children =
      vehicles
      |> Enum.map(fn %TeslaApi.Vehicle{} = vehicle ->
        {Vehicle, vehicle}
      end)

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 60)
  end
end
