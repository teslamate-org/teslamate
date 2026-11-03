defmodule TeslaMate.LogPositionTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log
  alias TeslaMate.Log.{Drive, Position}

  def car_fixture(attrs \\ %{}) do
    id = System.unique_integer([:positive, :monotonic])

    {:ok, car} =
      attrs
      |> Enum.into(%{
        efficiency: 0.153,
        eid: id,
        model: "M3",
        vid: id,
        vin: "test-#{id}"
      })
      |> Log.create_car()

    car
  end

  describe "get_latest_position/1" do
    test "returns the latest complete position for a car" do
      car = car_fixture()
      other_car = car_fixture()

      {:ok, complete_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:00:00Z],
          latitude: 1.0,
          longitude: 1.0,
          ideal_battery_range_km: 300.0
        })

      {:ok, _incomplete_streaming_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:05:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      {:ok, _other_car_position} =
        Log.insert_position(other_car, %{
          date: ~U[2026-01-01 10:10:00Z],
          latitude: 3.0,
          longitude: 3.0,
          ideal_battery_range_km: 200.0
        })

      assert %{id: id} = Log.get_latest_position(car)
      assert id == complete_position.id
    end

    test "returns nil when a car only has incomplete streaming positions" do
      car = car_fixture()

      {:ok, _incomplete_streaming_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:05:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      assert Log.get_latest_position(car) == nil
    end
  end

  # Stored the way Vehicle stores them: a stream position has an odometer but
  # no ideal range, a poll has both.
  defp insert_positions(car_or_drive, kinds) do
    start = DateTime.add(DateTime.utc_now(), -1, :hour)

    for {kind, index} <- Enum.with_index(kinds) do
      {:ok, position} =
        Log.insert_position(car_or_drive, position_attrs(kind, DateTime.add(start, index * 15)))

      position
    end
  end

  defp position_attrs(kind, date) do
    attrs =
      case kind do
        :stream -> %{elevation: 100}
        :stream_without_elevation -> %{}
        :poll -> %{ideal_battery_range_km: 300.0}
        :poll_with_elevation -> %{ideal_battery_range_km: 300.0, elevation: 100}
      end

    Map.merge(attrs, %{
      date: date,
      latitude: 1.0,
      longitude: 1.0,
      odometer: 100.0
    })
  end

  # The third poll after a stream position, stored after the next stream
  # position but dated before it: in a stream gap by date, not in the order
  # stored.
  defp stream_gap_stored_late(drive) do
    [_s0, _p0, p1, _s1] = insert_positions(drive, [:stream, :poll, :poll, :stream])
    {:ok, p2} = Log.insert_position(drive, position_attrs(:poll, DateTime.add(p1.date, 10)))
    p2
  end

  defp drive_fixture do
    {:ok, drive} = Log.start_drive(car_fixture())
    drive
  end

  defp closed_drive_fixture do
    {:ok, drive} = Log.update_drive(drive_fixture(), %{end_date: DateTime.utc_now()})
    drive
  end

  describe "get_terrain_elevation_drives/1" do
    test "selects the drives that started in the 10 days before the given time, closed ones first" do
      [open, closed] =
        for end_date <- [nil, ~U[2024-01-01 00:10:00Z]] do
          {:ok, drive} =
            Log.update_drive(drive_fixture(), %{
              start_date: ~U[2024-01-01 00:00:00Z],
              end_date: end_date
            })

          drive
        end

      assert [
               %{id: closed_id, end_date: %DateTime{}, queued: false},
               %{id: open_id, end_date: nil, queued: false}
             ] = Log.get_terrain_elevation_drives(now: ~U[2024-01-10 00:00:00Z])

      assert {open_id, closed_id} == {open.id, closed.id}

      assert Log.get_terrain_elevation_drives(now: ~U[2024-01-12 00:00:00Z]) == []
      assert Log.get_terrain_elevation_drives() == []
    end

    test "selects a drive of any age queued for the terrain elevation when it was closed" do
      {:ok, drive} = Log.update_drive(drive_fixture(), %{start_date: ~U[2020-01-01 00:00:00Z]})

      for minute <- [0, 1] do
        {:ok, _position} =
          Log.insert_position(
            drive,
            position_attrs(:poll, DateTime.add(~U[2020-01-01 00:00:00Z], minute, :minute))
            |> Map.put(:odometer, 100.0 + minute)
          )
      end

      assert {:ok, %Drive{end_date: ~U[2020-01-01 00:01:00.000000Z]}} = Log.close_drive(drive)

      assert [%{id: id, end_date: %DateTime{}, queued: true}] = Log.get_terrain_elevation_drives()
      assert id == drive.id
    end

    test "takes the drives whose lookups failed last, the one tried longest ago first" do
      [first, second] =
        for _drive <- 1..2 do
          {:ok, drive} = Log.start_drive(car_fixture())

          for minute <- [0, 1] do
            attrs = position_attrs(:poll, DateTime.add(DateTime.utc_now(), minute - 60, :minute))
            {:ok, _position} = Log.insert_position(drive, %{attrs | odometer: 100.0 + minute})
          end

          {:ok, drive} = Log.close_drive(drive)
          drive.id
        end

      listed = fn -> Enum.map(Log.get_terrain_elevation_drives(), & &1.id) end

      assert listed.() == [first, second]

      assert :ok = Log.add_terrain_elevation(first, %{}, :failed)
      assert listed.() == [second, first]

      assert :ok = Log.add_terrain_elevation(second, %{}, :failed)
      assert listed.() == [first, second]

      # Lookups that only ended keep a drive's place.
      assert :ok = Log.add_terrain_elevation(first, %{}, :incomplete)
      assert listed.() == [first, second]
    end
  end

  describe "get_positions_without_elevation/1" do
    defp selected(drive) do
      drive.id |> Log.get_positions_without_elevation() |> Enum.map(& &1.id)
    end

    test "selects every position without elevation of a drive without stream positions" do
      drive = closed_drive_fixture()

      [p0, p1, _p2, p3] = insert_positions(drive, [:poll, :poll, :poll_with_elevation, :poll])

      assert [%Position{latitude: _, longitude: _} | _] =
               Log.get_positions_without_elevation(drive.id)

      assert selected(drive) == [p0.id, p1.id, p3.id]
    end

    test "selects the polls of a stream gap from the third poll after the last stream position" do
      drive = closed_drive_fixture()

      [_s0, _s1, _p0, _p1, p2, p3, _s2, _p4, _s3] =
        insert_positions(drive, [
          :stream,
          :stream,
          :poll,
          :poll,
          :poll,
          :poll,
          :stream_without_elevation,
          :poll,
          :stream_without_elevation
        ])

      assert selected(drive) == [p2.id, p3.id]
    end

    test "does not select a single poll between stream positions" do
      drive = closed_drive_fixture()

      _positions = insert_positions(drive, [:stream, :poll, :stream, :poll, :stream])

      assert Log.get_positions_without_elevation(drive.id) == []
    end

    test "counts the polls of a stream gap at the start of a drive from the drive start" do
      drive = closed_drive_fixture()

      [_p0, _p1, p2, _s0, _p3] = insert_positions(drive, [:poll, :poll, :poll, :stream, :poll])

      assert selected(drive) == [p2.id]
    end

    test "counts the polls of a closed drive by their date, not in the order they were stored" do
      drive = closed_drive_fixture()

      [_s0, p0, _p1, _p2, p3] = insert_positions(drive, [:stream, :poll, :poll, :poll, :poll])

      # In the order stored, p2 and p3 lie in a stream gap; a stream position
      # stored late, dated between p0 and p1, shows that only p3 does.
      {:ok, _late} = Log.insert_position(drive, position_attrs(:stream, DateTime.add(p0.date, 5)))

      assert selected(drive) == [p3.id]
    end

    test "counts a poll of a closed drive stored late by its date" do
      drive = closed_drive_fixture()

      p2 = stream_gap_stored_late(drive)

      assert selected(drive) == [p2.id]
    end

    test "selects of an open drive with stream positions only polls in a stream gap in both orders" do
      drive = drive_fixture()

      _p2 = stream_gap_stored_late(drive)
      assert selected(drive) == []

      # A stream position stored late, dated between p0 and p1: by date only
      # p3 lies in a stream gap, in the order stored p2 and p3.
      {:ok, other_drive} = Log.start_drive(car_fixture())

      [_s0, p0, _p1, _p2, p3] =
        insert_positions(other_drive, [:stream, :poll, :poll, :poll, :poll])

      {:ok, _late} =
        Log.insert_position(other_drive, position_attrs(:stream, DateTime.add(p0.date, 5)))

      assert selected(other_drive) == [p3.id]
    end

    test "selects the positions of an open drive too" do
      drive = drive_fixture()

      [p0, p1] = insert_positions(drive, [:poll, :poll])

      assert selected(drive) == [p0.id, p1.id]
    end

    test "selects neither the positions of another drive nor those outside of a drive" do
      car = car_fixture()
      {:ok, drive} = Log.start_drive(car)
      {:ok, other_drive} = Log.start_drive(car)

      [p0] = insert_positions(drive, [:poll])
      _positions = insert_positions(other_drive, [:poll])
      _positions = insert_positions(car, [:poll, :poll, :poll])

      assert selected(drive) == [p0.id]
    end
  end

  describe "get_last_inserted_position/0" do
    test "returns the most recently inserted position across all cars, including incomplete ones" do
      car = car_fixture()
      other_car = car_fixture()

      {:ok, _latest_by_date_position} =
        Log.insert_position(car, %{
          date: ~U[2026-01-01 10:00:00Z],
          latitude: 1.0,
          longitude: 1.0,
          ideal_battery_range_km: 300.0
        })

      {:ok, latest_position} =
        Log.insert_position(other_car, %{
          date: ~U[2026-01-01 09:55:00Z],
          latitude: 2.0,
          longitude: 2.0
        })

      assert %{id: id} = Log.get_last_inserted_position()
      assert id == latest_position.id
    end
  end
end
