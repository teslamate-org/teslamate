defmodule TeslaMate.LocationsTest do
  use TeslaMate.DataCase

  alias TeslaMate.Log.{Charge, ChargingProcess}
  alias TeslaMate.{Locations, Log, Repo}
  alias TeslaMate.Locations.GeoFence

  describe "phase correction" do
    ## create

    test "creating a geofence with `apply_phase_correction: false` does not update exising charges" do
      {lat, lng} = {52.514521, 13.350144}
      charges = charges_fixture()

      assert {:ok, %ChargingProcess{id: id, charge_energy_used: used = 1.1192533333333332}} =
               log_charging_process(charges, {lat, lng})

      assert {:ok, %GeoFence{}} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: lat,
                 longitude: lng,
                 radius: 250,
                 phase_correction: 3
               })

      assert %ChargingProcess{charge_energy_used: ^used} = Repo.get!(ChargingProcess, id)
    end

    test "creating a geofence with `apply_phase_correction: true` updates exising charges" do
      {lat, lng} = {52.514521, 13.350144}
      charges = charges_fixture()

      assert {:ok, %ChargingProcess{id: id, charge_energy_used: used = 1.1192533333333332}} =
               log_charging_process(charges, {lat, lng})

      assert {:ok, %GeoFence{}} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: lat,
                 longitude: lng,
                 radius: 250,
                 phase_correction: 3,
                 apply_phase_correction: true
               })

      assert %ChargingProcess{charge_energy_used: 1.67888} = Repo.get!(ChargingProcess, id)
    end

    ## update

    test "full circle" do
      {lat, lng} = {52.514521, 13.350144}
      charges = charges_fixture()

      assert {:ok, %ChargingProcess{id: id_1, charge_energy_used: used_2p = 1.1192533333333332}} =
               log_charging_process(charges, {lat, lng})

      ## no change

      assert {:ok, geofence} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: lat,
                 longitude: lng,
                 radius: 250,
                 phase_correction: 3
               })

      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_1)

      ## applied

      assert {:ok, geofence} =
               Locations.update_geofence(geofence, %{apply_phase_correction: true})

      assert %ChargingProcess{charge_energy_used: used_3p = 1.67888} =
               Repo.get!(ChargingProcess, id_1)

      ## is applied to new charges within this geofence as well

      assert {:ok, %ChargingProcess{id: id_2, charge_energy_used: ^used_3p}} =
               log_charging_process(charges, {lat, lng})

      ## position change

      {new_lat, new_lng} = {37.8896, 41.1291}

      assert {:ok, %ChargingProcess{id: id_3, charge_energy_used: ^used_2p}} =
               log_charging_process(charges, {new_lat, new_lng})

      assert {:ok, geofence} =
               Locations.update_geofence(geofence, %{
                 latitude: new_lat,
                 longitude: new_lng,
                 apply_phase_correction: true
               })

      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_1)
      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_2)
      assert %ChargingProcess{charge_energy_used: ^used_3p} = Repo.get!(ChargingProcess, id_3)

      ## deletion

      assert {:ok, _geofence} = Locations.delete_geofence(geofence)

      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_1)
      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_2)
      assert %ChargingProcess{charge_energy_used: ^used_2p} = Repo.get!(ChargingProcess, id_3)
    end

    ## delete

    test "undos the phase correction during deletion in any case" do
      {lat, lng, charges} = {52.514521, 13.350144, charges_fixture()}

      assert {:ok, geofence} =
               Locations.create_geofence(%{
                 name: "foo",
                 latitude: lat,
                 longitude: lng,
                 radius: 20,
                 phase_correction: 3
               })

      assert {:ok, %ChargingProcess{id: id, charge_energy_used: _used_3p = 1.67888}} =
               log_charging_process(charges, {lat, lng})

      ## delete

      assert {:ok, _geofence} = Locations.delete_geofence(geofence)

      assert %ChargingProcess{charge_energy_used: _used_2p = 1.1192533333333332} =
               Repo.get!(ChargingProcess, id)
    end

    defp charges_fixture do
      [
        {"2019-10-19 18:27:35", 0, 8, 288.9, 2, 12, 231},
        {"2019-10-19 18:27:41", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:30:35", 0.52, 8, 292.3, 2, 12, 229},
        {"2019-10-19 18:34:16", 1.05, 8, 295.8, 2, 12, 230},
        {"2019-10-19 18:36:33", 1.26, 8, 297.1, 2, 12, 232},
        {"2019-10-19 18:38:03", 1.57, 8, 299.2, 2, 12, 229},
        {"2019-10-19 18:39:44", 1.68, 8, 299.9, 2, 12, 232},
        {"2019-10-19 18:39:49", 1.68, 0, 299.9, nil, 0, 64}
      ]
    end

    defp log_charging_process(charges, {lat, lng}) do
      id = :rand.uniform(1024)

      {:ok, car} = Log.create_car(%{eid: id, model: "M3", vid: id, vin: "vin_#{id}"})

      {:ok, cproc} =
        Log.start_charging_process(car, %{date: DateTime.utc_now(), latitude: lat, longitude: lng})

      for {date, added, power, range, phases, current, voltage} <- charges do
        {:ok, %Charge{}} =
          Log.insert_charge(cproc, %{
            date: date,
            charge_energy_added: added,
            charger_power: power,
            ideal_battery_range_km: range,
            charger_phases: phases,
            charger_actual_current: current,
            charger_voltage: voltage
          })
      end

      {:ok, %ChargingProcess{}} = Log.complete_charging_process(cproc)
    end
  end
end
