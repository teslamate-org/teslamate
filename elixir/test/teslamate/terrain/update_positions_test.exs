defmodule TeslaMate.Terrain.UpdatePositionsTest do
  use TeslaMate.DataCase

  import Ecto.Query

  alias TeslaMate.{Log, Repo, Terrain}
  alias TeslaMate.Terrain.Repair
  alias TeslaMate.Log.{Drive, Position}

  # The production Log, except that storing a drive's elevations waits until
  # the test sends :store: holds the repair inside its database work.
  defmodule HoldingLog do
    alias TeslaMate.Log

    def get_terrain_elevation_drives(_test, opts), do: Log.get_terrain_elevation_drives(opts)
    def get_positions_without_elevation(_test, id), do: Log.get_positions_without_elevation(id)

    def add_terrain_elevation(test, id, elevations, status, opts) do
      send(test, {:storing, self()})

      receive do
        :store -> Log.add_terrain_elevation(id, elevations, status, opts)
      end
    end
  end

  # Starts Terrain and its repair, which runs a pass on start.
  defp start_terrain(name, responses) do
    :ok = start_terrain_only(name, responses)
    _repair = start_repair(name)
    :ok
  end

  defp start_terrain_only(name, responses) do
    srtm_name = :"srtm_#{name}"

    {:ok, _pid} = start_supervised({SRTMMock, name: srtm_name, pid: self(), responses: responses})

    {:ok, _} =
      start_supervised({Terrain, name: name, timeout: 100, deps_srtm: {SRTMMock, srtm_name}})

    :ok
  end

  defp start_repair(name, opts \\ []) do
    {:ok, repair} =
      start_supervised({Repair, [name: repair_name(name), deps_terrain: {Terrain, name}] ++ opts})

    repair
  end

  defp repair_name(name), do: :"repair_#{name}"

  # The repair handles no other message before its pass is over.
  defp await_pass(name) do
    _state = :sys.get_state(repair_name(name))
    :ok
  end

  defp queued?(%Drive{id: id}) do
    Repo.exists?(from queued in "terrain_elevation_queue", where: queued.drive_id == ^id)
  end

  test "return the elevation", %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)

    positions =
      %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      |> List.duplicate(201)
      |> List.replace_at(50, %{date: DateTime.utc_now(), latitude: 1, longitude: 1})
      |> List.replace_at(150, %{date: DateTime.utc_now(), latitude: 1, longitude: 1})
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(drive, position)
        pos
      end)

    :ok =
      start_terrain_only(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn ->
          Process.sleep(100)
          {:ok, 420}
        end
      })

    _repair = start_repair(name, deps_log: {HoldingLog, self()})

    # answered while the repair stores the drive's elevations
    assert_receive {:storing, repair}, 5_000

    assert Terrain.get_elevation(name, {0.0, 0.0}) == {:ok, 42}
    assert Terrain.get_elevation(name, {0.0, 0.0}) == {:ok, 42}
    assert Terrain.get_elevation(name, {0.0, 0.0}) == {:ok, 42}

    for _lookup <- 1..3, do: assert_receive({SRTM, {:get_elevation, +0.0, +0.0, _opts}})

    send(repair, :store)

    for {_, i} <- Enum.with_index(positions) do
      if i in [50, 150] do
        assert_receive {SRTM, {:get_elevation, 1.0, 1.0, _opts}}
      else
        assert_receive {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
      end
    end

    :ok = await_pass(name)

    for {position, i} <- Enum.with_index(positions) do
      if i in [50, 150] do
        assert %Position{elevation: 420} = TeslaMate.Repo.get(Position, position.id)
      else
        assert %Position{elevation: 42} = TeslaMate.Repo.get(Position, position.id)
      end
    end

    refute_receive _
  end

  @tag :capture_log
  test "handles errors during update!", %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)

    [p0, p1, p2, p3, p4, p5] =
      [
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0},
        %{date: DateTime.utc_now(), latitude: 1, longitude: 1},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 42, longitude: 42},
        %{date: DateTime.utc_now(), latitude: 0, longitude: 0}
      ]
      |> Enum.map(fn position ->
        {:ok, pos} = Log.insert_position(drive, position)
        pos
      end)

    ## Does not get elevation for non-drive positions

    {:ok, _pos} =
      Log.insert_position(car, %{date: DateTime.utc_now(), latitude: 69, longitude: 69})

    {:ok, _pos} =
      Log.insert_position(car, %{date: DateTime.utc_now(), latitude: 99, longitude: 99})

    :ok =
      start_terrain(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn -> {:error, :boom} end,
        {42.0, 42.0} => fn ->
          Process.sleep(100)
          {:error, :kaputt}
        end
      })

    assert_receive {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_receive {SRTM, {:get_elevation, 1.0, 1.0, _opts}}
    assert_receive {SRTM, {:get_elevation, 42.0, 42.0, _opts}}
    assert_receive {SRTM, {:get_elevation, 42.0, 42.0, _opts}}

    # 4th and 5th are :unavailable

    :ok = await_pass(name)

    assert %Position{elevation: 42} = TeslaMate.Repo.get(Position, p0.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p1.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p2.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p3.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p4.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p5.id)

    refute_receive _
  end

  test "adds the elevation to the polls of a stream gap and recomputes the closed drive",
       %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)

    start = DateTime.add(DateTime.utc_now(), -1, :hour)

    stream = %{latitude: 1, longitude: 1, elevation: 100}
    poll = %{latitude: 0, longitude: 0, ideal_battery_range_km: 300.0}

    [s0, p0, p1, p2, p3] =
      [stream, poll, poll, poll, poll]
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        attrs =
          Map.merge(attrs, %{
            date: DateTime.add(start, index * 15, :second),
            odometer: 100.0 + index
          })

        {:ok, pos} = Log.insert_position(drive, attrs)
        pos
      end)

    {:ok, %Drive{ascent: 0, descent: 0}} = Log.close_drive(drive)

    :ok = start_terrain(name, %{{0.0, 0.0} => fn -> {:ok, 42} end})
    :ok = await_pass(name)

    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}

    assert %Drive{ascent: 0, descent: 58} = TeslaMate.Repo.get(Drive, drive.id)

    assert %Position{elevation: 100} = TeslaMate.Repo.get(Position, s0.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p0.id)
    assert %Position{elevation: nil} = TeslaMate.Repo.get(Position, p1.id)
    assert %Position{elevation: 42} = TeslaMate.Repo.get(Position, p2.id)
    assert %Position{elevation: 42} = TeslaMate.Repo.get(Position, p3.id)

    refute_receive _
  end

  defp insert_poll(drive, coordinate, date) do
    {:ok, position} =
      Log.insert_position(drive, %{
        date: date,
        latitude: coordinate,
        longitude: coordinate,
        odometer: 100.0 + coordinate,
        ideal_battery_range_km: 300.0
      })

    position
  end

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(), -minutes, :minute)

  @tag :capture_log
  test "adds the elevation to a drive of any age once it is closed, also after a restart",
       %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)
    {:ok, drive} = Log.update_drive(drive, %{start_date: ~U[2024-01-01 00:00:00Z]})

    p0 = insert_poll(drive, 0, ~U[2024-01-01 00:00:00Z])
    p1 = insert_poll(drive, 1, ~U[2024-01-01 00:01:00Z])

    {:ok, %Drive{ascent: 0, descent: 0} = drive} = Log.close_drive(drive)
    assert queued?(drive)

    answering = :counters.new(1, [])

    answer = fn elevation ->
      fn -> if :counters.get(answering, 1) == 0, do: {:error, :kaputt}, else: {:ok, elevation} end
    end

    :ok = start_terrain(name, %{{0.0, 0.0} => answer.(42), {1.0, 1.0} => answer.(100)})
    :ok = await_pass(name)

    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_received {SRTM, {:get_elevation, 1.0, 1.0, _opts}}

    assert %Drive{ascent: 0, descent: 0} = Repo.get(Drive, drive.id)
    assert %Position{elevation: nil} = Repo.get(Position, p0.id)
    assert queued?(drive)

    # A restart finds the drive still waiting.
    :ok = stop_supervised(Repair)
    :ok = :counters.add(answering, 1, 1)
    _repair = start_repair(name)
    :ok = await_pass(name)

    assert_received {SRTM, {:get_elevation, +0.0, +0.0, _opts}}
    assert_received {SRTM, {:get_elevation, 1.0, 1.0, _opts}}

    assert %Drive{ascent: 58, descent: 0} = Repo.get(Drive, drive.id)
    assert %Position{elevation: 42} = Repo.get(Position, p0.id)
    assert %Position{elevation: 100} = Repo.get(Position, p1.id)
    refute queued?(drive)

    refute_receive _
  end

  test "keeps the ascent and descent of each closed drive matching its elevations when the repair stops",
       %{test: name} do
    car = car_fixture()

    # Closed before drives were queued for Terrain: only its date selects it.
    {:ok, drive} = Log.start_drive(car)
    _p0 = insert_poll(drive, 0, minutes_ago(60))
    _p1 = insert_poll(drive, 1, minutes_ago(59))
    {:ok, drive} = Log.close_drive(drive)
    Repo.delete_all(from queued in "terrain_elevation_queue", where: queued.drive_id == ^drive.id)

    {:ok, stopping_drive} = Log.start_drive(car)
    _q0 = insert_poll(stopping_drive, 2, minutes_ago(58))
    _q1 = insert_poll(stopping_drive, 3, minutes_ago(57))
    {:ok, stopping_drive} = Log.close_drive(stopping_drive)

    test = self()
    stopped = :counters.new(1, [])

    :ok =
      start_terrain_only(name, %{
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn -> {:ok, 100} end,
        {2.0, 2.0} => fn ->
          if :counters.get(stopped, 1) == 0 do
            send(test, :looking_up)

            receive do
              :answer -> {:ok, 7}
            end
          else
            {:ok, 7}
          end
        end,
        {3.0, 3.0} => fn -> {:ok, 9} end
      })

    {:ok, repair} =
      start_supervised(
        Supervisor.child_spec(
          {Repair, name: repair_name(name), deps_terrain: {Terrain, name}},
          restart: :temporary
        )
      )

    # The repair stops while it looks up the elevation of the second drive.
    assert_receive :looking_up, 5_000
    stopping = Process.monitor(repair)
    Process.exit(repair, :kill)
    assert_receive {:DOWN, ^stopping, :process, ^repair, :killed}
    :ok = :counters.add(stopped, 1, 1)

    assert %Drive{ascent: 58, descent: 0} = Repo.get(Drive, drive.id)
    assert %Drive{ascent: 0, descent: 0} = Repo.get(Drive, stopping_drive.id)
    assert queued?(stopping_drive)

    # Restarted, the repair completes the second drive.
    send(Process.whereis(:"srtm_#{name}"), :answer)

    {:ok, _restarted} =
      start_supervised(
        Supervisor.child_spec({Repair, name: repair_name(name), deps_terrain: {Terrain, name}},
          id: :restarted_repair
        )
      )

    :ok = await_pass(name)

    assert %Drive{ascent: 58, descent: 0} = Repo.get(Drive, drive.id)
    refute queued?(stopping_drive)

    assert %Drive{ascent: 2, descent: 0} = Repo.get(Drive, stopping_drive.id)

    assert [7, 9] ==
             Repo.all(
               from position in Position,
                 where: position.drive_id == ^stopping_drive.id,
                 order_by: position.id,
                 select: position.elevation
             )
  end

  test "keeps a drive closed while it was looked up queued until the next pass",
       %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)
    _p0 = insert_poll(drive, 0, minutes_ago(60))
    _p1 = insert_poll(drive, 1, minutes_ago(59))

    test = self()

    :ok =
      start_terrain_only(name, %{
        {0.0, 0.0} => fn ->
          send(test, :looking_up)

          receive do
            :answer -> {:ok, 42}
          end
        end,
        {1.0, 1.0} => fn -> {:ok, 100} end,
        {2.0, 2.0} => fn -> {:ok, 120} end
      })

    repair = start_repair(name)

    # The drive is open when listed; it takes a position and is closed while
    # the repair looks up the positions it read.
    assert_receive :looking_up, 5_000
    p2 = insert_poll(drive, 2, minutes_ago(58))
    {:ok, drive} = Log.close_drive(drive)
    assert queued?(drive)
    send(Process.whereis(:"srtm_#{name}"), :answer)
    :ok = await_pass(name)

    assert %Drive{ascent: 58} = Repo.get(Drive, drive.id)
    assert %Position{elevation: nil} = Repo.get(Position, p2.id)
    assert queued?(drive)

    send(repair, :repair)
    :ok = await_pass(name)

    assert %Drive{ascent: 78} = Repo.get(Drive, drive.id)
    assert %Position{elevation: 120} = Repo.get(Position, p2.id)
    refute queued?(drive)
  end

  @tag :capture_log
  test "does not let a drive whose lookups keep failing hold back later drives, across a restart",
       %{test: name} do
    car = car_fixture()

    {:ok, failing_drive} = Log.start_drive(car)

    for coordinate <- [5, 6, 7],
        do: insert_poll(failing_drive, coordinate, minutes_ago(60 - coordinate))

    {:ok, failing_drive} = Log.close_drive(failing_drive)

    {:ok, drive} = Log.start_drive(car)
    p0 = insert_poll(drive, 0, minutes_ago(30))
    p1 = insert_poll(drive, 1, minutes_ago(29))
    {:ok, drive} = Log.close_drive(drive)

    failing = fn -> {:error, :kaputt} end

    :ok =
      start_terrain(name, %{
        {5.0, 5.0} => failing,
        {6.0, 6.0} => failing,
        {7.0, 7.0} => failing,
        {0.0, 0.0} => fn -> {:ok, 42} end,
        {1.0, 1.0} => fn -> {:ok, 100} end
      })

    :ok = await_pass(name)

    # Three failed lookups blew the circuit breaker: the pass ended before
    # the second drive.
    assert %Position{elevation: nil} = Repo.get(Position, p0.id)
    assert queued?(drive)

    # The circuit breaker resets after a while; a restart begins a new pass.
    :ok = stop_supervised(Repair)
    :ok = :fuse.reset(name)
    _repair = start_repair(name)
    :ok = await_pass(name)

    assert %Drive{ascent: 58} = Repo.get(Drive, drive.id)
    assert %Position{elevation: 42} = Repo.get(Position, p0.id)
    assert %Position{elevation: 100} = Repo.get(Position, p1.id)
    refute queued?(drive)
    assert queued?(failing_drive)
  end

  defmodule ReplayClock do
    def utc_now, do: ~U[2024-05-01 12:00:00.000000Z]
  end

  @tag :capture_log
  test "marks a drive whose lookups failed as tried at the time of the repair's clock",
       %{test: name} do
    car = car_fixture()

    {:ok, drive} = Log.start_drive(car)
    _p0 = insert_poll(drive, 5, ~U[2024-04-01 00:00:00Z])
    _p1 = insert_poll(drive, 6, ~U[2024-04-01 00:01:00Z])
    {:ok, drive} = Log.close_drive(drive)

    failing = fn -> {:error, :kaputt} end
    :ok = start_terrain_only(name, %{{5.0, 5.0} => failing, {6.0, 6.0} => failing})
    _repair = start_repair(name, deps_clock: ReplayClock)
    :ok = await_pass(name)

    assert [~U[2024-05-01 12:00:00.000000Z]] ==
             Repo.all(
               from queued in "terrain_elevation_queue",
                 where: queued.drive_id == ^drive.id,
                 select: type(queued.attempted_at, :utc_datetime_usec)
             )
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end
end
