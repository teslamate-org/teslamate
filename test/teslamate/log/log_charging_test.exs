defmodule TeslaMate.LogChargingTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, ChargingProcess, Charge, Position}
  alias TeslaMate.{Log, Repo}

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end

  @valid_attrs %{
    date: DateTime.utc_now(),
    charger_power: 50,
    charger_phases: 3,
    charge_energy_added: 0.160,
    ideal_battery_range_km: 250
  }

  describe "start_charging_process/2" do
    @valid_pos_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

    test "with valid data creates a position" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert cproc =
               %ChargingProcess{} =
               ChargingProcess
               |> preload([:position, :address])
               |> Repo.get(charging_process_id)

      assert cproc.car_id == car_id
      assert cproc.position.latitude == @valid_pos_attrs.latitude
      assert cproc.position.longitude == @valid_pos_attrs.longitude
      assert cproc.position.date == DateTime.truncate(@valid_pos_attrs.date, :second)
      assert %DateTime{} = cproc.start_date
      assert cproc.address.city == "Bielefeld"
      assert cproc.address.place_id == 103_619_766
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.start_charging_process(nil, %{latitude: 0, longitude: 0})

      assert errors_on(changeset) == %{
               car_id: ["can't be blank"],
               position: %{
                 car_id: ["can't be blank"],
                 date: ["can't be blank"]
               }
             }
    end

    test "accepts a custom start date" do
      assert %Car{id: car_id} = car_fixture()

      custom_date = DateTime.from_unix!(1_566_059_683)

      assert {:ok, charging_process_id} =
               Log.start_charging_process(car_id, @valid_pos_attrs, date: custom_date)

      assert %ChargingProcess{start_date: ^custom_date} =
               ChargingProcess
               |> preload([:position, :address])
               |> Repo.get(charging_process_id)
    end

    @tag :capture_log
    test "leaves address blank if resolving failed" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, charging_process_id} =
               Log.start_charging_process(car_id, %{
                 date: DateTime.utc_now(),
                 latitude: 99.9,
                 longitude: 99.9
               })

      assert cproc =
               %ChargingProcess{} =
               ChargingProcess
               |> preload([:position, :address])
               |> Repo.get(charging_process_id)

      assert cproc.car_id == car_id
      assert cproc.position.latitude == 99.9
      assert cproc.position.longitude == 99.9
      assert cproc.address_id == nil
      assert cproc.address == nil
    end
  end

  describe "insert_charge/2" do
    test "with valid data creates a position" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)
      assert {:ok, %Charge{} = charge} = Log.insert_charge(charging_process_id, @valid_attrs)

      assert charge.charging_process_id == charging_process_id
      assert charge.date == DateTime.truncate(@valid_attrs.date, :second)
      assert charge.charger_phases == @valid_attrs.charger_phases
      assert charge.charger_power == @valid_attrs.charger_power
      assert charge.charge_energy_added == @valid_attrs.charge_energy_added
      assert charge.ideal_battery_range_km == @valid_attrs.ideal_battery_range_km
    end

    test "with invalid data returns error changeset" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.insert_charge(charging_process_id, %{charger_phases: 0})

      assert errors_on(changeset) == %{
               charger_phases: ["must be greater than 0"],
               charge_energy_added: ["can't be blank"],
               charger_power: ["can't be blank"],
               date: ["can't be blank"],
               ideal_battery_range_km: ["can't be blank"]
             }
    end
  end

  describe "complete_charging_process/1" do
    test "aggregates charging data" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

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
          date: "2019-04-05 16:02:28",
          battery_level: 51,
          charge_energy_added: 0.51,
          charger_actual_current: 5,
          charger_phases: 3,
          charger_pilot_current: 16,
          charger_power: 4,
          charger_voltage: 234,
          ideal_battery_range_km: 267.3,
          rated_battery_range_km: 207.6,
          outside_temp: 15.5
        },
        %{
          date: "2019-04-05 16:04:34",
          battery_level: 52,
          charge_energy_added: 0.72,
          charger_actual_current: 5,
          charger_phases: 3,
          charger_pilot_current: 16,
          charger_power: 4,
          charger_voltage: 234,
          ideal_battery_range_km: 268.6,
          rated_battery_range_km: 208.6,
          outside_temp: 15
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
        assert {:ok, %Charge{} = charge} = Log.insert_charge(charging_process_id, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} =
               Log.complete_charging_process(charging_process_id)

      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
      assert cproc.charge_energy_added == 0.31
      assert cproc.duration_min == 4
      assert cproc.end_battery_level == 54
      assert cproc.start_battery_level == 50
      assert cproc.start_ideal_range_km == 266.6
      assert cproc.end_ideal_range_km == 268.6
      assert cproc.start_rated_range_km == 206.6
      assert cproc.end_rated_range_km == 208.6
      assert cproc.outside_temp_avg == 15.25
    end

    test "accepts a custom end date" do
      assert %Car{id: car_id} = car_fixture()

      custom_date = DateTime.from_unix!(1_566_059_683)

      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:ok, %ChargingProcess{end_date: ^custom_date}} =
               Log.complete_charging_process(charging_process_id, date: custom_date)
    end

    test "closes charging process with zero charges " do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:ok, %ChargingProcess{} = cproc} =
               Log.complete_charging_process(charging_process_id)

      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
    end
  end

  describe "resume_charging_process/1" do
    test "resets some fields" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

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
        assert {:ok, %Charge{} = charge} = Log.insert_charge(charging_process_id, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} =
               Log.complete_charging_process(charging_process_id)

      assert %DateTime{} = start_date = cproc.start_date
      assert %DateTime{} = cproc.end_date
      assert cproc.charge_energy_added == 0.31
      assert cproc.duration_min == 4
      assert cproc.end_battery_level == 54
      assert cproc.start_battery_level == 50
      assert cproc.start_ideal_range_km == 266.6
      assert cproc.end_ideal_range_km == 268.6
      assert cproc.start_rated_range_km == 206.6
      assert cproc.end_rated_range_km == 208.6
      assert cproc.outside_temp_avg == 15.25

      # RESUME

      assert {:ok, %ChargingProcess{} = cproc} = Log.resume_charging_process(charging_process_id)

      assert ^start_date = cproc.start_date
      assert cproc.start_battery_level == 50
      assert cproc.start_ideal_range_km == 266.6
      assert cproc.outside_temp_avg == 15.25

      assert cproc.end_date == nil
      assert cproc.charge_energy_added == nil
      assert cproc.duration_min == nil
      assert cproc.end_battery_level == nil
      assert cproc.end_ideal_range_km == nil
      assert cproc.end_rated_range_km == nil

      charges = [
        %{
          date: "2019-04-05 16:15:40",
          battery_level: 55,
          charge_energy_added: 1.14,
          charger_actual_current: 5,
          charger_phases: 3,
          charger_pilot_current: 16,
          charger_power: 4,
          charger_voltage: 234,
          ideal_battery_range_km: 278.6,
          rated_battery_range_km: 218.6,
          outside_temp: 15.01
        }
      ]

      for c <- charges do
        assert {:ok, %Charge{} = charge} = Log.insert_charge(charging_process_id, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} =
               Log.complete_charging_process(charging_process_id)

      assert ^start_date = cproc.start_date
      assert %DateTime{} = cproc.end_date
      assert cproc.charge_energy_added == 0.73
      assert cproc.duration_min == 14
      assert cproc.end_battery_level == 55
      assert cproc.start_battery_level == 50
      assert cproc.start_ideal_range_km == 266.6
      assert cproc.end_ideal_range_km == 278.6
      assert cproc.start_rated_range_km == 206.6
      assert cproc.end_rated_range_km == 218.6
      assert cproc.outside_temp_avg == 15.17
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
      %Car{id: car_id} = car_fixture()

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

      ###

      assert %GeoFence{id: id} =
               geofence_fixture(%{latitude: 50.1121, longitude: 11.597, radius: 50})

      {:ok, charging_process_id} =
        Log.start_charging_process(car_id, %{
          date: DateTime.utc_now(),
          latitude: 50.112198,
          longitude: 11.597669
        })

      for c <- charges, do: {:ok, %Charge{}} = Log.insert_charge(charging_process_id, c)

      assert {:ok, %ChargingProcess{geofence_id: ^id}} =
               Log.complete_charging_process(charging_process_id)
    end
  end

  describe "efficiency factor" do
    test "recalculates the efficiency factor after completing a charging session" do
      alias TeslaMate.Settings

      {:ok, _pid} = start_supervised({Phoenix.PubSub.PG2, name: TeslaMate.PubSub})

      data = [
        {293.9, 293.9, 0.0, 59, 59, 0},
        {293.2, 303.4, 1.65, 59, 61, 33},
        {302.5, 302.5, 0.0, 61, 61, 0},
        {302.5, 302.5, 0.0, 61, 61, 0},
        {302.1, 309.5, 1.14, 61, 62, 23},
        {71.9, 350.5, 42.21, 14, 70, 27},
        {181.0, 484.0, 46.13, 36, 97, 46},
        {312.3, 324.9, 1.75, 63, 65, 6},
        {325.6, 482.7, 23.71, 65, 97, 34},
        {80.5, 412.4, 50.63, 16, 83, 70},
        {259.7, 426.2, 25.56, 52, 85, 36},
        {105.5, 361.4, 38.96, 21, 72, 22},
        {143.1, 282.5, 21.11, 29, 57, 15},
        {111.6, 406.9, 44.93, 22, 82, 36},
        {115.0, 453.2, 51.49, 23, 91, 38},
        {112.5, 112.5, 0.0, 23, 23, 1},
        {109.7, 139.7, 4.57, 22, 28, 26},
        {63.9, 142.3, 11.82, 13, 29, 221},
        {107.9, 450.1, 52.1, 22, 90, 40}
      ]

      assert %Car{id: car_id_0, efficiency: nil} = car_fixture(eid: 3_453, vid: 3240, vin: "slkf")
      assert %Car{id: car_id_1, efficiency: nil} = car_fixture(eid: 3_904, vid: 9403, vin: "salk")

      for {range, car_id} <- [{:ideal, car_id_0}, {:rated, car_id_1}] do
        {:ok, _} = Settings.get_settings!() |> Settings.update_settings(%{preferred_range: range})

        :ok = insert_charging_process_fixtures(car_id, data, range)

        assert %Car{efficiency: 0.152} = Log.get_car!(car_id)
      end
    end

    test "makes an estimate with up to 4 decimal places" do
      assert %Car{id: car_id, efficiency: nil} = car_fixture()

      data = [
        {330.8, 379.0, 7.34, 66, 76, 47},
        {98.6, 372.8, 41.96, 20, 75, 60},
        {374.8, 448.6, 11.33, 75, 90, 20},
        {148.5, 329.9, 28.13, 30, 66, 277},
        {163.6, 287.4, 18.94, 33, 58, 109},
        {148.0, 334.4, 28.37, 30, 67, 166},
        {195.7, 429.1, 35.53, 39, 86, 25},
        {217.9, 436.5, 33.28, 44, 87, 46},
        {99.2, 251.1, 23.12, 20, 50, 133},
        {223.5, 354.4, 20.04, 45, 71, 28},
        {239.3, 239.6, 0.05, 48, 48, 0},
        {76.4, 372.3, 44.95, 15, 75, 26},
        {81.1, 385.3, 46.31, 16, 77, 27},
        {97.6, 288.1, 29.1, 20, 58, 16},
        {72.5, 454.2, 57.99, 15, 91, 42},
        {289.4, 294.6, 0.52, 58, 59, 19},
        {294.6, 294.6, 0.0, 59, 59, 0},
        {285.8, 294.6, 1.34, 57, 59, 24},
        {312.3, 324.9, 1.75, 63, 65, 6},
        {325.6, 482.7, 23.71, 65, 97, 34},
        {80.5, 412.4, 50.63, 16, 83, 70},
        {259.7, 426.2, 25.56, 52, 85, 36},
        {105.5, 361.4, 38.96, 21, 72, 22},
        {143.1, 282.5, 21.11, 29, 57, 15},
        {111.6, 406.9, 44.93, 22, 82, 36},
        {115.0, 453.2, 51.49, 23, 91, 38},
        {364.2, 369.0, 0.73, 73, 74, 5},
        {332.2, 353.5, 3.25, 67, 71, 5}
      ]

      :ok = insert_charging_process_fixtures(car_id, data)

      assert %Car{efficiency: 0.1522} = Log.get_car!(car_id)
    end

    test "makes a rough estimate starting a two values" do
      ## 2x
      assert %Car{id: car_id, efficiency: nil} = car_fixture(eid: 666, vid: 667, vin: "668")

      data = [
        {283.1, 353.9, 10.57, 57, 71, 60}
      ]

      :ok = insert_charging_process_fixtures(car_id, data)

      assert %Car{efficiency: nil} = Log.get_car!(car_id)

      ## 3x

      assert %Car{id: car_id, efficiency: nil} = car_fixture(eid: 886, vid: 887, vin: "888")

      data = [
        {283.1, 353.9, 10.57, 57, 71, 60},
        {259.7, 426.2, 25.56, 52, 85, 36}
      ]

      :ok = insert_charging_process_fixtures(car_id, data)

      assert %Car{efficiency: 0.15} = Log.get_car!(car_id)
    end

    test "handles NULL" do
      assert %Car{id: car_id, efficiency: nil} = car_fixture()

      data = [
        {262.8, 263.5, 0.0, 53, 53, 0},
        {176.8, 177.5, 0.0, 35, 36, 3},
        {294.6, 294.6, 0.0, 59, 59, 0}
      ]

      :ok = insert_charging_process_fixtures(car_id, data)

      assert %Car{efficiency: nil} = Log.get_car!(car_id)
    end

    defp insert_charging_process_fixtures(car_id, data, range \\ :ideal) do
      {:ok, %Position{id: position_id}} = Log.insert_position(car_id, @valid_pos_attrs)

      {start_range, end_range} =
        case range do
          :ideal -> {:start_ideal_range_km, :end_ideal_range_km}
          :rated -> {:start_rated_range_km, :end_rated_range_km}
        end

      data =
        for {sr, er, ca, sl, el, d} <- data do
          %{
            car_id: car_id,
            position_id: position_id,
            charge_energy_added: ca,
            start_battery_level: sl,
            end_battery_level: el,
            duration_min: d
          }
          |> Map.put(start_range, sr)
          |> Map.put(end_range, er)
        end

      {_, nil} = Repo.insert_all(ChargingProcess, data)

      {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)

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
        {:ok, %Charge{}} = Log.insert_charge(charging_process_id, c)
      end

      {:ok, %ChargingProcess{}} = Log.complete_charging_process(charging_process_id)

      :ok
    end
  end
end
