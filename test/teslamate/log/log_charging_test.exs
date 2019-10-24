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

      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)
      assert cproc.car_id == car_id
      assert cproc.position.latitude == @valid_pos_attrs.latitude
      assert cproc.position.longitude == @valid_pos_attrs.longitude
      assert cproc.position.date == @valid_pos_attrs.date
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

      custom_date = DateTime.from_unix!(1_566_059_683_000, :microsecond)

      assert {:ok, %ChargingProcess{start_date: ^custom_date}} =
               Log.start_charging_process(car_id, @valid_pos_attrs, date: custom_date)
    end

    @tag :capture_log
    test "leaves address blank if resolving failed" do
      assert %Car{id: car_id} = car_fixture()

      assert {:ok, cproc} =
               Log.start_charging_process(car_id, %{
                 date: DateTime.utc_now(),
                 latitude: 99.9,
                 longitude: 99.9
               })

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
      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)
      assert {:ok, %Charge{} = charge} = Log.insert_charge(cproc, @valid_attrs)

      assert charge.charging_process_id == cproc.id
      assert charge.date == @valid_attrs.date
      assert charge.charger_phases == @valid_attrs.charger_phases
      assert charge.charger_power == @valid_attrs.charger_power
      assert charge.charge_energy_added == @valid_attrs.charge_energy_added
      assert charge.ideal_battery_range_km == @valid_attrs.ideal_battery_range_km
    end

    test "with invalid data returns error changeset" do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.insert_charge(cproc, %{charger_phases: 0})

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
      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

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
        assert {:ok, %Charge{} = charge} = Log.insert_charge(cproc, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} = Log.complete_charging_process(cproc)

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

      Process.sleep(100)

      # calling it a 2nd time won't overwrite the end_date
      assert {:ok, ^cproc} = Log.complete_charging_process(cproc)
    end

    test "accepts a custom end date" do
      assert %Car{id: car_id} = car_fixture()

      custom_date = DateTime.from_unix!(1_566_059_683_000_000, :microsecond)

      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:ok, %ChargingProcess{end_date: ^custom_date}} =
               Log.complete_charging_process(cproc, date: custom_date)
    end

    test "closes charging process with zero charges " do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

      assert {:ok, %ChargingProcess{} = cproc} = Log.complete_charging_process(cproc)
      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
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

      {:ok, cproc} =
        Log.start_charging_process(car_id, %{
          date: DateTime.utc_now(),
          latitude: 50.112198,
          longitude: 11.597669
        })

      for c <- charges, do: {:ok, %Charge{}} = Log.insert_charge(cproc, c)

      assert {:ok, %ChargingProcess{geofence_id: ^id}} = Log.complete_charging_process(cproc)
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

    test "makes a rough estimate starting at two values" do
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

      {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

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
        {:ok, %Charge{}} = Log.insert_charge(cproc, c)
      end

      {:ok, %ChargingProcess{}} = Log.complete_charging_process(cproc)

      :ok
    end
  end

  describe "charge energy used" do
    test "calculates the energy used [P]" do
      charges = charges_fixture_1()

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == 12.77
      assert cproc.charge_energy_used == 12.455230833333333
      assert cproc.charge_energy_used_confidence == 0.88
      assert cproc.duration_min == 19
      assert cproc.start_ideal_range_km == 235.9
      assert cproc.end_ideal_range_km == 320.5
    end

    test "calculates the energy used [I * U]" do
      charges = charges_fixture_2()

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == 1.68
      assert cproc.charge_energy_used == 1.7756899999999984
      assert cproc.charge_energy_used_confidence == 0.9928571428571429
      assert cproc.duration_min == 13
      assert cproc.start_ideal_range_km == 288.9
      assert cproc.end_ideal_range_km == 299.9
    end

    test "handles a bad connection" do
      charges =
        charges_fixture_1()
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> rem(i, 3) == 0 end)
        |> Enum.map(fn {c, _} -> c end)

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == 12.67
      assert cproc.charge_energy_used == 12.45422888888889
      assert cproc.charge_energy_used_confidence == nil
      assert cproc.duration_min == 18
      assert cproc.start_ideal_range_km == 235.9
      assert cproc.end_ideal_range_km == 319.8
    end

    test "handles data gaps" do
      {c1, c2} = charges_fixture_1() |> Enum.split(100)

      charges =
        c1 ++
          Enum.map(c2, fn {date, added, _, _, _, _, _} = data ->
            new_date =
              date
              |> String.split(" ")
              |> Enum.join("T")
              |> Kernel.<>("Z")
              |> DateTime.from_iso8601()
              |> elem(1)
              |> DateTime.add(2 * 60, :second)
              |> DateTime.to_iso8601()

            data
            |> put_elem(0, new_date)
            |> put_elem(1, added + 1)
          end)

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == 13.77
      assert cproc.charge_energy_used == 13.8218975
      assert cproc.charge_energy_used_confidence == 0.875
      assert cproc.duration_min == 21
    end

    defp log_charging_process(charges) do
      %Car{id: car_id} = car_fixture()

      {:ok, cproc} = Log.start_charging_process(car_id, @valid_pos_attrs)

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

      {:ok, %ChargingProcess{}} = Log.complete_charging_process(cproc, charging_interval: 5)
    end

    defp charges_fixture_1 do
      [
        {"2019-10-24 06:43:48.022", 0, -1, 235.9, nil, 0, 1},
        {"2019-10-24 06:43:53.806", 0, -1, 236.6, nil, 0, 1},
        {"2019-10-24 06:43:59.474", 0, 43, 235.9, nil, 0, 1},
        {"2019-10-24 06:44:05.025", 0, 41, 236.6, nil, 0, 1},
        {"2019-10-24 06:44:10.538", 0.1, 41, 237.3, nil, 0, 1},
        {"2019-10-24 06:44:16.098", 0.1, 40, 237.3, nil, 0, 1},
        {"2019-10-24 06:44:21.755", 0.1, 40, 237.3, nil, 0, 1},
        {"2019-10-24 06:44:27.265", 0.21, 40, 238, nil, 0, 1},
        {"2019-10-24 06:44:32.821", 0.21, 40, 238, nil, 0, 1},
        {"2019-10-24 06:44:38.338", 0.31, 39, 238.7, nil, 0, 1},
        {"2019-10-24 06:44:43.858", 0.42, 40, 239.3, nil, 0, 1},
        {"2019-10-24 06:44:49.63", 0.52, 41, 240, nil, 0, 1},
        {"2019-10-24 06:44:55.11", 0.63, 40, 240.7, nil, 0, 1},
        {"2019-10-24 06:45:00.585", 0.63, 40, 240.7, nil, 0, 1},
        {"2019-10-24 06:45:06.106", 0.63, 40, 240.7, nil, 0, 1},
        {"2019-10-24 06:45:11.625", 0.73, 40, 241.4, nil, 0, 1},
        {"2019-10-24 06:45:17.145", 0.73, 41, 241.4, nil, 0, 1},
        {"2019-10-24 06:45:22.666", 0.84, 41, 242.1, nil, 0, 1},
        {"2019-10-24 06:45:28.33", 1.04, 40, 243.5, nil, 0, 1},
        {"2019-10-24 06:45:33.857", 1.04, 40, 243.5, nil, 0, 1},
        {"2019-10-24 06:45:39.384", 1.05, 40, 243.5, nil, 0, 1},
        {"2019-10-24 06:45:44.899", 1.15, 40, 244.2, nil, 0, 1},
        {"2019-10-24 06:45:50.425", 1.15, 40, 244.1, nil, 0, 1},
        {"2019-10-24 06:45:56.023", 1.26, 41, 244.8, nil, 0, 1},
        {"2019-10-24 06:46:01.543", 1.36, 41, 245.5, nil, 0, 1},
        {"2019-10-24 06:46:07.057", 1.36, 40, 245.5, nil, 0, 1},
        {"2019-10-24 06:46:12.581", 1.57, 40, 245.5, nil, 0, 1},
        {"2019-10-24 06:46:18.06", 1.57, 40, 246.9, nil, 0, 1},
        {"2019-10-24 06:46:23.698", 1.47, 40, 246.2, nil, 0, 1},
        {"2019-10-24 06:46:29.219", 1.68, 40, 247.6, nil, 0, 1},
        {"2019-10-24 06:46:34.736", 1.67, 40, 247.6, nil, 0, 1},
        {"2019-10-24 06:46:40.278", 1.78, 40, 248.3, nil, 0, 1},
        {"2019-10-24 06:46:45.733", 1.88, 41, 248.3, nil, 0, 1},
        {"2019-10-24 06:46:51.181", 1.88, 40, 248.9, nil, 0, 1},
        {"2019-10-24 06:46:56.662", 1.88, 40, 248.9, nil, 0, 1},
        {"2019-10-24 06:47:02.179", 1.99, 40, 249.6, nil, 0, 1},
        {"2019-10-24 06:47:07.67", 1.99, 40, 249.7, nil, 0, 1},
        {"2019-10-24 06:47:13.225", 2.2, 41, 251, nil, 0, 1},
        {"2019-10-24 06:47:18.737", 2.3, 41, 251.7, nil, 0, 1},
        {"2019-10-24 06:47:24.257", 2.3, 40, 251.7, nil, 0, 1},
        {"2019-10-24 06:47:29.802", 2.3, 40, 251.7, nil, 0, 1},
        {"2019-10-24 06:47:35.299", 2.41, 40, 252.4, nil, 0, 1},
        {"2019-10-24 06:47:40.826", 2.41, 40, 252.4, nil, 0, 1},
        {"2019-10-24 06:47:46.337", 2.51, 41, 253.1, nil, 0, 1},
        {"2019-10-24 06:47:51.802", 2.72, 40, 253.1, nil, 0, 1},
        {"2019-10-24 06:47:57.295", 2.72, 40, 254.5, nil, 0, 1},
        {"2019-10-24 06:48:02.766", 2.72, 40, 254.5, nil, 0, 1},
        {"2019-10-24 06:48:08.256", 2.83, 40, 255.2, nil, 0, 1},
        {"2019-10-24 06:48:14.425", 2.83, 40, 255.2, nil, 0, 1},
        {"2019-10-24 06:48:20.012", 2.93, 40, 255.9, nil, 0, 1},
        {"2019-10-24 06:48:25.619", 3.04, 40, 256.5, nil, 0, 1},
        {"2019-10-24 06:48:31.138", 3.04, 40, 256.5, nil, 0, 1},
        {"2019-10-24 06:48:36.657", 3.14, 40, 257.2, nil, 0, 1},
        {"2019-10-24 06:48:42.179", 3.25, 40, 257.9, nil, 0, 1},
        {"2019-10-24 06:48:47.701", 3.25, 41, 257.9, nil, 0, 1},
        {"2019-10-24 06:48:53.3", 3.35, 40, 258.6, nil, 0, 1},
        {"2019-10-24 06:48:58.824", 3.46, 40, 258.6, nil, 0, 1},
        {"2019-10-24 06:49:04.358", 3.46, 40, 259.3, nil, 0, 1},
        {"2019-10-24 06:49:09.938", 3.46, 40, 259.3, nil, 0, 1},
        {"2019-10-24 06:49:15.548", 3.66, 40, 260.7, nil, 0, 1},
        {"2019-10-24 06:49:21.058", 3.66, 40, 260.7, nil, 0, 1},
        {"2019-10-24 06:49:26.531", 3.77, 40, 261.4, nil, 0, 1},
        {"2019-10-24 06:49:32.273", 3.87, 41, 262, nil, 0, 1},
        {"2019-10-24 06:49:37.78", 3.87, 40, 262, nil, 0, 1},
        {"2019-10-24 06:49:43.298", 3.87, 40, 262, nil, 0, 1},
        {"2019-10-24 06:49:48.826", 3.98, 40, 262.7, nil, 0, 1},
        {"2019-10-24 06:49:54.358", 3.98, 40, 262.7, nil, 0, 1},
        {"2019-10-24 06:49:59.961", 4.08, 41, 263.4, nil, 0, 1},
        {"2019-10-24 06:50:05.49", 4.29, 40, 263.4, nil, 0, 1},
        {"2019-10-24 06:50:11.098", 4.29, 40, 264.8, nil, 0, 1},
        {"2019-10-24 06:50:16.591", 4.29, 40, 264.8, nil, 0, 1},
        {"2019-10-24 06:50:22.12", 4.4, 40, 265.5, nil, 0, 1},
        {"2019-10-24 06:50:27.631", 4.4, 40, 265.5, nil, 0, 1},
        {"2019-10-24 06:50:33.227", 4.5, 41, 266.2, nil, 0, 1},
        {"2019-10-24 06:50:38.739", 4.71, 40, 266.2, nil, 0, 1},
        {"2019-10-24 06:50:44.263", 4.71, 40, 267.5, nil, 0, 1},
        {"2019-10-24 06:50:49.949", 4.61, 40, 266.8, nil, 0, 1},
        {"2019-10-24 06:50:55.474", 4.82, 40, 268.2, nil, 0, 1},
        {"2019-10-24 06:51:00.991", 4.82, 41, 268.2, nil, 0, 1},
        {"2019-10-24 06:51:06.501", 4.92, 41, 268.2, nil, 0, 1},
        {"2019-10-24 06:51:12.027", 4.92, 40, 268.9, nil, 0, 1},
        {"2019-10-24 06:51:17.54", 5.03, 40, 269.6, nil, 0, 1},
        {"2019-10-24 06:51:23.071", 5.03, 41, 269.6, nil, 0, 1},
        {"2019-10-24 06:51:28.669", 5.24, 41, 271, nil, 0, 1},
        {"2019-10-24 06:51:34.19", 5.24, 40, 271, nil, 0, 1},
        {"2019-10-24 06:51:39.941", 5.24, 40, 271, nil, 0, 1},
        {"2019-10-24 06:51:45.467", 5.34, 40, 271.7, nil, 0, 1},
        {"2019-10-24 06:51:50.982", 5.44, 40, 272.3, nil, 0, 1},
        {"2019-10-24 06:51:56.503", 5.44, 41, 272.3, nil, 0, 1},
        {"2019-10-24 06:52:02.027", 5.55, 40, 273, nil, 0, 1},
        {"2019-10-24 06:52:07.541", 5.55, 40, 273, nil, 0, 1},
        {"2019-10-24 06:52:13.308", 5.55, 40, 273, nil, 0, 1},
        {"2019-10-24 06:52:18.899", 5.76, 41, 274.4, nil, 0, 1},
        {"2019-10-24 06:52:24.422", 5.86, 41, 275.1, nil, 0, 1},
        {"2019-10-24 06:52:29.94", 5.86, 40, 275.1, nil, 0, 1},
        {"2019-10-24 06:52:35.385", 5.86, 40, 275.1, nil, 0, 1},
        {"2019-10-24 06:52:40.898", 5.97, 40, 275.8, nil, 0, 1},
        {"2019-10-24 06:52:46.42", 5.97, 40, 275.8, nil, 0, 1},
        {"2019-10-24 06:52:52.025", 6.07, 40, 276.5, nil, 0, 1},
        {"2019-10-24 06:52:57.548", 6.28, 41, 277.9, nil, 0, 1},
        {"2019-10-24 06:53:03.22", 6.28, 41, 277.9, nil, 0, 1},
        {"2019-10-24 06:53:08.666", 6.28, 41, 277.9, nil, 0, 1},
        {"2019-10-24 06:53:14.162", 6.39, 41, 278.5, nil, 0, 1},
        {"2019-10-24 06:53:19.61", 6.49, 40, 279.2, nil, 0, 1},
        {"2019-10-24 06:53:25.62", 6.49, 41, 279.2, nil, 0, 1},
        {"2019-10-24 06:53:31.221", 6.59, 41, 279.9, nil, 0, 1},
        {"2019-10-24 06:53:36.662", 6.59, 40, 279.9, nil, 0, 1},
        {"2019-10-24 06:53:42.182", 6.59, 40, 279.9, nil, 0, 1},
        {"2019-10-24 06:53:47.86", 6.8, 40, 280.6, nil, 0, 1},
        {"2019-10-24 06:53:53.378", 6.91, 40, 282, nil, 0, 1},
        {"2019-10-24 06:53:58.91", 6.91, 40, 282, nil, 0, 1},
        {"2019-10-24 06:54:04.497", 6.91, 41, 282, nil, 0, 1},
        {"2019-10-24 06:54:10.034", 7.01, 41, 282.6, nil, 0, 1},
        {"2019-10-24 06:54:15.548", 7.01, 41, 282.6, nil, 0, 1},
        {"2019-10-24 06:54:21.086", 7.12, 41, 283.3, nil, 0, 1},
        {"2019-10-24 06:54:26.578", 7.22, 41, 283.4, nil, 0, 1},
        {"2019-10-24 06:54:32.156", 7.22, 40, 284, nil, 0, 1},
        {"2019-10-24 06:54:37.67", 7.22, 41, 284, nil, 0, 1},
        {"2019-10-24 06:54:43.291", 7.43, 41, 285.4, nil, 0, 1},
        {"2019-10-24 06:54:48.758", 7.54, 41, 286.1, nil, 0, 1},
        {"2019-10-24 06:54:54.25", 7.54, 41, 286.1, nil, 0, 1},
        {"2019-10-24 06:54:59.778", 7.54, 40, 286.1, nil, 0, 1},
        {"2019-10-24 06:55:05.299", 7.64, 41, 286.8, nil, 0, 1},
        {"2019-10-24 06:55:10.901", 7.64, 41, 286.8, nil, 0, 1},
        {"2019-10-24 06:55:16.42", 7.75, 40, 287.5, nil, 0, 1},
        {"2019-10-24 06:55:21.939", 7.75, 41, 287.5, nil, 0, 1},
        {"2019-10-24 06:55:27.461", 7.96, 41, 288.9, nil, 0, 1},
        {"2019-10-24 06:55:32.984", 7.95, 40, 288.8, nil, 0, 1},
        {"2019-10-24 06:55:38.5", 8.06, 41, 289.5, nil, 0, 1},
        {"2019-10-24 06:55:44.024", 8.16, 41, 290.2, nil, 0, 1},
        {"2019-10-24 06:55:49.498", 8.16, 41, 290.2, nil, 0, 1},
        {"2019-10-24 06:55:55.464", 8.16, 40, 290.2, nil, 0, 1},
        {"2019-10-24 06:56:00.982", 8.27, 41, 290.9, nil, 0, 1},
        {"2019-10-24 06:56:06.495", 8.48, 40, 292.3, nil, 0, 1},
        {"2019-10-24 06:56:12.022", 8.48, 41, 292.3, nil, 0, 1},
        {"2019-10-24 06:56:17.563", 8.48, 41, 292.3, nil, 0, 2},
        {"2019-10-24 06:56:23.143", 8.58, 41, 293, nil, 0, 1},
        {"2019-10-24 06:56:28.664", 8.58, 41, 293, nil, 0, 1},
        {"2019-10-24 06:56:34.188", 8.69, 41, 293.7, nil, 0, 1},
        {"2019-10-24 06:56:39.789", 8.69, 41, 293.7, nil, 0, 1},
        {"2019-10-24 06:56:45.305", 8.9, 41, 295, nil, 0, 1},
        {"2019-10-24 06:56:50.821", 8.9, 41, 294.3, nil, 0, 1},
        {"2019-10-24 06:56:56.423", 9, 41, 295.7, nil, 0, 1},
        {"2019-10-24 06:57:02.023", 9.11, 41, 296.4, nil, 0, 1},
        {"2019-10-24 06:57:07.544", 9.11, 41, 296.4, nil, 0, 1},
        {"2019-10-24 06:57:13.059", 9.11, 41, 296.4, nil, 0, 1},
        {"2019-10-24 06:57:18.659", 9.21, 41, 297.1, nil, 0, 1},
        {"2019-10-24 06:57:24.105", 9.42, 41, 297.1, nil, 0, 1},
        {"2019-10-24 06:57:30.26", 9.42, 41, 298.5, nil, 0, 1},
        {"2019-10-24 06:57:35.859", 9.32, 41, 297.8, nil, 0, 1},
        {"2019-10-24 06:57:41.379", 9.53, 41, 299.2, nil, 0, 2},
        {"2019-10-24 06:57:46.898", 9.53, 41, 299.2, nil, 0, 1},
        {"2019-10-24 06:57:52.419", 9.63, 41, 299.9, nil, 0, 2},
        {"2019-10-24 06:57:57.949", 9.63, 41, 299.9, nil, 0, 1},
        {"2019-10-24 06:58:03.545", 9.74, 41, 300.5, nil, 0, 1},
        {"2019-10-24 06:58:09.059", 9.74, 41, 300.6, nil, 0, 2},
        {"2019-10-24 06:58:14.66", 9.94, 41, 301.9, nil, 0, 1},
        {"2019-10-24 06:58:20.102", 9.95, 41, 301.9, nil, 0, 1},
        {"2019-10-24 06:58:25.597", 10.05, 41, 301.9, nil, 0, 1},
        {"2019-10-24 06:58:31.302", 10.05, 41, 302.6, nil, 0, 1},
        {"2019-10-24 06:58:36.823", 10.15, 41, 303.3, nil, 0, 1},
        {"2019-10-24 06:58:42.26", 10.26, 41, 303.3, nil, 0, 1},
        {"2019-10-24 06:58:47.782", 10.26, 41, 304, nil, 0, 1},
        {"2019-10-24 06:58:53.239", 10.26, 41, 304, nil, 0, 2},
        {"2019-10-24 06:58:58.719", 10.47, 41, 305.4, nil, 0, 2},
        {"2019-10-24 06:59:04.252", 10.57, 41, 304.7, nil, 0, 1},
        {"2019-10-24 06:59:09.785", 10.57, 41, 306, nil, 0, 2},
        {"2019-10-24 06:59:15.422", 10.57, 41, 306, nil, 0, 1},
        {"2019-10-24 06:59:20.907", 10.68, 41, 306.7, nil, 0, 1},
        {"2019-10-24 06:59:26.421", 10.78, 41, 306.7, nil, 0, 1},
        {"2019-10-24 06:59:31.939", 10.78, 41, 307.4, nil, 0, 1},
        {"2019-10-24 06:59:37.422", 10.78, 41, 307.4, nil, 0, 1},
        {"2019-10-24 06:59:42.979", 10.89, 41, 307.4, nil, 0, 1},
        {"2019-10-24 06:59:48.59", 10.99, 41, 308.8, nil, 0, 2},
        {"2019-10-24 06:59:54.109", 10.99, 41, 308.8, nil, 0, 1},
        {"2019-10-24 06:59:59.625", 11.1, 41, 309.5, nil, 0, 1},
        {"2019-10-24 07:00:05.3", 11.2, 40, 309.5, nil, 0, 1},
        {"2019-10-24 07:00:10.821", 11.2, 40, 310.2, nil, 0, 1},
        {"2019-10-24 07:00:17.875", 11.31, 41, 310.9, nil, 0, 1},
        {"2019-10-24 07:00:26.183", 11.41, 41, 310.9, nil, 0, 1},
        {"2019-10-24 07:00:32.1", 11.41, 41, 311.6, nil, 0, 2},
        {"2019-10-24 07:00:38.35", 11.41, 40, 311.6, nil, 0, 1},
        {"2019-10-24 07:00:43.818", 11.62, 40, 312.9, nil, 0, 2},
        {"2019-10-24 07:00:49.286", 11.73, 40, 312.9, nil, 0, 1},
        {"2019-10-24 07:00:54.772", 11.73, 40, 313.6, nil, 0, 2},
        {"2019-10-24 07:01:00.459", 11.73, 40, 313.6, nil, 0, 1},
        {"2019-10-24 07:01:05.963", 11.83, 40, 314.3, nil, 0, 1},
        {"2019-10-24 07:01:14.562", 12.04, 40, 315.7, nil, 0, 1},
        {"2019-10-24 07:01:20.426", 11.94, 40, 315, nil, 0, 1},
        {"2019-10-24 07:01:26.025", 12.15, 40, 315, nil, 0, 1},
        {"2019-10-24 07:01:31.633", 12.25, 40, 316.4, nil, 0, 1},
        {"2019-10-24 07:01:37.14", 12.25, 41, 317.1, nil, 0, 1},
        {"2019-10-24 07:01:42.602", 12.25, 41, 317.1, nil, 0, 1},
        {"2019-10-24 07:01:48.099", 12.35, 41, 317.1, nil, 0, 2},
        {"2019-10-24 07:01:53.78", 12.46, 41, 317.7, nil, 0, 2},
        {"2019-10-24 07:01:59.309", 12.56, 40, 318.4, nil, 0, 1},
        {"2019-10-24 07:02:04.822", 12.56, 40, 318.4, nil, 0, 2},
        {"2019-10-24 07:02:10.34", 12.67, 40, 319.1, nil, 0, 1},
        {"2019-10-24 07:02:15.861", 12.67, 40, 319.8, nil, 0, 2},
        {"2019-10-24 07:02:21.326", 12.77, 40, 320.5, nil, 0, 2}
      ]
    end

    defp charges_fixture_2 do
      [
        {"2019-10-19 18:26:44", 0, 0, 288.9, 2, 0, 233},
        {"2019-10-19 18:26:50", 0, 0, 288.9, 2, 2, 234},
        {"2019-10-19 18:26:56", 0, 2, 288.9, 2, 5, 234},
        {"2019-10-19 18:27:02", 0, 4, 288.9, 2, 8, 235},
        {"2019-10-19 18:27:07", 0, 8, 288.9, 2, 12, 230},
        {"2019-10-19 18:27:13", 0, 8, 288.9, 2, 12, 231},
        {"2019-10-19 18:27:18", 0, 8, 288.9, 2, 12, 230},
        {"2019-10-19 18:27:24", 0, 8, 288.9, 2, 12, 230},
        {"2019-10-19 18:27:30", 0, 8, 288.9, 2, 12, 231},
        {"2019-10-19 18:27:35", 0, 8, 288.9, 2, 12, 231},
        {"2019-10-19 18:27:41", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:27:46", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:27:52", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:27:57", 0.1, 8, 289.6, 2, 12, 230},
        {"2019-10-19 18:28:03", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:28:09", 0.1, 8, 289.6, 2, 12, 230},
        {"2019-10-19 18:28:15", 0.1, 8, 289.6, 2, 12, 230},
        {"2019-10-19 18:28:20", 0.1, 8, 289.6, 2, 12, 230},
        {"2019-10-19 18:28:26", 0.1, 8, 289.6, 2, 12, 231},
        {"2019-10-19 18:28:31", 0.1, 8, 289.6, 2, 12, 230},
        {"2019-10-19 18:28:37", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:28:43", 0.21, 8, 290.3, 2, 12, 231},
        {"2019-10-19 18:28:48", 0.21, 8, 290.3, 2, 12, 231},
        {"2019-10-19 18:28:54", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:28:59", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:29:05", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:29:11", 0.21, 8, 290.3, 2, 12, 231},
        {"2019-10-19 18:29:16", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:29:22", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:29:28", 0.21, 8, 290.3, 2, 12, 230},
        {"2019-10-19 18:29:33", 0.42, 8, 291.6, 2, 12, 231},
        {"2019-10-19 18:29:39", 0.42, 8, 291.6, 2, 12, 231},
        {"2019-10-19 18:29:44", 0.42, 8, 291.6, 2, 12, 231},
        {"2019-10-19 18:29:50", 0.42, 8, 291.6, 2, 12, 230},
        {"2019-10-19 18:29:56", 0.42, 8, 291.6, 2, 12, 230},
        {"2019-10-19 18:30:01", 0.42, 8, 291.6, 2, 12, 231},
        {"2019-10-19 18:30:07", 0.42, 8, 291.6, 2, 12, 231},
        {"2019-10-19 18:30:12", 0.42, 8, 291.6, 2, 12, 230},
        {"2019-10-19 18:30:18", 0.31, 8, 290.9, 2, 12, 230},
        {"2019-10-19 18:30:24", 0.31, 8, 290.9, 2, 12, 231},
        {"2019-10-19 18:30:29", 0.31, 8, 290.9, 2, 12, 230},
        {"2019-10-19 18:30:35", 0.52, 8, 292.3, 2, 12, 229},
        {"2019-10-19 18:30:41", 0.52, 8, 292.3, 2, 12, 231},
        {"2019-10-19 18:30:46", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:30:52", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:30:58", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:31:03", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:31:09", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:31:15", 0.52, 8, 292.3, 2, 12, 229},
        {"2019-10-19 18:31:20", 0.52, 8, 292.3, 2, 12, 230},
        {"2019-10-19 18:31:26", 0.52, 8, 292.3, 2, 12, 231},
        {"2019-10-19 18:31:32", 0.63, 8, 293, 2, 12, 229},
        {"2019-10-19 18:31:37", 0.63, 8, 293, 2, 12, 230},
        {"2019-10-19 18:31:43", 0.63, 8, 293, 2, 12, 231},
        {"2019-10-19 18:31:49", 0.63, 8, 293, 2, 12, 231},
        {"2019-10-19 18:31:55", 0.63, 8, 293, 2, 12, 232},
        {"2019-10-19 18:32:00", 0.63, 8, 293, 2, 12, 231},
        {"2019-10-19 18:32:06", 0.63, 8, 293, 2, 12, 230},
        {"2019-10-19 18:32:12", 0.63, 8, 293, 2, 12, 230},
        {"2019-10-19 18:32:17", 0.63, 8, 293, 2, 12, 231},
        {"2019-10-19 18:32:23", 0.63, 8, 293, 2, 12, 231},
        {"2019-10-19 18:32:28", 0.73, 8, 293.7, 2, 12, 230},
        {"2019-10-19 18:32:34", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:32:40", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:32:46", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:32:51", 0.73, 8, 293.7, 2, 12, 230},
        {"2019-10-19 18:32:57", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:33:03", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:33:08", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:33:14", 0.73, 8, 293.7, 2, 12, 230},
        {"2019-10-19 18:33:20", 0.73, 8, 293.7, 2, 12, 231},
        {"2019-10-19 18:33:25", 0.94, 8, 295.1, 2, 12, 231},
        {"2019-10-19 18:33:31", 0.84, 8, 294.4, 2, 12, 231},
        {"2019-10-19 18:33:37", 0.84, 8, 294.4, 2, 12, 231},
        {"2019-10-19 18:33:42", 0.94, 8, 295.1, 2, 12, 231},
        {"2019-10-19 18:33:48", 0.94, 8, 295.1, 2, 12, 231},
        {"2019-10-19 18:33:54", 0.94, 8, 295.1, 2, 12, 231},
        {"2019-10-19 18:33:59", 0.84, 8, 294.4, 2, 12, 231},
        {"2019-10-19 18:34:05", 0.84, 8, 294.4, 2, 12, 231},
        {"2019-10-19 18:34:11", 0.84, 8, 295.8, 2, 12, 230},
        {"2019-10-19 18:34:16", 1.05, 8, 295.8, 2, 12, 230},
        {"2019-10-19 18:34:22", 1.05, 8, 295.8, 2, 12, 230},
        {"2019-10-19 18:34:28", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:34:33", 1.05, 8, 295.8, 2, 12, 230},
        {"2019-10-19 18:34:39", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:34:45", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:34:50", 1.05, 8, 295.8, 2, 12, 232},
        {"2019-10-19 18:34:56", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:35:02", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:35:07", 1.05, 8, 295.8, 2, 12, 231},
        {"2019-10-19 18:35:13", 1.15, 8, 296.4, 2, 12, 230},
        {"2019-10-19 18:35:18", 1.15, 8, 296.4, 2, 12, 230},
        {"2019-10-19 18:35:24", 1.15, 8, 296.4, 2, 12, 231},
        {"2019-10-19 18:35:30", 1.15, 8, 296.4, 2, 12, 231},
        {"2019-10-19 18:35:36", 1.15, 8, 296.4, 2, 12, 230},
        {"2019-10-19 18:35:41", 1.15, 8, 296.4, 2, 12, 230},
        {"2019-10-19 18:35:47", 1.15, 8, 296.4, 2, 12, 231},
        {"2019-10-19 18:35:52", 1.15, 8, 296.4, 2, 12, 233},
        {"2019-10-19 18:35:58", 1.15, 8, 296.4, 2, 12, 232},
        {"2019-10-19 18:36:04", 1.15, 8, 296.4, 2, 12, 232},
        {"2019-10-19 18:36:10", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:16", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:21", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:27", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:33", 1.26, 8, 297.1, 2, 12, 232},
        {"2019-10-19 18:36:38", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:44", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:49", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:36:55", 1.26, 8, 297.1, 2, 12, 230},
        {"2019-10-19 18:37:01", 1.26, 8, 297.1, 2, 12, 231},
        {"2019-10-19 18:37:06", 1.47, 8, 298.5, 2, 12, 231},
        {"2019-10-19 18:37:12", 1.36, 8, 297.8, 2, 12, 231},
        {"2019-10-19 18:37:18", 1.36, 8, 297.8, 2, 12, 230},
        {"2019-10-19 18:37:24", 1.36, 8, 297.8, 2, 12, 231},
        {"2019-10-19 18:37:29", 1.47, 8, 298.5, 2, 12, 231},
        {"2019-10-19 18:37:35", 1.47, 8, 298.5, 2, 12, 231},
        {"2019-10-19 18:37:40", 1.36, 8, 297.8, 2, 12, 230},
        {"2019-10-19 18:37:46", 1.36, 8, 297.8, 2, 12, 231},
        {"2019-10-19 18:37:51", 1.36, 8, 297.8, 2, 12, 231},
        {"2019-10-19 18:37:57", 1.47, 8, 298.5, 2, 12, 231},
        {"2019-10-19 18:38:03", 1.57, 8, 299.2, 2, 12, 229},
        {"2019-10-19 18:38:08", 1.57, 8, 299.2, 2, 12, 231},
        {"2019-10-19 18:38:14", 1.57, 8, 299.2, 2, 12, 231},
        {"2019-10-19 18:38:19", 1.57, 8, 299.2, 2, 12, 231},
        {"2019-10-19 18:38:25", 1.57, 8, 299.2, 2, 12, 232},
        {"2019-10-19 18:38:31", 1.57, 8, 299.2, 2, 12, 232},
        {"2019-10-19 18:38:36", 1.57, 8, 299.2, 2, 12, 231},
        {"2019-10-19 18:38:42", 1.57, 8, 299.2, 2, 12, 232},
        {"2019-10-19 18:38:48", 1.57, 8, 299.2, 2, 12, 233},
        {"2019-10-19 18:38:53", 1.57, 8, 299.2, 2, 12, 231},
        {"2019-10-19 18:38:59", 1.68, 8, 299.9, 2, 12, 231},
        {"2019-10-19 18:39:05", 1.68, 8, 299.9, 2, 12, 232},
        {"2019-10-19 18:39:10", 1.68, 8, 299.9, 2, 12, 231},
        {"2019-10-19 18:39:16", 1.68, 8, 299.9, 2, 12, 230},
        {"2019-10-19 18:39:21", 1.68, 8, 299.9, 2, 12, 232},
        {"2019-10-19 18:39:27", 1.68, 8, 299.9, 2, 12, 231},
        {"2019-10-19 18:39:33", 1.68, 8, 299.9, 2, 12, 230},
        {"2019-10-19 18:39:38", 1.68, 8, 299.9, 2, 12, 231},
        {"2019-10-19 18:39:44", 1.68, 8, 299.9, 2, 12, 232},
        {"2019-10-19 18:39:49", 1.68, 0, 299.9, nil, 0, 64}
      ]
    end
  end
end
