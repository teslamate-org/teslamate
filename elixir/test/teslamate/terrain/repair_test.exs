defmodule TeslaMate.Terrain.RepairTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Terrain
  alias TeslaMate.Terrain.Repair
  alias TeslaMate.Log.Position

  # The repair's clock: one reading per pass, handed to every store.
  @now ~U[2024-05-01 12:00:00.000000Z]

  defmodule FixedClock do
    def utc_now, do: ~U[2024-05-01 12:00:00.000000Z]
  end

  # A Log whose first call of a pass waits until the test sends :release.
  defmodule BlockingLog do
    def get_terrain_elevation_drives(test, _opts) do
      send(test, {:blocked, self()})

      receive do
        :release -> []
      end
    end
  end

  defp start_terrain(name, responses) do
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    {:ok, _pid} =
      start_supervised({Terrain, name: name, timeout: 100, deps_srtm: {SRTMMock, srtm_name}})

    :ok
  end

  defp start_repair(name, deps_log) do
    {:ok, pid} =
      start_supervised(
        {Repair,
         name: :"repair_#{name}",
         deps_log: deps_log,
         deps_terrain: {Terrain, name},
         deps_clock: FixedClock}
      )

    pid
  end

  defp start_repair_with_drives(name, terrain_elevation_drives) do
    name
    |> start_repair_on_drives(terrain_elevation_drives)
    |> pass_messages()
  end

  defp start_repair_on_drives(name, terrain_elevation_drives) do
    log_name = :"log_#{name}"

    {:ok, _pid} =
      start_supervised(
        {LogMock,
         name: log_name,
         pid: self(),
         last_update: nil,
         terrain_elevation_drives: terrain_elevation_drives}
      )

    start_repair(name, {LogMock, log_name})
  end

  # The pass runs on start, before the repair handles any other message.
  defp pass_messages(repair) do
    _state = :sys.get_state(repair)

    {:messages, messages} = Process.info(self(), :messages)
    Enum.reject(messages, &match?({SRTM, _}, &1))
  end

  defp closed(id), do: %{id: id, end_date: ~U[2024-01-01 00:10:00Z], queued: true}
  defp open(id), do: %{id: id, end_date: nil, queued: false}

  defp position(id, drive_id, {lat, lng}) do
    %Position{id: id, drive_id: drive_id, latitude: Decimal.new(lat), longitude: Decimal.new(lng)}
  end

  @tag :capture_log
  test "stores the elevations of each drive at once, after looking them up", %{test: name} do
    :ok =
      start_terrain(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn -> {:ok, nil} end,
        {2.0, 2.0} => fn -> {:error, :kaputt} end
      })

    messages =
      start_repair_with_drives(name, [
        {closed(10), [position(1, 10, {0, 0}), position(3, 10, {0, 0})]},
        {closed(20), [position(2, 20, {1, 1})]},
        {closed(30), [position(4, 30, {2, 2}), position(5, 30, {0, 0})]},
        {closed(40), []}
      ])

    assert messages == [
             :get_terrain_elevation_drives,
             {:get_positions_without_elevation, 10},
             {:add_terrain_elevation, 10, %{1 => 42, 3 => 42}, :complete, [now: @now]},
             {:get_positions_without_elevation, 20},
             {:add_terrain_elevation, 20, %{}, :complete, [now: @now]},
             {:get_positions_without_elevation, 30},
             {:add_terrain_elevation, 30, %{5 => 42}, :failed, [now: @now]},
             {:get_positions_without_elevation, 40},
             {:add_terrain_elevation, 40, %{}, :complete, [now: @now]}
           ]

    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_received {SRTM, {:get_elevation, 1.0, 1.0, _opts}}
    assert_received {SRTM, {:get_elevation, 2.0, 2.0, _opts}}
    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
  end

  test "waits for a lookup that takes longer than Terrain's timeout", %{test: name} do
    gated =
      fn ->
        receive do
          :answer -> {:ok, 42}
        end
      end

    :ok = start_terrain(name, %{{0.0, 0.0} => gated})

    repair = start_repair_on_drives(name, [{closed(10), [position(1, 10, {0, 0})]}])
    assert_receive {SRTM, {:get_elevation, +0.0, +0.0, _opts}}, 5_000

    # Past its timeout, Terrain waits for the lookup.
    assert Terrain.get_elevation(name, {9.0, 9.0}) == {:error, :unavailable}

    send(Process.whereis(:"srtm_#{name}"), :answer)
    messages = pass_messages(repair)

    assert {:add_terrain_elevation, 10, %{1 => 42}, :complete, [now: @now]} in messages
  end

  test "ends the wait only of a drive that was closed when listed", %{test: name} do
    :ok = start_terrain(name, %{{0.0, 0.0} => fn -> {:ok, 42} end})

    messages = start_repair_with_drives(name, [{open(10), [position(1, 10, {0, 0})]}])

    assert {:add_terrain_elevation, 10, %{1 => 42}, :incomplete, [now: @now]} in messages
  end

  @tag :capture_log
  test "ends the pass once Terrain is unavailable, leaving the other drives waiting",
       %{test: name} do
    :ok = start_terrain(name, %{{2.0, 2.0} => fn -> {:error, :kaputt} end})

    drives =
      for id <- 1..6 do
        {closed(id * 10), [position(id, id * 10, {2, 2}), position(id + 100, id * 10, {2, 2})]}
      end

    messages = start_repair_with_drives(name, drives)

    # Three failed lookups blow Terrain's circuit breaker; the fourth finds it
    # blown and ends the pass in the second drive.
    assert messages == [
             :get_terrain_elevation_drives,
             {:get_positions_without_elevation, 10},
             {:add_terrain_elevation, 10, %{}, :failed, [now: @now]},
             {:get_positions_without_elevation, 20},
             {:add_terrain_elevation, 20, %{}, :failed, [now: @now]}
           ]

    for _lookup <- 1..3, do: assert_received({SRTM, {:get_elevation, 2.0, 2.0, _opts}})
    refute_received {SRTM, _}
  end

  test "leaves Terrain answering lookups while it works on the database", %{test: name} do
    :ok = start_terrain(name, %{{0.0, 0.0} => fn -> {:ok, 42} end})

    _repair = start_repair(name, {BlockingLog, self()})
    assert_receive {:blocked, repair}, 5_000

    assert Terrain.get_elevation(name, {0.0, 0.0}) == {:ok, 42}

    send(repair, :release)
  end

  test "takes no transaction for a drive with nothing to store and no queue entry", %{test: name} do
    :ok = start_terrain(name, %{})

    messages =
      start_repair_with_drives(name, [
        {%{closed(10) | queued: false}, []},
        {open(20), []},
        {closed(30), []}
      ])

    assert messages == [
             :get_terrain_elevation_drives,
             {:get_positions_without_elevation, 10},
             {:get_positions_without_elevation, 20},
             {:get_positions_without_elevation, 30},
             {:add_terrain_elevation, 30, %{}, :complete, [now: @now]}
           ]
  end

  test "queues a closed drive whose lookups failed, though it was not queued", %{test: name} do
    :ok = start_terrain(name, %{{2.0, 2.0} => fn -> {:error, :kaputt} end})

    messages =
      start_repair_with_drives(name, [{%{closed(10) | queued: false}, [position(1, 10, {2, 2})]}])

    assert {:add_terrain_elevation, 10, %{}, :failed, [now: @now]} in messages
  end

  test "ends the pass without crashing when Terrain is not running", %{test: name} do
    messages =
      start_repair_with_drives(name, [
        {closed(10), [position(1, 10, {0, 0})]},
        {closed(20), [position(2, 20, {0, 0})]}
      ])

    assert messages == [
             :get_terrain_elevation_drives,
             {:get_positions_without_elevation, 10},
             {:add_terrain_elevation, 10, %{}, :incomplete, [now: @now]}
           ]

    assert Process.alive?(Process.whereis(:"repair_#{name}"))
  end
end
