defmodule TeslaMate.LogDriveTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, Position, Drive}
  alias TeslaMate.Log

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

  describe "close_drive/2" do
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
      assert is_number(drive.start_address_id)
      assert addr_id = drive.start_address_id
      assert ^addr_id = drive.end_address_id
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
end
