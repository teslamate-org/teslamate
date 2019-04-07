defmodule TeslaMate.Vehicles do
  use Supervisor

  alias __MODULE__.Vehicle

  @name __MODULE__

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(opts) do
    children =
      opts
      |> Keyword.get_lazy(:vehicles, &list_vehicles!/0)
      |> Enum.map(&{Vehicle, vehicle: &1})

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 60)
  end

  defp list_vehicles! do
    {:ok, vehicles} = TeslaMate.Api.list_vehicles()
    vehicles
  end
end
