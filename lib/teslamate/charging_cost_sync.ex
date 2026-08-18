defmodule TeslaMate.ChargingCostSync do
  use GenServer

  require Logger

  alias TeslaApi.ChargingHistory.Result

  import Core.Dependency, only: [call: 3, call: 2]

  defmodule State do
    defstruct name: nil,
              deps: %{},
              interval: nil,
              backfilled_cars: MapSet.new(),
              timer: nil
  end

  @name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def trigger_sync(name \\ @name), do: send(name, :sync)

  @impl true
  def init(opts) do
    state = %State{
      name: Keyword.fetch!(opts, :name),
      deps: %{
        api: Keyword.get(opts, :api, TeslaMate.Api),
        log: Keyword.get(opts, :log, TeslaMate.Log)
      },
      interval: Keyword.get(opts, :interval, :timer.minutes(90))
    }

    {:ok, state, {:continue, :initial_sync}}
  end

  @impl true
  def handle_continue(:initial_sync, state) do
    {:noreply, run_sync(state) |> schedule_sync()}
  end

  @impl true
  def handle_info(:sync, %State{} = state) do
    if is_reference(state.timer), do: Process.cancel_timer(state.timer)
    {:noreply, run_sync(%State{state | timer: nil}) |> schedule_sync()}
  end

  def handle_info(message, state) do
    Logger.warning("Unexpected message: #{inspect(message, pretty: true)}")
    {:noreply, state}
  end

  defp run_sync(%State{} = state) do
    cars = call(state.deps.log, :list_cars)

    Logger.info("Synchronizing Tesla Supercharger costs for #{length(cars)} vehicle(s)")

    Enum.reduce(cars, state, fn car, state -> sync_car(car, state) end)
  rescue
    error ->
      Logger.warning("Supercharger cost synchronization failed: #{Exception.message(error)}")
      state
  end

  defp sync_car(%{id: car_id, vin: vin} = car, %State{} = state) when is_binary(vin) do
    page_limit = if MapSet.member?(state.backfilled_cars, car_id), do: 1, else: :all

    case call(state.deps.api, :get_charging_history, [vin, [page_limit: page_limit]]) do
      {:ok, %Result{sessions: sessions}} ->
        summary =
          Enum.reduce(sessions, %{updated: 0, no_match: 0, skipped: 0}, fn session, counts ->
            case call(state.deps.log, :sync_charging_cost, [car, session]) do
              {:ok, _id} -> Map.update!(counts, :updated, &(&1 + 1))
              :no_match -> Map.update!(counts, :no_match, &(&1 + 1))
              _other -> Map.update!(counts, :skipped, &(&1 + 1))
            end
          end)

        Logger.info(
          "Supercharger cost synchronization completed: " <>
            "#{summary.updated} updated, #{summary.no_match} unmatched, " <>
            "#{summary.skipped} skipped",
          car_id: car_id
        )

        %State{state | backfilled_cars: MapSet.put(state.backfilled_cars, car_id)}

      {:error, reason} ->
        Logger.warning(
          "Supercharger cost synchronization failed: #{inspect(reason, pretty: true)}",
          car_id: car_id
        )

        state
    end
  end

  defp sync_car(%{id: car_id}, state) do
    Logger.warning("Skipping Supercharger cost synchronization: vehicle has no VIN",
      car_id: car_id
    )

    state
  end

  defp schedule_sync(%State{timer: timer} = state) do
    if is_reference(timer), do: Process.cancel_timer(timer)
    %State{state | timer: Process.send_after(self(), :sync, state.interval)}
  end
end
