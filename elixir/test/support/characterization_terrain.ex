defmodule TeslaMate.Characterization.Terrain do
  @moduledoc """
  One repair pass of the production `TeslaMate.Terrain` inside a
  characterization replay — the `{"repair": "elevation"}` event.

  The pass runs against the replay's database through the real `Log`, on
  the replay's clock (`TeslaMate.Characterization.Clock`, so the first page's
  window covers the replay's dates), with `TerrainMock` as its SRTM
  dependency: the declared `terrain` rows answer the repair's lookups, after
  the lookups at insert have used up their `unavailable_lookups`.

  The pass is over when Terrain has fetched an empty page: it is then
  `:ready` with the next pass scheduled as its only timeout. Within a pass
  `:ready` is never observable — every transition into it inserts the next
  page's fetch as an event, which gen_statem handles before any system
  message — so one `:sys.get_status/1` snapshot showing both is the proof,
  without a wall-clock wait.
  """

  alias TeslaMate.{Characterization, Log, Terrain}

  def repair_elevation do
    name = :"characterization_terrain_#{System.unique_integer([:positive])}"

    {:ok, terrain} =
      Terrain.start_link(
        name: name,
        deps_log: Log,
        deps_srtm: TerrainMock,
        deps_clock: Characterization.Clock
      )

    :ok = await_pass(terrain)
    :ok = GenStateMachine.stop(terrain)

    # Terrain installs its circuit breaker under its name on the first
    # lookup; the name is unique per pass, so the fuse goes with it.
    _ = :fuse.remove(name)

    :ok
  end

  defp await_pass(terrain) do
    case Characterization.status_snapshot(terrain) do
      {{:ready, _data}, {_count, [{:state_timeout, {:fetch_positions, 0}}]}} -> :ok
      _in_pass -> await_pass(terrain)
    end
  end
end
