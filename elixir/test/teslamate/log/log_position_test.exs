defmodule TeslaMate.LogPositionTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log
  alias TeslaMate.Log.Position

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

  describe "get_positions_without_elevation/2" do
    # Stored the way Vehicle stores them: a stream position has an odometer but
    # no ideal range, a poll has both.
    defp insert_positions(car_or_drive, kinds) do
      start = DateTime.add(DateTime.utc_now(), -1, :hour)

      for {kind, index} <- Enum.with_index(kinds) do
        attrs =
          case kind do
            :stream -> %{elevation: 100}
            :stream_without_elevation -> %{}
            :poll -> %{ideal_battery_range_km: 300.0}
            :poll_with_elevation -> %{ideal_battery_range_km: 300.0, elevation: 100}
          end

        {:ok, position} =
          Log.insert_position(
            car_or_drive,
            Map.merge(attrs, %{
              date: DateTime.add(start, index * 15, :second),
              latitude: 1.0,
              longitude: 1.0,
              odometer: 100.0 + index
            })
          )

        position
      end
    end

    defp closed_drive_fixture do
      {:ok, drive} = Log.start_drive(car_fixture())
      {:ok, drive} = Log.update_drive(drive, %{end_date: DateTime.utc_now()})
      drive
    end

    defp selected(min_id \\ 0, opts \\ []) do
      {positions, _next} = Log.get_positions_without_elevation(min_id, opts)
      Enum.map(positions, & &1.id)
    end

    test "selects every position without elevation of a drive without stream positions" do
      drive = closed_drive_fixture()

      [p0, p1, _p2, p3] = insert_positions(drive, [:poll, :poll, :poll_with_elevation, :poll])

      assert {[_ | _], next} = Log.get_positions_without_elevation(0, limit: 100)
      assert next == p3.id
      assert selected() == [p0.id, p1.id, p3.id]
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

      assert selected() == [p2.id, p3.id]
    end

    test "does not select a single poll between stream positions" do
      drive = closed_drive_fixture()

      _positions = insert_positions(drive, [:stream, :poll, :stream, :poll, :stream])

      assert Log.get_positions_without_elevation(0, limit: 100) == {[], nil}
    end

    test "counts the polls of a stream gap at the start of a drive from the drive start" do
      drive = closed_drive_fixture()

      [_p0, _p1, p2, _s0, _p3] = insert_positions(drive, [:poll, :poll, :poll, :stream, :poll])

      assert selected() == [p2.id]
    end

    test "counts the polls in the order they were stored, not by their date" do
      drive = closed_drive_fixture()

      [stream_position, _p0, _p1] = insert_positions(drive, [:stream, :poll, :poll])

      {:ok, older_poll} =
        Log.insert_position(drive, %{
          date: DateTime.add(stream_position.date, -1, :minute),
          latitude: 1.0,
          longitude: 1.0,
          odometer: 99.0,
          ideal_battery_range_km: 300.0
        })

      assert selected() == [older_poll.id]
    end

    test "selects the same polls if a page begins within a drive" do
      drive = closed_drive_fixture()

      [_s0, p0, _p1, p2, p3, p4] =
        insert_positions(drive, [:stream, :poll, :poll, :poll, :poll, :poll])

      assert {[%Position{id: id}], next} = Log.get_positions_without_elevation(0, limit: 1)
      assert id == p2.id
      assert next == p2.id

      assert selected(p0.id, limit: 100) == [p2.id, p3.id, p4.id]
      assert selected(p2.id, limit: 100) == [p3.id, p4.id]
      assert selected(p4.id, limit: 100) == []
    end

    test "does not select the positions of an open drive" do
      {:ok, drive} = Log.start_drive(car_fixture())

      _positions = insert_positions(drive, [:poll, :poll, :stream, :poll, :poll, :poll])

      assert Log.get_positions_without_elevation(0, limit: 100) == {[], nil}
    end

    test "does not select positions outside of a drive" do
      car = car_fixture()

      _positions = insert_positions(car, [:poll, :poll, :poll])

      assert Log.get_positions_without_elevation(0, limit: 100) == {[], nil}
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
