defmodule TeslaMate.Vehicles.Vehicle do
  use GenServer

  require Logger

  alias __MODULE__.Identification

  # import Core.Dependency, only: [call: 3]

  defstruct id: nil,
            properties: nil,
            deps: %{}

  alias __MODULE__, as: State

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @impl true
  def init(%TeslaApi.Vehicle{} = vehicle) do
    properties = Identification.properties(vehicle)

    Logger.info("Found Vehicle '#{vehicle.display_name}' [#{inspect(properties)}]")

    {:ok, %State{id: vehicle.vehicle_id, properties: properties}, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, state) do
    {:noreply, state}
  end

  # Private
end
