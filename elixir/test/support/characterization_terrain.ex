defmodule TeslaMate.Characterization.Terrain do
  @moduledoc """
  One pass of the production `TeslaMate.Terrain.Repair` inside a
  characterization replay — the `{"repair": "elevation"}` event.

  The pass runs against the replay's database through the real `Log`, on
  the replay's clock (`TeslaMate.Characterization.Clock`, so its window
  covers the replay's dates), and looks the elevations up through the
  production `TeslaMate.Terrain` with `TerrainMock` as its SRTM dependency:
  the declared `terrain` rows answer the repair's lookups, after the lookups
  at insert have used up their `unavailable_lookups`.

  The repair runs its pass on start, before it handles any other message,
  so one `:sys.get_state/1` returns once the pass is over, without a
  wall-clock wait.
  """

  alias TeslaMate.{Characterization, Log, Terrain}
  alias TeslaMate.Terrain.Repair

  def repair_elevation do
    name = :"characterization_terrain_#{System.unique_integer([:positive])}"

    {:ok, terrain} = Terrain.start_link(name: name, deps_srtm: TerrainMock)

    {:ok, repair} =
      Repair.start_link(
        name: :"#{name}_repair",
        deps_log: Log,
        deps_terrain: {Terrain, name},
        deps_clock: Characterization.Clock
      )

    _state = :sys.get_state(repair)
    :ok = GenServer.stop(repair)
    :ok = GenStateMachine.stop(terrain)

    # Terrain installs its circuit breaker under its name on the first
    # lookup; the name is unique per pass, so the fuse goes with it.
    _ = :fuse.remove(name)

    :ok
  end
end
