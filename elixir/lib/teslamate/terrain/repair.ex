defmodule TeslaMate.Terrain.Repair do
  @moduledoc """
  Adds the terrain elevation that positions of drives lack, at start and
  every 6 hours, one drive at a time (`Log.get_terrain_elevation_drives/1`):
  it looks the elevations up through `TeslaMate.Terrain` with no transaction
  open, then stores them in one transaction with the drive's ascent and
  descent (`Log.add_terrain_elevation/4`).

  It is a process of its own, so that Terrain, which answers the vehicles'
  lookups, does no database work.

  A pass ends early once Terrain answers `:unavailable` (its circuit breaker
  blown, or disabled): until it recovers, every further lookup would fail
  too, and the drives that still wait for it would only cost their queries.
  They wait for the next pass, so a pass stays bounded however many drives
  wait while the terrain cannot be looked up.
  """

  use GenServer

  require Logger
  import Core.Dependency, only: [call: 3]

  alias TeslaMate.{Log, Terrain}
  alias TeslaMate.Log.Position

  defstruct [:deps]
  alias __MODULE__, as: State

  @interval :timer.hours(6)

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  # Callbacks

  @impl true
  def init(opts) do
    state = %State{
      deps: %{
        log: Keyword.get(opts, :deps_log, Log),
        terrain: Keyword.get(opts, :deps_terrain, Terrain),
        clock: Keyword.get(opts, :deps_clock, DateTime)
      }
    }

    {:ok, state, {:continue, :repair}}
  end

  @impl true
  def handle_continue(:repair, %State{deps: deps} = state) do
    # One clock reading for the whole pass.
    now = deps.clock.utc_now()
    drives = call(deps.log, :get_terrain_elevation_drives, [[now: now]])

    Enum.reduce_while(drives, :ok, fn drive, :ok ->
      case repair_drive(drive, now, deps) do
        :answered -> {:cont, :ok}
        :unavailable -> {:halt, :ok}
      end
    end)

    Process.send_after(self(), :repair, @interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:repair, state) do
    {:noreply, state, {:continue, :repair}}
  end

  # Private

  # Looks up the drive's positions until Terrain answers :unavailable. Only a
  # drive closed when listed can end its wait (:complete): positions an open
  # one takes meanwhile were never looked up. A drive whose lookups failed is
  # :failed and taken last from then on; one whose lookups only ended, as
  # Terrain became unavailable before its turn, keeps its place. A drive
  # with nothing to store and no queue entry to settle takes no transaction.
  defp repair_drive(%{id: drive_id, end_date: end_date, queued: queued}, now, deps) do
    positions = call(deps.log, :get_positions_without_elevation, [drive_id])

    if positions != [] do
      Logger.info("Adding elevation to #{length(positions)} positions of drive ##{drive_id} ...")
    end

    {answers, terrain} = look_up(positions, deps)

    elevations =
      for {id, {:ok, elevation}} <- answers, not is_nil(elevation), into: %{}, do: {id, elevation}

    status =
      cond do
        Enum.any?(answers, &match?({_id, {:error, _reason}}, &1)) -> :failed
        terrain == :answered and not is_nil(end_date) -> :complete
        true -> :incomplete
      end

    if elevations != %{} or queued or (status == :failed and not is_nil(end_date)) do
      :ok = call(deps.log, :add_terrain_elevation, [drive_id, elevations, status, [now: now]])
    end

    terrain
  end

  # The answers, and whether Terrain answered every lookup or became
  # :unavailable, which ends the lookups.
  defp look_up(positions, deps), do: look_up(positions, [], deps)

  defp look_up([], answers, _deps), do: {answers, :answered}

  defp look_up([%Position{} = position | rest], answers, deps) do
    coordinates = {Decimal.to_float(position.latitude), Decimal.to_float(position.longitude)}

    case call(deps.terrain, :await_elevation, [coordinates]) do
      {:error, :unavailable} -> {answers, :unavailable}
      answer -> look_up(rest, [{position.id, answer} | answers], deps)
    end
  end
end
