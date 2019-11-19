defmodule TeslaMate.LocationsGeofencesTest do
  use TeslaMate.DataCase

  alias TeslaMate.{Locations, Log, Repo}
  alias TeslaMate.Locations.GeoFence

  describe "geofences" do
    @valid_attrs %{name: "foo", latitude: 52.514521, longitude: 13.350144, radius: 42}
    @update_attrs %{
      name: "bar",
      latitude: 53.514521,
      longitude: 14.350144,
      radius: 43,
      phase_correction: 3
    }
    @invalid_attrs %{
      name: nil,
      latitude: nil,
      longitude: nil,
      radius: nil,
      phase_correction: nil,
      sleep_mode_whitelist: nil,
      sleep_mode_blacklist: nil
    }

    def geofence_fixture(attrs \\ %{}) do
      {:ok, geofence} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Locations.create_geofence()

      Repo.preload(geofence, [:sleep_mode_whitelist, :sleep_mode_blacklist])
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

      {:ok, %Log.ChargingProcess{} = cproc} = Log.complete_charging_process(charging_process_id)

      cproc
    end

    test "list_geofences/0 returns all geofences" do
      geofence = geofence_fixture()

      geofences =
        Locations.list_geofences()
        |> Enum.map(&Repo.preload(&1, [:sleep_mode_blacklist, :sleep_mode_whitelist]))

      assert geofences == [geofence]
    end

    test "get_geofence!/1 returns the geofence with given id" do
      geofence = geofence_fixture()
      assert Locations.get_geofence!(geofence.id) == geofence
    end

    test "create_geofence/1 with valid data creates a geofence" do
      assert {:ok, %GeoFence{} = geofence} = Locations.create_geofence(@valid_attrs)
      assert geofence.name == "foo"
      assert geofence.latitude == 52.514521
      assert geofence.longitude == 13.350144
      assert geofence.radius == 42
      assert geofence.phase_correction == nil
      geofence = Repo.preload(geofence, [:sleep_mode_whitelist, :sleep_mode_blacklist])
      assert geofence.sleep_mode_blacklist == []
      assert geofence.sleep_mode_whitelist == []
    end

    test "create_geofence/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Locations.create_geofence(@invalid_attrs)

      assert errors_on(changeset) == %{
               latitude: ["can't be blank"],
               longitude: ["can't be blank"],
               name: ["can't be blank"],
               radius: ["can't be blank"]
             }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Locations.create_geofence(%{
                 latitude: "wat",
                 longitude: "wat",
                 phase_correction: "wat"
               })

      assert %{
               latitude: ["is invalid"],
               longitude: ["is invalid"],
               phase_correction: ["is invalid"]
             } = errors_on(changeset)
    end

    test "create_geofence/1 fails if there is already a geo-fence nearby" do
      _geofence = geofence_fixture(%{latitude: 52.514521, longitude: 13.350144})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Locations.create_geofence(%{
                 name: "bar",
                 latitude: 52.514521,
                 longitude: 13.350144,
                 radius: 20
               })

      assert errors_on(changeset) == %{latitude: ["is overlapping with other geo-fence"]}
    end

    test "create_geofence/1 links the geofence with drives and charging processes" do
      car = car_fixture()

      %Log.ChargingProcess{id: cproc_id} =
        create_charging_process(car, %{latitude: 52.51500, longitude: 13.35100})

      %Log.Drive{id: drive_id, start_geofence_id: nil, end_geofence_id: nil} =
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

      assert %Log.Drive{start_geofence_id: ^start_geofence_id, end_geofence_id: nil} =
               Repo.get(Log.Drive, drive_id)

      assert %Log.ChargingProcess{geofence_id: ^start_geofence_id} =
               Repo.get(Log.ChargingProcess, cproc_id)

      assert {:ok, %GeoFence{id: end_geofence_id}} =
               Locations.create_geofence(%{
                 name: "bar",
                 latitude: 51.2201,
                 longitude: 13.9501,
                 radius: 50
               })

      assert %Log.Drive{start_geofence_id: ^start_geofence_id, end_geofence_id: ^end_geofence_id} =
               Repo.get(Log.Drive, drive_id)
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
      car = car_fixture()
      geofence = geofence_fixture()

      attrs =
        Enum.into(%{sleep_mode_whitelist: [car], sleep_mode_blacklist: [car]}, @update_attrs)

      assert {:ok, %GeoFence{} = geofence} = Locations.update_geofence(geofence, attrs)
      assert geofence.name == "bar"
      assert geofence.latitude == 53.514521
      assert geofence.longitude == 14.350144
      assert geofence.radius == 43
      assert geofence.phase_correction == 3
      assert geofence.sleep_mode_blacklist == [car]
      assert geofence.sleep_mode_whitelist == [car]

      assert {:ok, %GeoFence{} = geofence} =
               Locations.update_geofence(geofence, %{sleep_mode_whitelist: []})

      assert geofence.sleep_mode_blacklist == [car]
      assert geofence.sleep_mode_whitelist == []
    end

    test "update_geofence/2 with invalid data returns error changeset" do
      geofence = geofence_fixture()
      assert {:error, %Ecto.Changeset{}} = Locations.update_geofence(geofence, @invalid_attrs)
      assert geofence == Locations.get_geofence!(geofence.id)
    end

    test "update_geofence/1 links the geofence with drives and charging processes" do
      car = car_fixture()

      %Log.ChargingProcess{id: cproc_id} =
        create_charging_process(car, %{latitude: 52.51500, longitude: 13.35100})

      %Log.Drive{id: drive_id, start_geofence_id: nil, end_geofence_id: nil} =
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

      assert %Log.Drive{start_geofence_id: ^geofence_id} = Repo.get(Log.Drive, drive_id)

      assert %Log.ChargingProcess{geofence_id: ^geofence_id} =
               Repo.get(Log.ChargingProcess, cproc_id)

      # Reduce radius

      assert {:ok, %GeoFence{id: ^geofence_id}} =
               Locations.update_geofence(geofence, %{radius: 10})

      assert %Log.Drive{start_geofence_id: nil} = Repo.get(Log.Drive, drive_id)
      assert %Log.ChargingProcess{geofence_id: nil} = Repo.get(Log.ChargingProcess, cproc_id)

      # Move geo-fence

      assert {:ok, %GeoFence{id: ^geofence_id}} =
               Locations.update_geofence(geofence, %{latitude: 52.51500, longitude: 13.35100})

      assert %Log.Drive{start_geofence_id: ^geofence_id} = Repo.get(Log.Drive, drive_id)

      assert %Log.ChargingProcess{geofence_id: ^geofence_id} =
               Repo.get(Log.ChargingProcess, cproc_id)
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
end
