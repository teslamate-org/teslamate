defmodule TeslaMate.LogDriveTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, Position, Drive}
  alias TeslaMate.Locations.Address
  alias TeslaMate.{Log, Locations}

  @valid_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end

  test "start_drive/1 returns the drive" do
    %Car{id: id} = car = car_fixture()

    assert {:ok, %Drive{car_id: ^id}} = Log.start_drive(car)
  end

  describe "insert_position/1" do
    test "with valid data creates a position" do
      car = car_fixture()

      assert {:ok, %Position{} = position} = Log.insert_position(car, @valid_attrs)
      assert %DateTime{} = position.date
      assert position.car_id == car.id
      assert position.longitude == Decimal.new("0.000000")
      assert position.latitude == Decimal.new("0.000000")
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.insert_position(%Drive{}, %{latitude: nil, longitude: nil})

      assert errors_on(changeset) == %{
               car_id: ["can't be blank"],
               date: ["can't be blank"],
               latitude: ["can't be blank"],
               longitude: ["can't be blank"]
             }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.insert_position(%Car{}, %{latitude: nil, longitude: nil})

      assert errors_on(changeset) == %{
               car_id: ["can't be blank"],
               date: ["can't be blank"],
               latitude: ["can't be blank"],
               longitude: ["can't be blank"]
             }
    end
  end

  describe "close_drive/1" do
    test "aggregates drive data" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          speed: 23,
          power: 15,
          odometer: 284.85156,
          ideal_battery_range_km: 338.8,
          rated_battery_range_km: 308.8,
          battery_level: 68,
          outside_temp: 19.2,
          inside_temp: 21.0
        },
        %{
          date: "2019-04-06 10:20:08",
          latitude: 50.112214,
          longitude: 11.598471,
          speed: 42,
          power: -4,
          odometer: 285.90556,
          ideal_battery_range_km: 337.8,
          rated_battery_range_km: 307.8,
          battery_level: 68,
          outside_temp: 19.0,
          inside_temp: 21.1
        },
        %{
          date: "2019-04-06 10:21:14",
          latitude: 50.112167,
          longitude: 11.599395,
          speed: 34,
          power: -7,
          odometer: 286.969561,
          ideal_battery_range_km: 336.8,
          rated_battery_range_km: 306.8,
          battery_level: 68,
          outside_temp: 21.0,
          inside_temp: 21.2
        },
        %{
          date: "2019-04-06 10:22:20",
          latitude: 50.112118,
          longitude: 11.599919,
          speed: 21,
          power: 1,
          odometer: 287.00556,
          ideal_battery_range_km: 335.8,
          rated_battery_range_km: 305.8,
          battery_level: 68,
          outside_temp: 18,
          inside_temp: 20.9
        },
        %{
          date: "2019-04-06 10:23:25",
          latitude: 50.11196,
          longitude: 11.600445,
          speed: 39,
          power: 36,
          odometer: 288.045561,
          ideal_battery_range_km: 334.8,
          rated_battery_range_km: 304.8,
          battery_level: 68,
          outside_temp: 18.0,
          inside_temp: 21.0
        }
      ]

      assert {:ok, drive} = Log.start_drive(car)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(drive, p)
      end

      assert {:ok, drive} = Log.close_drive(drive)

      assert {:ok, drive.end_date, 0} == DateTime.from_iso8601("2019-04-06 10:23:25.000000Z")
      assert drive.outside_temp_avg == Decimal.from_float(19.0)
      assert drive.inside_temp_avg == Decimal.from_float(21.0)
      assert drive.speed_max == 42
      assert drive.power_max == 36.0
      assert drive.power_min == -7.0
      assert drive.start_km == 284.85156
      assert drive.end_km == 288.045561
      assert drive.distance == 3.1940010000000143
      assert drive.start_ideal_range_km == Decimal.new("338.80")
      assert drive.end_ideal_range_km == Decimal.new("334.80")
      assert drive.start_rated_range_km == Decimal.new("308.80")
      assert drive.end_rated_range_km == Decimal.new("304.80")
      assert drive.duration_min == 4
    end

    test "queues the drive for the terrain elevation its positions lack" do
      car = car_fixture()

      assert {:ok, drive} = Log.start_drive(car)
      assert {:ok, _} = Log.insert_position(drive, poll_attrs(0, nil))
      assert {:ok, _} = Log.insert_position(drive, poll_attrs(1, 100))

      assert {:ok, drive} = Log.close_drive(drive)
      assert queued?(drive)
    end

    test "does not queue a drive whose positions lack no terrain elevation they take" do
      car = car_fixture()

      assert {:ok, polled} = Log.start_drive(car)
      _positions = insert_positions(polled, [poll_attrs(0, 100), poll_attrs(1, 150)])

      # A single poll between stream positions takes none.
      assert {:ok, streamed} = Log.start_drive(car)

      _positions =
        insert_positions(streamed, [
          stream_attrs(0, 100),
          poll_attrs(1, nil),
          stream_attrs(2, 110)
        ])

      for drive <- [polled, streamed] do
        assert {:ok, drive} = Log.close_drive(drive)
        refute queued?(drive)
      end
    end

    test "hands back the start and end position without looking up addresses" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          odometer: 284.8,
          ideal_battery_range_km: 300
        },
        %{
          date: "2019-04-06 10:20:08",
          latitude: 50.112214,
          longitude: 11.598471,
          odometer: 285.9,
          ideal_battery_range_km: 300
        },
        %{
          date: "2019-04-06 10:21:14",
          latitude: 50.112167,
          longitude: 11.599395,
          odometer: 286.9,
          ideal_battery_range_km: 300
        }
      ]

      assert {:ok, drive} = Log.start_drive(car)

      ids =
        for p <- positions do
          assert {:ok, %Position{id: id}} = Log.insert_position(drive, p)
          id
        end

      assert {:ok, drive} = Log.close_drive(drive)

      assert %Position{id: start_id, latitude: start_lat} = drive.start_position
      assert %Position{id: end_id, latitude: end_lat} = drive.end_position
      assert [^start_id, _, ^end_id] = ids
      assert {drive.start_position_id, drive.end_position_id} == {start_id, end_id}
      assert {start_lat, end_lat} == {Decimal.new("50.112198"), Decimal.new("50.112167")}

      assert {drive.start_address_id, drive.end_address_id} == {nil, nil}
      assert [] == Repo.all(Address)
    end

    test "deletes a drive and if it has no positions" do
      car = car_fixture()

      assert {:ok, %Drive{} = drive} = Log.start_drive(car)
      assert {:ok, %Drive{id: id, distance: +0.0, duration_min: 0}} = Log.close_drive(drive)
      assert nil == Repo.get(Drive, id)
    end

    test "deletes a drive and its position if it has only one position" do
      car = car_fixture()

      positions = [
        %{date: "2019-04-06 10:00:00", latitude: +0.0, longitude: +0.0, odometer: 100}
      ]

      assert {:ok, drive} = Log.start_drive(car)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(drive, p)
      end

      assert {:ok, %Drive{id: id, distance: +0.0, duration_min: 0}} = Log.close_drive(drive)
      assert nil == Repo.get(Drive, id)
    end

    test "deletes a drive and its position if the distance driven is 0" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:00:00",
          latitude: +0.0,
          longitude: +0.0,
          odometer: 100,
          ideal_battery_range_km: 300
        },
        %{
          date: "2019-04-06 10:05:00",
          latitude: +0.0,
          longitude: +0.0,
          odometer: 100,
          ideal_battery_range_km: 300
        }
      ]

      assert {:ok, drive} = Log.start_drive(car)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(drive, p)
      end

      assert {:ok, %Drive{id: id, distance: +0.0}} = Log.close_drive(drive)
      assert nil == Repo.get(Drive, id)
    end
  end

  describe "update_drive/2" do
    test "sets the addresses" do
      car = car_fixture()

      assert {:ok, drive} = Log.start_drive(car)

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 52.514521,
          longitude: 13.350144,
          odometer: 284.8,
          ideal_battery_range_km: 300
        },
        %{
          date: "2019-04-06 10:20:08",
          latitude: 52.394246,
          longitude: 13.542552,
          odometer: 285.9,
          ideal_battery_range_km: 300
        }
      ]

      for p <- positions, do: {:ok, _} = Log.insert_position(drive, p)
      assert {:ok, drive} = Log.close_drive(drive)

      {:ok, %Address{id: start_id}} = Locations.find_address(drive.start_position)
      {:ok, %Address{id: end_id}} = Locations.find_address(drive.end_position)

      assert {:ok, %Drive{start_address_id: ^start_id, end_address_id: ^end_id}} =
               Log.update_drive(drive, %{start_address_id: start_id, end_address_id: end_id})

      assert start_id != end_id

      assert %Drive{start_address_id: ^start_id, end_address_id: ^end_id} =
               Repo.get(Drive, drive.id)
    end
  end

  describe "geo-fencing" do
    alias TeslaMate.Locations.GeoFence
    alias TeslaMate.Locations

    def geofence_fixture(attrs \\ %{}) do
      {:ok, geofence} =
        attrs
        |> Enum.into(%{name: "foo", latitude: 52.514521, longitude: 13.350144, radius: 42})
        |> Locations.create_geofence()

      geofence
    end

    test "links to the nearby geo-fence" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          speed: 23,
          power: 15,
          odometer: 284.85156,
          ideal_battery_range_km: 338.8,
          rated_battery_range_km: 308.8,
          battery_level: 68,
          outside_temp: 19.2,
          inside_temp: 21.0
        },
        %{
          date: "2019-04-06 10:23:25",
          latitude: 49.11196,
          longitude: 11.222,
          speed: 39,
          power: 36,
          odometer: 288.045561,
          ideal_battery_range_km: 334.8,
          rated_battery_range_km: 304.8,
          battery_level: 68,
          outside_temp: 18.0,
          inside_temp: 21.0
        }
      ]

      ###

      assert %GeoFence{id: start_id} =
               geofence_fixture(%{latitude: 50.1121, longitude: 11.597, radius: 100})

      assert %GeoFence{id: end_id} =
               geofence_fixture(%{latitude: 49.11161, longitude: 11.222, radius: 200})

      {:ok, drive} = Log.start_drive(car)

      for p <- positions,
          do: {:ok, _} = Log.insert_position(drive, p)

      assert {:ok, drive} = Log.close_drive(drive)
      assert drive.start_geofence_id == start_id
      assert drive.end_geofence_id == end_id
    end
  end

  describe "elevation calculation" do
    test "calculates ascent and descent correctly" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          ideal_battery_range_km: 338.8,
          speed: 23,
          odometer: 284.85156
        },
        %{
          date: "2019-04-06 10:20:08",
          latitude: 50.112214,
          longitude: 11.598471,
          elevation: 150,
          speed: 42,
          odometer: 285.90556
        },
        %{
          date: "2019-04-06 10:21:14",
          latitude: 50.112167,
          longitude: 11.599395,
          elevation: 120,
          speed: 34,
          odometer: 286.969561
        },
        %{
          date: "2019-04-06 10:22:20",
          latitude: 50.112118,
          longitude: 11.599919,
          elevation: 180,
          speed: 21,
          odometer: 287.00556
        }
      ]

      assert {:ok, drive} = Log.start_drive(car)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(drive, p)
      end

      assert {:ok, drive} = Log.close_drive(drive)

      assert drive.ascent == 60
      assert drive.descent == 30
    end

    test "handles single elevation point gracefully" do
      car = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          elevation: 100,
          speed: 23,
          odometer: 284.85156
        },
        %{
          date: "2019-04-06 10:20:08",
          latitude: 50.112214,
          longitude: 11.598471,
          ideal_battery_range_km: 338.8,
          speed: 42,
          odometer: 285.90556
        }
      ]

      assert {:ok, drive} = Log.start_drive(car)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(drive, p)
      end

      assert {:ok, drive} = Log.close_drive(drive)

      assert drive.ascent == 0
      assert drive.descent == 0
    end
  end

  # Polls as Vehicle stores them, a minute apart: with ideal range.
  defp poll_attrs(minute, elevation) do
    %{
      date: DateTime.add(~U[2019-04-06 10:19:02Z], minute, :minute),
      latitude: 50.112198,
      longitude: 11.597669,
      elevation: elevation,
      ideal_battery_range_km: 338.8,
      odometer: 284.85156 + minute
    }
  end

  # Stream positions as Vehicle stores them: without ideal range.
  defp stream_attrs(minute, elevation) do
    minute |> poll_attrs(elevation) |> Map.delete(:ideal_battery_range_km)
  end

  defp insert_positions(drive, attrs) do
    for attrs <- attrs do
      assert {:ok, position} = Log.insert_position(drive, attrs)
      position
    end
  end

  defp queued?(%Drive{id: id}) do
    Repo.exists?(from queued in "terrain_elevation_queue", where: queued.drive_id == ^id)
  end

  # A drive whose stream sends a position late: in the order stored, p2 and p3
  # lie in a stream gap, by date only p3 does.
  defp drive_with_late_stream_position(car, [p2_elevation, p3_elevation]) do
    assert {:ok, drive} = Log.start_drive(car)

    positions =
      insert_positions(drive, [
        stream_attrs(0, 100),
        poll_attrs(2, nil),
        poll_attrs(4, nil),
        poll_attrs(6, p2_elevation),
        poll_attrs(8, p3_elevation),
        stream_attrs(3, 110)
      ])

    {drive, positions}
  end

  describe "close_drive/1 with terrain elevations" do
    test "removes the terrain elevation from polls stored in a stream gap that by date lie in none" do
      car = car_fixture()

      {drive, [_s0, _p0, _p1, p2, p3, _late]} =
        drive_with_late_stream_position(car, [200, 160])

      assert {:ok, %Drive{ascent: 60, descent: 0}} = Log.close_drive(drive)

      assert %Position{elevation: nil} = Repo.get!(Position, p2.id)
      assert %Position{elevation: 160} = Repo.get!(Position, p3.id)
    end

    test "keeps the terrain elevation of polls stored while the car was not streaming" do
      car = car_fixture()

      # Streaming is switched on and off again during the drive: the polls
      # before and after the stream position got the terrain elevation.
      assert {:ok, drive} = Log.start_drive(car)

      [p0, _p1, _s0, _p2, p3] =
        insert_positions(drive, [
          poll_attrs(0, 36),
          poll_attrs(1, nil),
          stream_attrs(2, 37),
          poll_attrs(2, nil),
          poll_attrs(3, 39)
        ])

      assert {:ok, %Drive{ascent: 3, descent: 0}} = Log.close_drive(drive)

      assert %Position{elevation: 36} = Repo.get!(Position, p0.id)
      assert %Position{elevation: 39} = Repo.get!(Position, p3.id)
    end

    test "keeps the elevations of the polls of a drive without stream positions" do
      car = car_fixture()

      assert {:ok, drive} = Log.start_drive(car)
      _positions = insert_positions(drive, [poll_attrs(0, 100), poll_attrs(1, 150)])

      assert {:ok, %Drive{ascent: 50, descent: 0}} = Log.close_drive(drive)
    end
  end

  describe "add_terrain_elevation/4" do
    defp closed_drive_with_elevations(car, elevations) do
      assert {:ok, drive} = Log.start_drive(car)

      positions =
        insert_positions(
          drive,
          for(
            {elevation, minute} <- Enum.with_index(elevations),
            do: poll_attrs(minute, elevation)
          )
        )

      assert {:ok, drive} = Log.close_drive(drive)

      {drive, positions}
    end

    test "stores the elevations and recomputes the ascent and descent of a closed drive" do
      car = car_fixture()

      {drive, [_p0, p1, p2, _p3]} = closed_drive_with_elevations(car, [150, nil, nil, 180])

      assert drive.ascent == 30
      assert drive.descent == 0

      assert :ok = Log.add_terrain_elevation(drive.id, %{p1.id => 120, p2.id => 200}, :complete)

      assert %Drive{ascent: 80, descent: 50} = Repo.get!(Drive, drive.id)
      refute queued?(drive)

      assert %Position{elevation: 120} = Repo.get!(Position, p1.id)
      assert %Position{elevation: 200} = Repo.get!(Position, p2.id)
    end

    test "sets the sum to 0 if it exceeds the max value of a smallint" do
      car = car_fixture()

      {drive, [_p0, p1, _p2, _p3]} = closed_drive_with_elevations(car, [0, nil, 0, 1])

      assert :ok = Log.add_terrain_elevation(drive.id, %{p1.id => 32767}, :complete)

      assert %Drive{ascent: 0, descent: 32767} = Repo.get!(Drive, drive.id)
    end

    test "keeps a drive waiting for the next pass while a lookup did not answer" do
      car = car_fixture()

      {drive, [_p0, p1, _p2]} = closed_drive_with_elevations(car, [100, nil, nil])

      assert :ok = Log.add_terrain_elevation(drive.id, %{p1.id => 150}, :incomplete)

      assert %Drive{ascent: 50, descent: 0} = Repo.get!(Drive, drive.id)
      assert queued?(drive)

      assert :ok = Log.add_terrain_elevation(drive.id, %{}, :incomplete)
      assert queued?(drive)

      assert :ok = Log.add_terrain_elevation(drive.id, %{}, :complete)
      assert %Drive{ascent: 50} = Repo.get!(Drive, drive.id)
      refute queued?(drive)
    end

    test "stores the elevations of an open drive and leaves its ascent and descent to closing" do
      car = car_fixture()

      assert {:ok, drive} = Log.start_drive(car)
      [p0, p1] = insert_positions(drive, [poll_attrs(0, nil), poll_attrs(1, nil)])

      assert :ok = Log.add_terrain_elevation(drive.id, %{p0.id => 100, p1.id => 150}, :complete)

      assert %Drive{ascent: nil, descent: nil} = Repo.get!(Drive, drive.id)
      refute queued?(drive)

      assert %Position{elevation: 150} = Repo.get!(Position, p1.id)

      assert {:ok, %Drive{ascent: 50, descent: 0}} = Log.close_drive(drive)
    end

    test "removes the terrain elevation from a poll that by date lies in no stream gap" do
      car = car_fixture()

      {drive, [_s0, _p0, _p1, p2, p3, _late]} = drive_with_late_stream_position(car, [nil, nil])
      assert {:ok, %Drive{ascent: 10}} = Log.close_drive(drive)

      # Looked up before the late stream position was stored.
      assert :ok = Log.add_terrain_elevation(drive.id, %{p2.id => 200, p3.id => 160}, :complete)

      assert %Drive{ascent: 60, descent: 0} = Repo.get!(Drive, drive.id)
      assert %Position{elevation: nil} = Repo.get!(Position, p2.id)
      assert %Position{elevation: 160} = Repo.get!(Position, p3.id)
    end

    test "marks a drive whose lookups failed as tried at the given time" do
      car = car_fixture()

      {drive, [_p0, _p1]} = closed_drive_with_elevations(car, [100, nil])

      assert :ok =
               Log.add_terrain_elevation(drive.id, %{}, :failed, now: ~U[2024-05-01 12:00:00Z])

      assert [~U[2024-05-01 12:00:00.000000Z]] ==
               Repo.all(
                 from queued in "terrain_elevation_queue",
                   where: queued.drive_id == ^drive.id,
                   select: type(queued.attempted_at, :utc_datetime_usec)
               )
    end

    test "leaves a deleted drive deleted" do
      car = car_fixture()

      {drive, [_p0, p1]} = closed_drive_with_elevations(car, [100, nil])
      assert {:ok, _} = Repo.delete(drive)

      assert :ok = Log.add_terrain_elevation(drive.id, %{p1.id => 150}, :complete)
      assert nil == Repo.get(Drive, drive.id)
    end

    test "leaves the other drives unchanged" do
      car = car_fixture()

      {drive, [_p0, p1]} = closed_drive_with_elevations(car, [100, nil])
      {other_drive, [_q0, q1]} = closed_drive_with_elevations(car, [100, nil])

      assert :ok = Log.add_terrain_elevation(drive.id, %{p1.id => 150, q1.id => 150}, :complete)

      assert %Drive{ascent: 50, descent: 0} = Repo.get!(Drive, drive.id)

      assert %Drive{ascent: 0, descent: 0} = Repo.get!(Drive, other_drive.id)
      assert queued?(other_drive)

      assert %Position{elevation: nil} = Repo.get!(Position, q1.id)
    end
  end
end
