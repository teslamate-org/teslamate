defmodule TeslaMate.LogDriveTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, Position, Drive}
  alias TeslaMate.Log

  @valid_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42})
      |> Log.create_car()

    car
  end

  test "start_drive/1 returns the drive_id" do
    assert %car{id: car_id} = car_fixture()
    assert {:ok, drive_id} = Log.start_drive(car_id)
    assert is_number(drive_id)
  end

  describe "insert_position/1" do
    test "with valid data creates a position" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, %Position{} = position} = Log.insert_position(car_id, @valid_attrs)
      assert %DateTime{} = position.date
      assert position.car_id == car_id
      assert position.longitude == 0.0
      assert position.latitude == 0.0
    end

    test "cannot insert positions for drives which don't exist" do
      assert %Car{id: car_id} = car_fixture()

      attrs = Map.put(@valid_attrs, :drive_id, 404)
      assert {:error, %Ecto.Changeset{} = changeset} = Log.insert_position(car_id, attrs)
      assert errors_on(changeset) == %{drive_id: ["does not exist"]}
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Log.insert_position(nil, %{})

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
      assert %car{id: car_id} = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:19:02",
          latitude: 50.112198,
          longitude: 11.597669,
          speed: 23,
          power: 15,
          odometer: 284.85156,
          ideal_battery_range_km: 338.8,
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
          battery_level: 68,
          outside_temp: 18.0,
          inside_temp: 21.0
        }
      ]

      assert {:ok, drive_id} = Log.start_drive(car_id)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(car_id, Map.put(p, :drive_id, drive_id))
      end

      assert {:ok, drive} = Log.close_drive(drive_id)

      assert {:ok, drive.end_date, 0} == DateTime.from_iso8601("2019-04-06 10:23:25Z")
      assert drive.outside_temp_avg == 19.04
      assert drive.inside_temp_avg == 21.04
      assert drive.speed_max == 42
      assert drive.power_max == 36.0
      assert drive.power_min == -7.0
      assert drive.power_avg == 8.2
      assert drive.start_km == 284.85156
      assert drive.end_km == 288.045561
      assert drive.distance == 3.1940010000000143
      assert drive.start_range_km == 338.8
      assert drive.end_range_km == 334.8
      assert drive.duration_min == 4
      assert drive.consumption_kWh == 0.612
      assert drive.consumption_kWh_100km == 19.160920738597053
      assert is_number(drive.start_address_id)
      assert addr_id = drive.start_address_id
      assert ^addr_id = drive.end_address_id
    end

    test "deletes a drive and if it has no positions" do
      assert %car{id: car_id} = car_fixture()

      assert {:ok, drive_id} = Log.start_drive(car_id)
      assert %Drive{} = Repo.get(Drive, drive_id)

      assert {:ok, %Drive{distance: 0.0, duration_min: 0}} = Log.close_drive(drive_id)
      assert nil == Repo.get(Drive, drive_id)
    end

    test "deletes a drive and its position if it has only one position" do
      assert %car{id: car_id} = car_fixture()

      positions = [
        %{date: "2019-04-06 10:00:00", latitude: 0.0, longitude: 0.0, odometer: 100}
      ]

      assert {:ok, drive_id} = Log.start_drive(car_id)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(car_id, Map.put(p, :drive_id, drive_id))
      end

      assert {:ok, %Drive{distance: 0.0, duration_min: 0}} = Log.close_drive(drive_id)
      assert nil == Repo.get(Drive, drive_id)
    end

    test "deletes a drive and its position if the distance driven is 0" do
      assert %car{id: car_id} = car_fixture()

      positions = [
        %{
          date: "2019-04-06 10:00:00",
          latitude: 0.0,
          longitude: 0.0,
          odometer: 100,
          ideal_battery_range_km: 300
        },
        %{
          date: "2019-04-06 10:05:00",
          latitude: 0.0,
          longitude: 0.0,
          odometer: 100,
          ideal_battery_range_km: 300
        }
      ]

      assert {:ok, drive_id} = Log.start_drive(car_id)

      for p <- positions do
        assert {:ok, _} = Log.insert_position(car_id, Map.put(p, :drive_id, drive_id))
      end

      assert {:ok, %Drive{distance: 0.0}} = Log.close_drive(drive_id)
      assert nil == Repo.get(Drive, drive_id)
    end
  end
end
