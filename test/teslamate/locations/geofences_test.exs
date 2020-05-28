defmodule TeslaMate.LocationsGeofencesTest do
  use TeslaMate.DataCase

  alias TeslaMate.{Locations, Log, Repo}
  alias TeslaMate.Locations.GeoFence
  alias Log.{Drive, ChargingProcess}

  @valid_attrs %{
    name: "foo",
    latitude: 52.514521,
    longitude: 13.350144,
    radius: 42,
    billing_type: :per_kwh,
    cost_per_unit: nil,
    session_fee: nil
  }
  @update_attrs %{
    name: "bar",
    latitude: 53.514521,
    longitude: 14.350144,
    radius: 43,
    billing_type: :per_minute,
    cost_per_unit: 0.0079,
    session_fee: 5.0
  }
  @invalid_attrs %{
    name: nil,
    latitude: nil,
    longitude: nil,
    radius: nil,
    billing_type: :per_hour,
    cost_per_unit: -0.01,
    session_fee: -0.01
  }

  describe "geofences" do
    test "list_geofences/0 returns all geofences" do
      geofence = geofence_fixture()

      geofences = Locations.list_geofences()

      assert geofences == [geofence]
    end

    test "get_geofence!/1 returns the geofence with given id" do
      geofence = geofence_fixture()
      assert Locations.get_geofence!(geofence.id) == geofence
    end

    test "create_geofence/1 with valid data creates a geofence" do
      assert {:ok, %GeoFence{} = geofence} = Locations.create_geofence(@valid_attrs)
      assert geofence.name == "foo"
      assert geofence.latitude == Decimal.cast(52.514521)
      assert geofence.longitude == Decimal.cast(13.350144)
      assert geofence.radius == 42
      assert geofence.billing_type == :per_kwh
      assert geofence.cost_per_unit == nil
      assert geofence.session_fee == nil
    end

    test "create_geofence/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Locations.create_geofence(@invalid_attrs)

      assert errors_on(changeset) == %{
               latitude: ["can't be blank"],
               longitude: ["can't be blank"],
               name: ["can't be blank"],
               radius: ["can't be blank"],
               billing_type: ["is invalid"],
               cost_per_unit: ["must be greater than or equal to 0"],
               session_fee: ["must be greater than or equal to 0"]
             }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Locations.create_geofence(%{
                 latitude: "wat",
                 longitude: "wat"
               })

      assert %{
               latitude: ["is invalid"],
               longitude: ["is invalid"]
             } = errors_on(changeset)
    end

    test "create_geofence/1 links the geofence with drives and charging processes" do
      car = car_fixture()

      %ChargingProcess{id: cproc_id} =
        create_charging_process(car, %{latitude: 52.51500, longitude: 13.35100})

      %Drive{id: drive_id, start_geofence_id: nil, end_geofence_id: nil} =
        create_drive(car, %{latitude: 52.51500, longitude: 13.35100}, %{
          latitude: 51.22,
          longitude: 13.95
        })

      assert {:ok, %GeoFence{id: start_geofence_id}} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: 52.514521,
                 longitude: 13.350144,
                 radius: 250
               })

      assert %Drive{start_geofence_id: ^start_geofence_id, end_geofence_id: nil} =
               Repo.get(Drive, drive_id)

      assert %ChargingProcess{geofence_id: ^start_geofence_id} =
               Repo.get(ChargingProcess, cproc_id)

      assert {:ok, %GeoFence{id: end_geofence_id}} =
               Locations.create_geofence(%{
                 name: "bar",
                 latitude: 51.2201,
                 longitude: 13.9501,
                 radius: 50
               })

      assert %Drive{start_geofence_id: ^start_geofence_id, end_geofence_id: ^end_geofence_id} =
               Repo.get(Drive, drive_id)
    end

    test "find_geofence/1 return the geo-fence at the given point" do
      %GeoFence{id: id} =
        geofence_fixture(%{latitude: 52.514521, longitude: 13.350144, radius: 250})

      assert %GeoFence{id: ^id} =
               Locations.find_geofence(%{latitude: 52.514521, longitude: 13.350144})

      assert %GeoFence{id: ^id} =
               Locations.find_geofence(%{latitude: 52.51599, longitude: 13.35199})

      assert %GeoFence{id: ^id} =
               Locations.find_geofence(%{latitude: 52.51500, longitude: 13.35100})

      assert nil == Locations.find_geofence(%{latitude: 52.5, longitude: 13.3})
    end

    test "update_geofence/2 with valid data updates the geofence" do
      geofence = geofence_fixture()

      assert {:ok, %GeoFence{id: id} = geofence} =
               Locations.update_geofence(geofence, @update_attrs)

      assert geofence.name == "bar"
      assert geofence.latitude == Decimal.cast(53.514521)
      assert geofence.longitude == Decimal.cast(14.350144)
      assert geofence.radius == 43
      assert geofence.billing_type == :per_minute
      assert geofence.cost_per_unit == Decimal.cast(0.0079)
      assert geofence.session_fee == Decimal.cast("5.00")

      assert {:ok, %GeoFence{} = geofence} =
               Locations.update_geofence(geofence, %{cost_per_unit: nil, session_fee: nil})

      assert geofence.cost_per_unit == nil
      assert geofence.session_fee == nil
    end

    test "update_geofence/2 with invalid data returns error changeset" do
      geofence = geofence_fixture()
      assert {:error, %Ecto.Changeset{}} = Locations.update_geofence(geofence, @invalid_attrs)
      assert geofence == Locations.get_geofence!(geofence.id)
    end

    test "update_geofence/1 links the geofence with drives and charging processes" do
      car = car_fixture()

      %ChargingProcess{id: cproc_id} =
        create_charging_process(car, %{latitude: 52.51500, longitude: 13.35100})

      %Drive{id: drive_id, start_geofence_id: nil, end_geofence_id: nil} =
        create_drive(
          car,
          %{latitude: 52.51500, longitude: 13.35100},
          %{latitude: 51.22, longitude: 13.95}
        )

      assert {:ok, %GeoFence{id: geofence_id} = geofence} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: 52.514521,
                 longitude: 13.350144,
                 radius: 250
               })

      assert %Drive{start_geofence_id: ^geofence_id} = Repo.get(Drive, drive_id)

      assert %ChargingProcess{geofence_id: ^geofence_id} = Repo.get(ChargingProcess, cproc_id)

      # Reduce radius

      assert {:ok, %GeoFence{id: ^geofence_id}} =
               Locations.update_geofence(geofence, %{radius: 10})

      assert %Drive{start_geofence_id: nil} = Repo.get(Drive, drive_id)
      assert %ChargingProcess{geofence_id: nil} = Repo.get(ChargingProcess, cproc_id)

      # Move geo-fence

      assert {:ok, %GeoFence{id: ^geofence_id}} =
               Locations.update_geofence(geofence, %{latitude: 52.51500, longitude: 13.35100})

      assert %Drive{start_geofence_id: ^geofence_id} = Repo.get(Drive, drive_id)

      assert %ChargingProcess{geofence_id: ^geofence_id} = Repo.get(ChargingProcess, cproc_id)
    end

    test "delete_geofence/1 deletes the geofence" do
      geofence = geofence_fixture()
      assert {:ok, %GeoFence{}} = Locations.delete_geofence(geofence)
      assert_raise Ecto.NoResultsError, fn -> Locations.get_geofence!(geofence.id) end
    end

    test "change_geofence/1 returns a geofence changeset" do
      geofence = geofence_fixture()
      assert %Ecto.Changeset{} = Locations.change_geofence(geofence)
    end
  end

  describe "overlapping geo-fences" do
    test "are handled correctly" do
      [
        %{
          name: "huge",
          radius: 1658,
          latitude: 40.725633,
          longitude: -73.994207
        },
        %{
          name: "top",
          radius: 544,
          latitude: 40.734413,
          longitude: -73.983865
        },
        %{
          name: "middle",
          radius: 359,
          latitude: 40.724982,
          longitude: -73.999057
        },
        %{
          name: "bottom",
          radius: 614,
          latitude: 40.713728,
          longitude: -74.001288
        }
      ]
      |> Enum.map(&geofence_fixture/1)

      assert %GeoFence{name: "huge"} =
               Locations.find_geofence(%{latitude: 40.725307, longitude: -73.995838})

      assert %GeoFence{name: "huge"} =
               Locations.find_geofence(%{latitude: 40.717534, longitude: -73.978589})

      assert %GeoFence{name: "top"} =
               Locations.find_geofence(%{latitude: 40.737047, longitude: -73.980817})

      assert %GeoFence{name: "top"} =
               Locations.find_geofence(%{latitude: 40.731324, longitude: -73.988155})

      assert %GeoFence{name: "middle"} =
               Locations.find_geofence(%{latitude: 40.723551, longitude: -74.000687})

      assert %GeoFence{name: "middle"} =
               Locations.find_geofence(%{latitude: 40.722608, longitude: -73.997211})

      assert %GeoFence{name: "bottom"} =
               Locations.find_geofence(%{latitude: 40.709532, longitude: -74.00502})

      assert %GeoFence{name: "bottom"} =
               Locations.find_geofence(%{latitude: 40.715289, longitude: -74.007682})

      assert nil == Locations.find_geofence(%{latitude: 40.714737, longitude: -74.009142})
      assert nil == Locations.find_geofence(%{latitude: 40.715062, longitude: -73.976703})
    end

    test "deletes overlapping geo-fences" do
      car = car_fixture()

      position = %{latitude: 52.513619, longitude: 13.335633}
      charger_0 = %{latitude: 52.512955, longitude: 13.329694}
      charger_1 = %{latitude: 52.520344, longitude: 13.345496}

      assert %ChargingProcess{id: c0_id, geofence_id: nil} =
               create_charging_process(car, charger_1)

      # create initial geo-fence

      {:ok, _tiergarten = %GeoFence{id: t_id}} =
        Locations.create_geofence(%{
          name: "tiergarten",
          latitude: 52.514549,
          longitude: 13.350019,
          radius: 1658
        })

      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)

      # create drive & charge

      assert %ChargingProcess{id: c1_id, geofence_id: ^t_id} =
               create_charging_process(car, charger_0)

      assert %Drive{id: d0_id, start_geofence_id: ^t_id, end_geofence_id: ^t_id} =
               create_drive(car, position, position)

      # create new geo-fence that overlaps with the previous one

      {:ok, straße = %GeoFence{id: s_id}} =
        Locations.create_geofence(%{
          name: "Straße des 17. Juni",
          latitude: 52.513361,
          longitude: 13.332489,
          radius: 250
        })

      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: ^s_id} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: ^s_id, end_geofence_id: ^s_id} = Repo.get!(Drive, d0_id)

      # Delete geo-fence

      assert {:ok, %GeoFence{}} = Locations.delete_geofence(straße)
      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: ^t_id, end_geofence_id: ^t_id} = Repo.get!(Drive, d0_id)
    end

    test "updates overlapping geo-fences" do
      car = car_fixture()

      position = %{latitude: 52.513619, longitude: 13.335633}
      charger_0 = %{latitude: 52.512955, longitude: 13.329694}
      charger_1 = %{latitude: 52.520344, longitude: 13.345496}

      # create drive & charge

      assert %ChargingProcess{id: c0_id, geofence_id: nil} =
               create_charging_process(car, charger_1)

      assert %ChargingProcess{id: c1_id, geofence_id: nil} =
               create_charging_process(car, charger_0)

      assert %Drive{id: d0_id, start_geofence_id: nil, end_geofence_id: nil} =
               create_drive(car, position, position)

      # create geo-fences

      {:ok, tiergarten = %GeoFence{id: t_id}} =
        Locations.create_geofence(%{
          name: "tiergarten",
          latitude: 52.514549,
          longitude: 13.350019,
          radius: 721
        })

      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: nil} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: nil, end_geofence_id: nil} = Repo.get!(Drive, d0_id)

      {:ok, straße = %GeoFence{id: s_id}} =
        Locations.create_geofence(%{
          name: "Straße des 17. Juni",
          latitude: 52.513361,
          longitude: 13.332489,
          radius: 250
        })

      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: ^s_id} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: ^s_id, end_geofence_id: ^s_id} = Repo.get!(Drive, d0_id)

      # update geo-fence so that it overlaps with the other one

      assert {:ok, tiergarten} = Locations.update_geofence(tiergarten, %{radius: 1658})

      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: ^s_id} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: ^s_id, end_geofence_id: ^s_id} = Repo.get!(Drive, d0_id)

      # decrease radius of geo-fences

      assert {:ok, straße} = Locations.update_geofence(straße, %{radius: 20})
      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: ^t_id} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: ^t_id, end_geofence_id: ^t_id} = Repo.get!(Drive, d0_id)

      assert {:ok, tiergarten} = Locations.update_geofence(tiergarten, %{radius: 20})
      assert %ChargingProcess{geofence_id: nil} = Repo.get!(ChargingProcess, c0_id)
      assert %ChargingProcess{geofence_id: nil} = Repo.get!(ChargingProcess, c1_id)
      assert %Drive{start_geofence_id: nil, end_geofence_id: nil} = Repo.get!(Drive, d0_id)
    end

    test "creates overlapping geo-fences" do
      car = car_fixture()

      position = %{latitude: 52.513619, longitude: 13.335633}
      charger = %{latitude: 52.512955, longitude: 13.329694}

      assert %ChargingProcess{id: cproc_id, geofence_id: nil} =
               create_charging_process(car, charger)

      {:ok, %GeoFence{}} =
        Locations.create_geofence(%{
          name: "tiergarten",
          latitude: 52.514549,
          longitude: 13.350019,
          radius: 1658
        })

      {:ok, %GeoFence{id: id}} =
        Locations.create_geofence(%{
          name: "Straße des 17. Juni",
          latitude: 52.513361,
          longitude: 13.332489,
          radius: 250
        })

      assert %ChargingProcess{geofence_id: ^id} = Repo.get!(ChargingProcess, cproc_id)

      assert %Drive{id: drive_id, start_geofence_id: ^id, end_geofence_id: ^id} =
               create_drive(car, position, position)
    end
  end

  defp geofence_fixture(attrs \\ %{}) do
    {:ok, geofence} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Locations.create_geofence()

    geofence
  end

  defp car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 11, model: "M3", vid: 111, vin: "32532"})
      |> Log.create_car()

    car
  end

  defp create_drive(
         car,
         %{latitude: start_lat, longitude: start_lng},
         %{latitude: end_lat, longitude: end_lng}
       ) do
    positions = [
      %{
        date: "2019-04-06 10:19:02",
        latitude: start_lat,
        longitude: start_lng,
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
        latitude: end_lat,
        longitude: end_lng,
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

    {:ok, drive} = Log.start_drive(car)

    for p <- positions do
      {:ok, _} = Log.insert_position(drive, p)
    end

    {:ok, drive} = Log.close_drive(drive)

    drive
  end

  defp create_charging_process(car, %{latitude: lat, longitude: lng}) do
    {:ok, charging_process_id} =
      Log.start_charging_process(car, %{
        date: DateTime.utc_now(),
        latitude: lat,
        longitude: lng
      })

    charges = [
      %{
        date: "2019-04-05 16:01:27",
        battery_level: 50,
        charge_energy_added: 0.41,
        charger_actual_current: 5,
        charger_phases: 3,
        charger_pilot_current: 16,
        charger_power: 4,
        charger_voltage: 234,
        ideal_battery_range_km: 266.6,
        rated_battery_range_km: 206.6,
        outside_temp: 16
      },
      %{
        date: "2019-04-05 16:05:40",
        battery_level: 54,
        charge_energy_added: 0.72,
        charger_actual_current: 5,
        charger_phases: 3,
        charger_pilot_current: 16,
        charger_power: 4,
        charger_voltage: 234,
        ideal_battery_range_km: 268.6,
        rated_battery_range_km: 208.6,
        outside_temp: 14.5
      }
    ]

    for c <- charges do
      {:ok, %Log.Charge{}} = Log.insert_charge(charging_process_id, c)
    end

    {:ok, %ChargingProcess{} = cproc} = Log.complete_charging_process(charging_process_id)

    cproc
  end
end
