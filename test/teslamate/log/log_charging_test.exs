defmodule TeslaMate.LogChargingTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, ChargingProcess, Charge, Position}
  alias TeslaMate.{Log, Repo, Locations}

  @valid_attrs %{
    date: DateTime.utc_now(),
    charger_power: 50,
    charger_phases: 3,
    charge_energy_added: 0.160,
    ideal_battery_range_km: 250
  }

  @valid_pos_attrs %{date: DateTime.utc_now(), latitude: 0.0, longitude: 0.0}

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{eid: 42, model: "M3", vid: 42, vin: "xxxxx"})
      |> Log.create_car()

    car
  end

  defp log_charging_process(charges, opts \\ []) do
    car =
      Keyword.get_lazy(opts, :car, fn ->
        id = :rand.uniform(1024)
        car_fixture(%{eid: id, vid: id, vin: "vin_#{id}"})
      end)

    attrs = Keyword.get(opts, :attrs, @valid_pos_attrs)

    {:ok, cproc} = Log.start_charging_process(car, attrs)

    for {date, added, power, range, phases, current, voltage, fc_type} <- charges do
      {:ok, %Charge{}} =
        Log.insert_charge(cproc, %{
          date: date,
          charge_energy_added: added,
          charger_power: power,
          ideal_battery_range_km: range,
          charger_phases: phases,
          charger_actual_current: current,
          charger_voltage: voltage,
          fast_charger_type: fc_type
        })
    end

    {:ok, %ChargingProcess{}} = Log.complete_charging_process(cproc)
  end

  describe "start_charging_process/2" do
    test "with valid data creates a position" do
      car = car_fixture()

      assert {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)
      assert cproc.car_id == car.id
      assert cproc.position.latitude == Decimal.new("0.000000")
      assert cproc.position.longitude == Decimal.new("0.000000")
      assert cproc.position.date == @valid_pos_attrs.date
      assert %DateTime{} = cproc.start_date
      assert cproc.address.city == "Bielefeld"
      assert cproc.address.osm_id == 103_619_766
    end

    test "with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Log.start_charging_process(%Car{}, %{latitude: 0, longitude: 0})

      assert errors_on(changeset) == %{
               car_id: ["can't be blank"],
               position: %{
                 car_id: ["can't be blank"],
                 date: ["can't be blank"]
               }
             }
    end

    @tag :capture_log
    test "leaves address blank if resolving failed" do
      car = car_fixture()

      assert {:ok, cproc} =
               Log.start_charging_process(car, %{
                 date: DateTime.utc_now(),
                 latitude: 99.9,
                 longitude: 99.9
               })

      assert cproc.car_id == car.id
      assert cproc.position.latitude == Decimal.new("99.900000")
      assert cproc.position.longitude == Decimal.new("99.900000")
      assert cproc.address_id == nil
      assert cproc.address == nil
    end

    test "saves dummy address if geocoding failed" do
      car = car_fixture()

      assert {:ok, cproc} =
               Log.start_charging_process(car, %{
                 date: DateTime.utc_now(),
                 latitude: -99.9,
                 longitude: -99.9
               })

      assert cproc.car_id == car.id
      assert cproc.position.latitude == Decimal.new("-99.900000")
      assert cproc.position.longitude == Decimal.new("-99.900000")
      assert not is_nil(cproc.address_id)

      assert %Locations.Address{
               osm_id: 0,
               osm_type: "unknown",
               display_name: "Unknown",
               latitude: latitude,
               longitude: longitude,
               raw: %{"error" => "Unable to geocode"}
             } = cproc.address

      assert latitude == Decimal.new("0.000000")
      assert longitude == Decimal.new("0.000000")
    end
  end

  describe "insert_charge/2" do
    test "with valid data creates a position" do
      car = car_fixture()

      assert {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)
      assert {:ok, %Charge{} = charge} = Log.insert_charge(cproc, @valid_attrs)

      assert charge.charging_process_id == cproc.id
      assert charge.date == @valid_attrs.date
      assert charge.charger_phases == @valid_attrs.charger_phases
      assert charge.charger_power == @valid_attrs.charger_power

      assert charge.charge_energy_added ==
               @valid_attrs.charge_energy_added |> Decimal.from_float()

      assert charge.ideal_battery_range_km == Decimal.new("250.00")
    end

    test "with invalid data returns error changeset" do
      car = car_fixture()

      assert {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)

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
      car = car_fixture()
      assert {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)

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
        assert {:ok, %Charge{} = _charge} = Log.insert_charge(cproc, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} = Log.complete_charging_process(cproc)

      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
      assert cproc.charge_energy_added == Decimal.from_float(0.31)
      assert cproc.duration_min == 4
      assert cproc.end_battery_level == 54
      assert cproc.start_battery_level == 50
      assert cproc.start_ideal_range_km == Decimal.new("266.60")
      assert cproc.end_ideal_range_km == Decimal.new("268.60")
      assert cproc.start_rated_range_km == Decimal.new("206.60")
      assert cproc.end_rated_range_km == Decimal.new("208.60")
      assert cproc.outside_temp_avg == Decimal.from_float(15.3)

      Process.sleep(100)

      # calling it a 2nd time won't overwrite the end_date
      assert {:ok, ^cproc} = Log.complete_charging_process(cproc)
    end

    test "closes charging process with zero charges " do
      car = car_fixture()

      assert {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)

      assert {:ok, %ChargingProcess{} = cproc} = Log.complete_charging_process(cproc)
      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
    end

    test "set nil if charge_energy_added is negative" do
      charges = charges_fixture(:negative_energy_added)

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == nil
      assert cproc.charge_energy_used == Decimal.from_float(12.58)
      assert cproc.duration_min == 48
    end

    test "uses max instead of last charge_energy_added if necessary" do
      charges = [
        {"2020-01-22 10:07:44.843", 0, 0, 230.4, 3, 16, 241, "<invalid>"},
        {"2020-01-22 10:08:12.109", 0, 11, 230.4, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:09:36.568", 0.21, 11, 231.4, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:11:01.313", 0.53, 11, 232.4, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:12:25.325", 0.74, 11, 233.4, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:13:51.237", 0.95, 11, 234.9, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:15:16.959", 1.26, 11, 235.8, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:16:40.722", 1.47, 11, 237.3, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:18:05.355", 1.69, 11, 238.3, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:19:30.293", 1.9, 11, 239.3, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:20:53.012", 2.21, 11, 240.3, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:22:15.884", 2.42, 11, 241.8, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:23:39.886", 2.63, 11, 242.8, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:25:03.659", 2.95, 11, 243.8, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:26:26.947", 3.16, 10, 244.7, 3, 14, 238, "<invalid>"},
        {"2020-01-22 10:27:50.703", 3.37, 11, 245.7, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:29:15.39", 3.58, 11, 247.2, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:30:50.514", 3.9, 11, 248.2, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:32:15.901", 4.11, 11, 249.2, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:33:40.844", 4.42, 11, 250.7, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:35:04.851", 4.63, 11, 251.7, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:36:29.838", 4.84, 11, 253.2, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:38:25.125", 5.16, 10, 254.6, 3, 14, 239, "<invalid>"},
        {"2020-01-22 10:39:48.877", 5.37, 11, 255.6, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:41:35.732", 5.69, 11, 256.6, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:43:00.226", 5.9, 11, 257.6, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:44:23.892", 6.21, 11, 259.1, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:45:50.474", 6.42, 11, 260.1, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:47:16.234", 6.64, 11, 261.6, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:48:45.226", 6.95, 11, 262.5, 3, 16, 237, "<invalid>"},
        {"2020-01-22 10:50:10.469", 7.16, 11, 263.5, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:51:34.798", 7.37, 11, 264.5, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:52:58.478", 7.69, 11, 266, 3, 16, 239, "<invalid>"},
        {"2020-01-22 10:54:32.061", 7.9, 10, 267, 3, 14, 239, "<invalid>"},
        {"2020-01-22 10:55:56.615", 8.11, 11, 268, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:57:23.599", 8.43, 11, 269.5, 3, 16, 238, "<invalid>"},
        {"2020-01-22 10:58:47.438", 8.64, 11, 270.5, 3, 16, 239, "<invalid>"},
        {"2020-01-22 11:00:12.74", 8.85, 11, 271.9, 3, 16, 239, "<invalid>"},
        {"2020-01-22 11:01:40.436", 9.16, 11, 272.9, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:03:04.127", 9.37, 11, 273.9, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:04:28.536", 9.58, 11, 274.9, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:05:52.939", 9.79, 11, 275.9, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:07:16.42", 10.01, 11, 277.4, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:08:40.085", 10.32, 11, 278.4, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:10:04.71", 10.53, 11, 279.4, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:11:59.287", 10.85, 11, 280.8, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:13:47.923", 11.16, 11, 282.3, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:15:11.586", 11.37, 11, 283.3, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:16:36.854", 11.59, 11, 284.8, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:18:01.857", 11.9, 11, 285.3, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:19:26.632", 12.11, 11, 286.3, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:20:50.537", 12.32, 11, 287.8, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:23:00.723", 12.64, 11, 289.3, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:24:25.183", 12.95, 11, 290.7, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:25:49.861", 13.16, 11, 291.7, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:27:17.549", 13.38, 11, 292.7, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:28:41.387", 13.59, 11, 293.7, 3, 16, 237, "<invalid>"},
        {"2020-01-22 11:30:08.548", 13.9, 11, 294.7, 3, 16, 237, "<invalid>"},
        {"2020-01-22 11:31:40.833", 14.11, 11, 296.2, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:33:06.332", 14.43, 11, 297.2, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:34:46.017", 14.64, 11, 298.6, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:36:26.489", 14.96, 11, 300.1, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:37:08.28", 15.06, 11, 300.6, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:38:32.559", 15.27, 10, 301.6, 3, 14, 237, "<invalid>"},
        {"2020-01-22 11:39:57.376", 15.59, 11, 302.6, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:41:23.626", 15.8, 11, 303.6, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:42:48.114", 16.01, 11, 305.1, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:44:13.379", 16.22, 11, 306.1, 3, 16, 234, "<invalid>"},
        {"2020-01-22 11:45:37.073", 16.54, 11, 307.1, 3, 16, 235, "<invalid>"},
        {"2020-01-22 11:46:40.012", 16.64, 11, 308, 3, 16, 236, "<invalid>"},
        {"2020-01-22 11:47:01.369", 0, 0, 308, nil, 16, 1, "<invalid>"}
      ]

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(16.64)
      assert cproc.charge_energy_used == Decimal.from_float(18.59)
      assert cproc.duration_min == 99
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
        Log.start_charging_process(car, %{
          date: DateTime.utc_now(),
          latitude: 50.112198,
          longitude: 11.597669
        })

      for c <- charges, do: {:ok, %Charge{}} = Log.insert_charge(cproc, c)

      assert {:ok, %ChargingProcess{geofence_id: ^id}} = Log.complete_charging_process(cproc)
    end

    test "calculates the charge costs based on the price per kwh" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: 0.25,
                 billing_type: :per_kwh
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.cost == Decimal.from_float(3.19)
    end

    test "calculates the charge costs based on the price per minute" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: 0.33,
                 billing_type: :per_minute
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.duration_min == 19
      assert cproc.cost == Decimal.from_float(6.27)
    end

    test "calculates the charge costs based on the session fee" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 session_fee: 7.00
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.cost == Decimal.new("7.00")
    end

    test "calculates the charge costs based on the session fee and energy used" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: 0.25,
                 session_fee: 4.79
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.cost == Decimal.from_float(7.98)
    end

    test "fees can be zero" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: 0.0,
                 session_fee: 0.0
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:negative_energy_added),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == nil
      assert cproc.charge_energy_used == Decimal.from_float(12.58)
      assert cproc.cost == Decimal.new("0.00")
    end

    test "cost per unit can be negative" do
      car = car_fixture()

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: -0.15,
                 session_fee: 0.0
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.cost == Decimal.new("-1.92")
    end

    test "sets charge cost to zero if free supercharging is enabled" do
      alias TeslaMate.Settings

      car = car_fixture()

      {:ok, _} =
        car
        |> Settings.get_car_settings!()
        |> Settings.update_car_settings(%{free_supercharging: true})

      assert %GeoFence{id: _id} =
               geofence_fixture(%{
                 latitude: 50.1121,
                 longitude: 11.597,
                 radius: 50,
                 cost_per_unit: 0.33
               })

      assert {:ok, cproc} =
               log_charging_process(charges_fixture(:phases_nil, "Tesla"),
                 car: car,
                 attrs: %{
                   date: DateTime.utc_now(),
                   latitude: 50.112198,
                   longitude: 11.597669
                 }
               )

      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.cost == Decimal.new("0.00")
    end
  end

  describe "efficiency factor" do
    test "recalculates the efficiency factor after completing a charging session" do
      alias TeslaMate.Settings

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

      assert %Car{efficiency: nil} = car_0 = car_fixture(eid: 3_453, vid: 3240, vin: "slkf")
      assert %Car{efficiency: nil} = car_1 = car_fixture(eid: 3_904, vid: 9403, vin: "salk")

      for {range, car} <- [{:ideal, car_0}, {:rated, car_1}] do
        {:ok, _} =
          Settings.get_global_settings!()
          |> Settings.update_global_settings(%{preferred_range: range})

        :ok = insert_charging_process_fixtures(car, data, range)

        assert %Car{efficiency: 0.152} = Log.get_car!(car.id)
      end
    end

    test "makes an estimate with up to 4 decimal places" do
      assert %Car{efficiency: nil} = car = car_fixture()

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

      :ok = insert_charging_process_fixtures(car, data)

      assert %Car{efficiency: 0.1522} = Log.get_car!(car.id)
    end

    test "makes a rough estimate starting at two values" do
      ## 2x
      assert %Car{efficiency: nil} = car = car_fixture(eid: 666, vid: 667, vin: "668")

      data = [
        {283.1, 353.9, 10.57, 57, 71, 60}
      ]

      :ok = insert_charging_process_fixtures(car, data)

      assert %Car{efficiency: nil} = Log.get_car!(car.id)

      ## 3x

      assert %Car{efficiency: nil} = car = car_fixture(eid: 886, vid: 887, vin: "888")

      data = [
        {283.1, 353.9, 10.57, 57, 71, 60},
        {259.7, 426.2, 25.56, 52, 85, 36}
      ]

      :ok = insert_charging_process_fixtures(car, data)

      assert %Car{efficiency: 0.15} = Log.get_car!(car.id)
    end

    test "handles NULL" do
      assert %Car{efficiency: nil} = car = car_fixture()

      data = [
        {262.8, 263.5, 0.0, 53, 53, 0},
        {176.8, 177.5, 0.0, 35, 36, 3},
        {294.6, 294.6, 0.0, 59, 59, 0}
      ]

      :ok = insert_charging_process_fixtures(car, data)

      assert %Car{efficiency: nil} = Log.get_car!(car.id)
    end

    test "rejects zero" do
      assert %Car{efficiency: nil} = car = car_fixture()

      data = [
        {262.8, 263.5, 0.0, 53, 53, 20},
        {176.8, 177.5, 0.0, 35, 36, 20},
        {294.6, 294.6, 0.0, 59, 59, 45}
      ]

      :ok = insert_charging_process_fixtures(car, data)

      assert %Car{efficiency: nil} = Log.get_car!(car.id)
    end

    defp insert_charging_process_fixtures(car, data, range \\ :rated) do
      {:ok, %Position{id: position_id}} = Log.insert_position(car, @valid_pos_attrs)

      {start_range, end_range} =
        case range do
          :ideal -> {:start_ideal_range_km, :end_ideal_range_km}
          :rated -> {:start_rated_range_km, :end_rated_range_km}
        end

      data =
        for {sr, er, ca, sl, el, d} <- data do
          %{
            car_id: car.id,
            start_date: DateTime.utc_now(),
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

      {:ok, cproc} = Log.start_charging_process(car, @valid_pos_attrs)

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
      charges = charges_fixture(:phases_nil)

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(12.77)
      assert cproc.charge_energy_used == Decimal.from_float(12.46)
      assert cproc.duration_min == 19
      assert cproc.start_ideal_range_km == Decimal.new("235.90")
      assert cproc.end_ideal_range_km == Decimal.new("320.50")
    end

    test "calculates the energy used with phase correction" do
      charges = charges_fixture(:phase_correction_2_to_3)
      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(1.68)
      assert cproc.charge_energy_used == Decimal.from_float(1.78)
      assert cproc.duration_min == 13
      assert cproc.start_ideal_range_km == Decimal.new("288.90")
      assert cproc.end_ideal_range_km == Decimal.new("299.90")

      charges = charges_fixture(:phase_correction_2_to_1)
      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(12.64)
      assert cproc.charge_energy_used == Decimal.from_float(14.76)
      assert cproc.duration_min == 640
      assert cproc.start_ideal_range_km == Decimal.new("180.10")
      assert cproc.end_ideal_range_km == Decimal.new("262.50")
    end

    test "calculates the energy used with voltage correction" do
      charges = charges_fixture(:voltage_correction_220_to_127_p1)
      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(8.48)
      assert cproc.charge_energy_used == Decimal.from_float(8.92)
      assert cproc.duration_min == 74
      assert cproc.start_ideal_range_km == Decimal.new("384.60")
      assert cproc.end_ideal_range_km == Decimal.new("440.30")

      charges = charges_fixture(:voltage_correction_220_to_127_p2)
      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.new("38.44")
      assert cproc.charge_energy_used == Decimal.new("40.70")
      assert cproc.duration_min == 330
      assert cproc.start_ideal_range_km == Decimal.new("189.20")
      assert cproc.end_ideal_range_km == Decimal.new("441.70")
    end

    test "handles a bad connection" do
      charges =
        charges_fixture(:phases_nil)
        |> Enum.with_index()
        |> Enum.filter(fn {_, i} -> rem(i, 3) == 0 end)
        |> Enum.map(fn {c, _} -> c end)

      assert {:ok, cproc} = log_charging_process(charges)
      assert cproc.charge_energy_added == Decimal.from_float(12.67)
      assert cproc.charge_energy_used == Decimal.from_float(12.45)
      assert cproc.duration_min == 18
      assert cproc.start_ideal_range_km == Decimal.new("235.90")
      assert cproc.end_ideal_range_km == Decimal.new("319.80")
    end

    test "handles data gaps" do
      {c1, c2} = charges_fixture(:phases_nil) |> Enum.split(100)

      charges =
        c1 ++
          Enum.map(c2, fn {date, added, _, _, _, _, _, _} = data ->
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
      assert cproc.charge_energy_added == Decimal.from_float(13.77)
      assert cproc.charge_energy_used == Decimal.from_float(13.82)
      assert cproc.duration_min == 21
    end

    defp charges_fixture(fixture, fast_charger_type \\ "<invalid>")

    defp charges_fixture(:phases_nil, fast_charger_type) do
      [
        {"2019-10-24 06:43:48.022", 0, -1, 235.9, nil, 0, 1, "<invalid>"},
        {"2019-10-24 06:43:53.806", 0, -1, 236.6, nil, 0, 1, "<invalid>"},
        {"2019-10-24 06:43:59.474", 0, 43, 235.9, nil, 0, 1, "<invalid>"},
        {"2019-10-24 06:44:05.025", 0, 41, 236.6, nil, 0, 1, "<invalid>"},
        {"2019-10-24 06:44:10.538", 0.1, 41, 237.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:16.098", 0.1, 40, 237.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:21.755", 0.1, 40, 237.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:27.265", 0.21, 40, 238, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:32.821", 0.21, 40, 238, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:38.338", 0.31, 39, 238.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:43.858", 0.42, 40, 239.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:49.63", 0.52, 41, 240, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:44:55.11", 0.63, 40, 240.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:00.585", 0.63, 40, 240.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:06.106", 0.63, 40, 240.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:11.625", 0.73, 40, 241.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:17.145", 0.73, 41, 241.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:22.666", 0.84, 41, 242.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:28.33", 1.04, 40, 243.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:33.857", 1.04, 40, 243.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:39.384", 1.05, 40, 243.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:44.899", 1.15, 40, 244.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:50.425", 1.15, 40, 244.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:45:56.023", 1.26, 41, 244.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:01.543", 1.36, 41, 245.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:07.057", 1.36, 40, 245.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:12.581", 1.57, 40, 245.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:18.06", 1.57, 40, 246.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:23.698", 1.47, 40, 246.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:29.219", 1.68, 40, 247.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:34.736", 1.67, 40, 247.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:40.278", 1.78, 40, 248.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:45.733", 1.88, 41, 248.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:51.181", 1.88, 40, 248.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:46:56.662", 1.88, 40, 248.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:02.179", 1.99, 40, 249.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:07.67", 1.99, 40, 249.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:13.225", 2.2, 41, 251, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:18.737", 2.3, 41, 251.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:24.257", 2.3, 40, 251.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:29.802", 2.3, 40, 251.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:35.299", 2.41, 40, 252.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:40.826", 2.41, 40, 252.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:46.337", 2.51, 41, 253.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:51.802", 2.72, 40, 253.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:47:57.295", 2.72, 40, 254.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:02.766", 2.72, 40, 254.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:08.256", 2.83, 40, 255.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:14.425", 2.83, 40, 255.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:20.012", 2.93, 40, 255.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:25.619", 3.04, 40, 256.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:31.138", 3.04, 40, 256.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:36.657", 3.14, 40, 257.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:42.179", 3.25, 40, 257.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:47.701", 3.25, 41, 257.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:53.3", 3.35, 40, 258.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:48:58.824", 3.46, 40, 258.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:04.358", 3.46, 40, 259.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:09.938", 3.46, 40, 259.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:15.548", 3.66, 40, 260.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:21.058", 3.66, 40, 260.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:26.531", 3.77, 40, 261.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:32.273", 3.87, 41, 262, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:37.78", 3.87, 40, 262, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:43.298", 3.87, 40, 262, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:48.826", 3.98, 40, 262.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:54.358", 3.98, 40, 262.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:49:59.961", 4.08, 41, 263.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:05.49", 4.29, 40, 263.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:11.098", 4.29, 40, 264.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:16.591", 4.29, 40, 264.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:22.12", 4.4, 40, 265.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:27.631", 4.4, 40, 265.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:33.227", 4.5, 41, 266.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:38.739", 4.71, 40, 266.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:44.263", 4.71, 40, 267.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:49.949", 4.61, 40, 266.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:50:55.474", 4.82, 40, 268.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:00.991", 4.82, 41, 268.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:06.501", 4.92, 41, 268.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:12.027", 4.92, 40, 268.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:17.54", 5.03, 40, 269.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:23.071", 5.03, 41, 269.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:28.669", 5.24, 41, 271, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:34.19", 5.24, 40, 271, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:39.941", 5.24, 40, 271, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:45.467", 5.34, 40, 271.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:50.982", 5.44, 40, 272.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:51:56.503", 5.44, 41, 272.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:02.027", 5.55, 40, 273, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:07.541", 5.55, 40, 273, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:13.308", 5.55, 40, 273, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:18.899", 5.76, 41, 274.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:24.422", 5.86, 41, 275.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:29.94", 5.86, 40, 275.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:35.385", 5.86, 40, 275.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:40.898", 5.97, 40, 275.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:46.42", 5.97, 40, 275.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:52.025", 6.07, 40, 276.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:52:57.548", 6.28, 41, 277.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:03.22", 6.28, 41, 277.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:08.666", 6.28, 41, 277.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:14.162", 6.39, 41, 278.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:19.61", 6.49, 40, 279.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:25.62", 6.49, 41, 279.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:31.221", 6.59, 41, 279.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:36.662", 6.59, 40, 279.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:42.182", 6.59, 40, 279.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:47.86", 6.8, 40, 280.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:53.378", 6.91, 40, 282, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:53:58.91", 6.91, 40, 282, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:04.497", 6.91, 41, 282, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:10.034", 7.01, 41, 282.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:15.548", 7.01, 41, 282.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:21.086", 7.12, 41, 283.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:26.578", 7.22, 41, 283.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:32.156", 7.22, 40, 284, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:37.67", 7.22, 41, 284, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:43.291", 7.43, 41, 285.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:48.758", 7.54, 41, 286.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:54.25", 7.54, 41, 286.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:54:59.778", 7.54, 40, 286.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:05.299", 7.64, 41, 286.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:10.901", 7.64, 41, 286.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:16.42", 7.75, 40, 287.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:21.939", 7.75, 41, 287.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:27.461", 7.96, 41, 288.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:32.984", 7.95, 40, 288.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:38.5", 8.06, 41, 289.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:44.024", 8.16, 41, 290.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:49.498", 8.16, 41, 290.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:55:55.464", 8.16, 40, 290.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:00.982", 8.27, 41, 290.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:06.495", 8.48, 40, 292.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:12.022", 8.48, 41, 292.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:17.563", 8.48, 41, 292.3, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:56:23.143", 8.58, 41, 293, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:28.664", 8.58, 41, 293, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:34.188", 8.69, 41, 293.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:39.789", 8.69, 41, 293.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:45.305", 8.9, 41, 295, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:50.821", 8.9, 41, 294.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:56:56.423", 9, 41, 295.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:02.023", 9.11, 41, 296.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:07.544", 9.11, 41, 296.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:13.059", 9.11, 41, 296.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:18.659", 9.21, 41, 297.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:24.105", 9.42, 41, 297.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:30.26", 9.42, 41, 298.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:35.859", 9.32, 41, 297.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:41.379", 9.53, 41, 299.2, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:57:46.898", 9.53, 41, 299.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:57:52.419", 9.63, 41, 299.9, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:57:57.949", 9.63, 41, 299.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:03.545", 9.74, 41, 300.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:09.059", 9.74, 41, 300.6, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:58:14.66", 9.94, 41, 301.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:20.102", 9.95, 41, 301.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:25.597", 10.05, 41, 301.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:31.302", 10.05, 41, 302.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:36.823", 10.15, 41, 303.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:42.26", 10.26, 41, 303.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:47.782", 10.26, 41, 304, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:58:53.239", 10.26, 41, 304, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:58:58.719", 10.47, 41, 305.4, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:59:04.252", 10.57, 41, 304.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:09.785", 10.57, 41, 306, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:59:15.422", 10.57, 41, 306, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:20.907", 10.68, 41, 306.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:26.421", 10.78, 41, 306.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:31.939", 10.78, 41, 307.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:37.422", 10.78, 41, 307.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:42.979", 10.89, 41, 307.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:48.59", 10.99, 41, 308.8, nil, 0, 2, fast_charger_type},
        {"2019-10-24 06:59:54.109", 10.99, 41, 308.8, nil, 0, 1, fast_charger_type},
        {"2019-10-24 06:59:59.625", 11.1, 41, 309.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:05.3", 11.2, 40, 309.5, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:10.821", 11.2, 40, 310.2, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:17.875", 11.31, 41, 310.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:26.183", 11.41, 41, 310.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:32.1", 11.41, 41, 311.6, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:00:38.35", 11.41, 40, 311.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:43.818", 11.62, 40, 312.9, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:00:49.286", 11.73, 40, 312.9, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:00:54.772", 11.73, 40, 313.6, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:01:00.459", 11.73, 40, 313.6, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:05.963", 11.83, 40, 314.3, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:14.562", 12.04, 40, 315.7, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:20.426", 11.94, 40, 315, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:26.025", 12.15, 40, 315, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:31.633", 12.25, 40, 316.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:37.14", 12.25, 41, 317.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:42.602", 12.25, 41, 317.1, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:01:48.099", 12.35, 41, 317.1, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:01:53.78", 12.46, 41, 317.7, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:01:59.309", 12.56, 40, 318.4, nil, 0, 1, fast_charger_type},
        {"2019-10-24 07:02:04.822", 12.56, 40, 318.4, nil, 0, 2, fast_charger_type},
        {"2019-10-24 07:02:10.34", 12.67, 40, 319.1, nil, 0, 1, "<invalid>"},
        {"2019-10-24 07:02:15.861", 12.67, 40, 319.8, nil, 0, 2, "<invalid>"},
        {"2019-10-24 07:02:21.326", 12.77, 40, 320.5, nil, 0, 2, "<invalid>"}
      ]
    end

    defp charges_fixture(:phase_correction_2_to_3, _fast_charger_type) do
      [
        {"2019-10-19 18:26:44", 0, 0, 288.9, 2, 0, 233, "<invalid>"},
        {"2019-10-19 18:26:50", 0, 0, 288.9, 2, 2, 234, "<invalid>"},
        {"2019-10-19 18:26:56", 0, 2, 288.9, 2, 5, 234, "<invalid>"},
        {"2019-10-19 18:27:02", 0, 4, 288.9, 2, 8, 235, "<invalid>"},
        {"2019-10-19 18:27:07", 0, 8, 288.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:27:13", 0, 8, 288.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:18", 0, 8, 288.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:27:24", 0, 8, 288.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:27:30", 0, 8, 288.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:35", 0, 8, 288.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:41", 0.1, 8, 289.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:46", 0.1, 8, 289.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:52", 0.1, 8, 289.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:27:57", 0.1, 8, 289.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:03", 0.1, 8, 289.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:28:09", 0.1, 8, 289.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:15", 0.1, 8, 289.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:20", 0.1, 8, 289.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:26", 0.1, 8, 289.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:28:31", 0.1, 8, 289.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:37", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:43", 0.21, 8, 290.3, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:28:48", 0.21, 8, 290.3, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:28:54", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:28:59", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:05", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:11", 0.21, 8, 290.3, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:29:16", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:22", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:28", 0.21, 8, 290.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:33", 0.42, 8, 291.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:29:39", 0.42, 8, 291.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:29:44", 0.42, 8, 291.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:29:50", 0.42, 8, 291.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:29:56", 0.42, 8, 291.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:01", 0.42, 8, 291.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:30:07", 0.42, 8, 291.6, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:30:12", 0.42, 8, 291.6, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:18", 0.31, 8, 290.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:24", 0.31, 8, 290.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:30:29", 0.31, 8, 290.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:35", 0.52, 8, 292.3, 2, 12, 229, "<invalid>"},
        {"2019-10-19 18:30:41", 0.52, 8, 292.3, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:30:46", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:52", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:30:58", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:31:03", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:31:09", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:31:15", 0.52, 8, 292.3, 2, 12, 229, "<invalid>"},
        {"2019-10-19 18:31:20", 0.52, 8, 292.3, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:31:26", 0.52, 8, 292.3, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:31:32", 0.63, 8, 293, 2, 12, 229, "<invalid>"},
        {"2019-10-19 18:31:37", 0.63, 8, 293, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:31:43", 0.63, 8, 293, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:31:49", 0.63, 8, 293, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:31:55", 0.63, 8, 293, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:32:00", 0.63, 8, 293, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:06", 0.63, 8, 293, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:32:12", 0.63, 8, 293, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:32:17", 0.63, 8, 293, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:23", 0.63, 8, 293, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:28", 0.73, 8, 293.7, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:32:34", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:40", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:46", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:32:51", 0.73, 8, 293.7, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:32:57", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:03", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:08", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:14", 0.73, 8, 293.7, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:33:20", 0.73, 8, 293.7, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:25", 0.94, 8, 295.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:31", 0.84, 8, 294.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:37", 0.84, 8, 294.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:42", 0.94, 8, 295.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:48", 0.94, 8, 295.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:54", 0.94, 8, 295.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:33:59", 0.84, 8, 294.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:34:05", 0.84, 8, 294.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:34:11", 0.84, 8, 295.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:34:16", 1.05, 8, 295.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:34:22", 1.05, 8, 295.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:34:28", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:34:33", 1.05, 8, 295.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:34:39", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:34:45", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:34:50", 1.05, 8, 295.8, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:34:56", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:02", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:07", 1.05, 8, 295.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:13", 1.15, 8, 296.4, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:35:18", 1.15, 8, 296.4, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:35:24", 1.15, 8, 296.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:30", 1.15, 8, 296.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:36", 1.15, 8, 296.4, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:35:41", 1.15, 8, 296.4, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:35:47", 1.15, 8, 296.4, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:35:52", 1.15, 8, 296.4, 2, 12, 233, "<invalid>"},
        {"2019-10-19 18:35:58", 1.15, 8, 296.4, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:36:04", 1.15, 8, 296.4, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:36:10", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:16", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:21", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:27", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:33", 1.26, 8, 297.1, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:36:38", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:44", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:49", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:36:55", 1.26, 8, 297.1, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:37:01", 1.26, 8, 297.1, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:06", 1.47, 8, 298.5, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:12", 1.36, 8, 297.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:18", 1.36, 8, 297.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:37:24", 1.36, 8, 297.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:29", 1.47, 8, 298.5, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:35", 1.47, 8, 298.5, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:40", 1.36, 8, 297.8, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:37:46", 1.36, 8, 297.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:51", 1.36, 8, 297.8, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:37:57", 1.47, 8, 298.5, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:03", 1.57, 8, 299.2, 2, 12, 229, "<invalid>"},
        {"2019-10-19 18:38:08", 1.57, 8, 299.2, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:14", 1.57, 8, 299.2, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:19", 1.57, 8, 299.2, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:25", 1.57, 8, 299.2, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:38:31", 1.57, 8, 299.2, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:38:36", 1.57, 8, 299.2, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:42", 1.57, 8, 299.2, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:38:48", 1.57, 8, 299.2, 2, 12, 233, "<invalid>"},
        {"2019-10-19 18:38:53", 1.57, 8, 299.2, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:38:59", 1.68, 8, 299.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:39:05", 1.68, 8, 299.9, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:39:10", 1.68, 8, 299.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:39:16", 1.68, 8, 299.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:39:21", 1.68, 8, 299.9, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:39:27", 1.68, 8, 299.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:39:33", 1.68, 8, 299.9, 2, 12, 230, "<invalid>"},
        {"2019-10-19 18:39:38", 1.68, 8, 299.9, 2, 12, 231, "<invalid>"},
        {"2019-10-19 18:39:44", 1.68, 8, 299.9, 2, 12, 232, "<invalid>"},
        {"2019-10-19 18:39:49", 1.68, 0, 299.9, nil, 0, 6, 4, "<invalid>"}
      ]
    end

    defp charges_fixture(:phase_correction_2_to_1, _fast_charger_type) do
      [
        {"2019-06-15 09:28:19", 0.51, 2, 180.8, 2, 9, 224, "<invalid>"},
        {"2019-06-15 09:29:51", 0.51, 2, 180.8, 2, 9, 224, "<invalid>"},
        {"2019-06-15 09:23:43", 0.41, 2, 180.1, 2, 9, 223, "<invalid>"},
        {"2019-06-15 09:26:16", 0.51, 2, 180.1, 2, 9, 221, "<invalid>"},
        {"2019-06-15 09:35:28", 0.71, 2, 181.5, 2, 9, 223, "<invalid>"},
        {"2019-06-15 09:41:36", 0.92, 2, 183.5, 2, 9, 223, "<invalid>"},
        {"2019-06-15 09:45:43", 1.02, 2, 184.2, 2, 9, 225, "<invalid>"},
        {"2019-06-15 09:49:49", 1.12, 2, 184.8, 2, 9, 224, "<invalid>"},
        {"2019-06-15 09:53:55", 1.22, 2, 185.5, 2, 9, 225, "<invalid>"},
        {"2019-06-15 09:58:01", 1.43, 2, 186.8, 2, 9, 226, "<invalid>"},
        {"2019-06-15 10:14:27", 1.94, 2, 189.5, 2, 9, 223, "<invalid>"},
        {"2019-06-15 11:15:50", 2.96, 1, 196.2, 2, 5, 228, "<invalid>"},
        {"2019-06-15 10:07:48", 1.63, 2, 188.2, 2, 9, 224, "<invalid>"},
        {"2019-06-15 11:08:40", 2.75, 1, 194.9, 2, 5, 228, "<invalid>"},
        {"2019-06-15 10:01:36", 1.53, 2, 186.8, 2, 9, 226, "<invalid>"},
        {"2019-06-15 11:02:30", 2.65, 1, 194.9, 2, 5, 228, "<invalid>"},
        {"2019-06-15 10:02:07", 1.53, 2, 187.5, 2, 9, 223, "<invalid>"},
        {"2019-06-15 10:56:21", 2.55, 1, 194.2, 2, 5, 231, "<invalid>"},
        {"2019-06-15 12:01:27", 3.57, 1, 200.9, 2, 5, 229, "<invalid>"},
        {"2019-06-15 11:03:02", 2.65, 1, 194.9, 2, 5, 227, "<invalid>"},
        {"2019-06-15 12:01:58", 3.57, 1, 200.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 10:57:22", 2.65, 1, 194.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 11:55:48", 3.57, 1, 200.2, 2, 5, 228, "<invalid>"},
        {"2019-06-15 10:50:13", 2.55, 1, 193.5, 2, 5, 231, "<invalid>"},
        {"2019-06-15 11:56:19", 3.57, 1, 200.2, 2, 5, 229, "<invalid>"},
        {"2019-06-15 10:50:44", 2.55, 1, 193.5, 2, 5, 231, "<invalid>"},
        {"2019-06-15 11:56:50", 3.57, 1, 200.2, 2, 5, 229, "<invalid>"},
        {"2019-06-15 10:51:14", 2.55, 1, 193.5, 2, 5, 231, "<invalid>"},
        {"2019-06-15 11:57:21", 3.57, 1, 200.2, 2, 5, 228, "<invalid>"},
        {"2019-06-15 10:58:55", 2.65, 1, 194.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 12:04:31", 3.67, 1, 200.9, 2, 6, 227, "<invalid>"},
        {"2019-06-15 10:59:25", 2.65, 1, 194.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 12:05:01", 3.67, 1, 200.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 10:53:17", 2.55, 1, 194.2, 2, 5, 231, "<invalid>"},
        {"2019-06-15 11:58:54", 3.57, 1, 200.9, 2, 5, 229, "<invalid>"},
        {"2019-06-15 10:53:48", 2.55, 1, 194.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 11:52:12", 3.47, 1, 200.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 10:52:46", 2.55, 1, 194.2, 2, 5, 229, "<invalid>"},
        {"2019-06-15 11:51:11", 3.47, 1, 200.2, 2, 5, 230, "<invalid>"},
        {"2019-06-15 10:46:39", 2.45, 1, 193.5, 2, 5, 228, "<invalid>"},
        {"2019-06-15 11:45:03", 3.26, 1, 198.9, 2, 5, 230, "<invalid>"},
        {"2019-06-15 12:08:36", 3.67, 1, 201.6, 2, 6, 227, "<invalid>"},
        {"2019-06-15 12:12:42", 3.87, 1, 202.9, 2, 6, 229, "<invalid>"},
        {"2019-06-15 12:16:47", 3.98, 1, 202.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 12:20:52", 3.98, 1, 203.6, 2, 6, 229, "<invalid>"},
        {"2019-06-15 12:51:38", 4.59, 1, 207.6, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:51:03", 5.71, 1, 215, 2, 6, 226, "<invalid>"},
        {"2019-06-15 12:23:25", 4.08, 1, 203.6, 2, 6, 229, "<invalid>"},
        {"2019-06-15 13:29:02", 5.4, 1, 211.6, 2, 6, 226, "<invalid>"},
        {"2019-06-15 14:29:30", 6.52, 1, 219, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:00:21", 4.69, 1, 208.3, 2, 6, 227, "<invalid>"},
        {"2019-06-15 13:56:09", 5.81, 1, 215, 2, 6, 226, "<invalid>"},
        {"2019-06-15 12:39:21", 4.28, 1, 205.6, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:45:55", 5.61, 1, 214.3, 2, 6, 227, "<invalid>"},
        {"2019-06-15 12:24:59", 4.08, 1, 203.6, 2, 6, 227, "<invalid>"},
        {"2019-06-15 13:24:24", 5.2, 1, 210.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 14:17:12", 6.22, 1, 218.3, 2, 6, 229, "<invalid>"},
        {"2019-06-15 12:54:43", 4.59, 1, 207.6, 2, 6, 227, "<invalid>"},
        {"2019-06-15 13:54:07", 5.71, 1, 215, 2, 6, 228, "<invalid>"},
        {"2019-06-15 12:33:42", 4.18, 1, 204.9, 2, 6, 230, "<invalid>"},
        {"2019-06-15 13:39:47", 5.51, 1, 213.6, 2, 6, 228, "<invalid>"},
        {"2019-06-15 14:32:34", 6.52, 1, 220.3, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:02:54", 4.89, 1, 208.3, 2, 6, 225, "<invalid>"},
        {"2019-06-15 13:58:12", 5.81, 1, 215.6, 2, 6, 227, "<invalid>"},
        {"2019-06-15 12:27:02", 4.08, 1, 204.2, 2, 6, 229, "<invalid>"},
        {"2019-06-15 13:25:57", 5.2, 1, 211.6, 2, 6, 226, "<invalid>"},
        {"2019-06-15 14:26:25", 6.32, 1, 219, 2, 6, 230, "<invalid>"},
        {"2019-06-15 13:03:56", 4.89, 1, 208.3, 2, 6, 226, "<invalid>"},
        {"2019-06-15 14:06:23", 6.01, 1, 217, 2, 6, 229, "<invalid>"},
        {"2019-06-15 12:42:56", 4.49, 1, 206.3, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:59:44", 5.81, 1, 215.6, 2, 6, 225, "<invalid>"},
        {"2019-06-15 12:43:26", 4.49, 1, 205.6, 2, 6, 230, "<invalid>"},
        {"2019-06-15 13:42:20", 5.61, 1, 213.6, 2, 6, 228, "<invalid>"},
        {"2019-06-15 12:36:46", 4.38, 1, 204.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 13:35:09", 5.51, 1, 212.9, 2, 6, 228, "<invalid>"},
        {"2019-06-15 14:27:58", 6.52, 1, 219.6, 2, 6, 229, "<invalid>"},
        {"2019-06-15 13:13:39", 5, 1, 210.3, 2, 6, 229, "<invalid>"},
        {"2019-06-15 14:28:28", 6.52, 1, 219, 2, 6, 229, "<invalid>"},
        {"2019-06-15 13:15:11", 5.1, 1, 210.3, 2, 6, 227, "<invalid>"},
        {"2019-06-15 14:15:40", 6.22, 1, 217.6, 2, 6, 228, "<invalid>"},
        {"2019-06-15 14:48:33", 6.83, 1, 221.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 14:52:38", 6.83, 1, 222.3, 2, 6, 226, "<invalid>"},
        {"2019-06-15 14:56:44", 7.03, 1, 223.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 15:00:49", 7.14, 1, 223.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 15:31:36", 7.65, 1, 227.7, 2, 6, 228, "<invalid>"},
        {"2019-06-15 16:46:08", 9.18, 1, 237.1, 2, 6, 230, "<invalid>"},
        {"2019-06-15 17:43:05", 10.19, 1, 244.4, 2, 6, 231, "<invalid>"},
        {"2019-06-15 16:00:22", 8.26, 1, 231, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:53:49", 9.28, 1, 237.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 15:03:53", 7.14, 1, 224.3, 2, 6, 228, "<invalid>"},
        {"2019-06-15 16:00:52", 8.26, 1, 231, 2, 6, 227, "<invalid>"},
        {"2019-06-15 17:01:31", 9.38, 1, 238.4, 2, 6, 228, "<invalid>"},
        {"2019-06-15 15:12:07", 7.24, 1, 225, 2, 6, 226, "<invalid>"},
        {"2019-06-15 16:15:47", 8.56, 1, 233.7, 2, 6, 228, "<invalid>"},
        {"2019-06-15 17:08:43", 9.58, 1, 240.4, 2, 6, 227, "<invalid>"},
        {"2019-06-15 15:26:58", 7.65, 1, 227, 2, 6, 226, "<invalid>"},
        {"2019-06-15 16:30:07", 8.77, 1, 235, 2, 6, 227, "<invalid>"},
        {"2019-06-15 17:38:28", 10.19, 1, 243.8, 2, 6, 229, "<invalid>"},
        {"2019-06-15 15:55:44", 8.16, 1, 230.4, 2, 6, 227, "<invalid>"},
        {"2019-06-15 17:03:04", 9.48, 1, 239.1, 2, 6, 226, "<invalid>"},
        {"2019-06-15 15:27:59", 7.65, 1, 227, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:24:28", 8.67, 1, 234.4, 2, 6, 228, "<invalid>"},
        {"2019-06-15 17:17:28", 9.68, 1, 241.1, 2, 6, 228, "<invalid>"},
        {"2019-06-15 15:42:23", 7.85, 1, 228.4, 2, 6, 226, "<invalid>"},
        {"2019-06-15 16:49:43", 9.18, 1, 237.7, 2, 6, 228, "<invalid>"},
        {"2019-06-15 15:06:59", 7.24, 1, 224.3, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:03:57", 8.26, 1, 231.7, 2, 6, 226, "<invalid>"},
        {"2019-06-15 16:57:55", 9.28, 1, 238.4, 2, 6, 228, "<invalid>"},
        {"2019-06-15 15:21:51", 7.54, 1, 226.3, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:50:45", 9.18, 1, 237.7, 2, 6, 226, "<invalid>"},
        {"2019-06-15 15:08:00", 7.24, 1, 224.3, 2, 6, 229, "<invalid>"},
        {"2019-06-15 16:04:29", 8.26, 1, 231.7, 2, 6, 226, "<invalid>"},
        {"2019-06-15 16:58:56", 9.38, 1, 238.4, 2, 6, 228, "<invalid>"},
        {"2019-06-15 15:16:13", 7.34, 1, 225, 2, 6, 229, "<invalid>"},
        {"2019-06-15 16:19:52", 8.67, 1, 233.7, 2, 6, 228, "<invalid>"},
        {"2019-06-15 17:34:22", 10.09, 1, 243.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 15:51:39", 8.05, 1, 230.4, 2, 6, 228, "<invalid>"},
        {"2019-06-15 16:52:17", 9.28, 1, 237.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 15:09:33", 7.24, 1, 224.3, 2, 6, 228, "<invalid>"},
        {"2019-06-15 16:06:02", 8.36, 1, 231.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:59:59", 9.38, 1, 238.4, 2, 6, 229, "<invalid>"},
        {"2019-06-15 15:32:38", 7.75, 1, 227.7, 2, 6, 227, "<invalid>"},
        {"2019-06-15 16:41:27", 9.07, 1, 235.7, 2, 6, 229, "<invalid>"},
        {"2019-06-15 17:45:09", 10.3, 1, 244.4, 2, 6, 230, "<invalid>"},
        {"2019-06-15 17:49:14", 10.3, 1, 245.1, 2, 6, 229, "<invalid>"},
        {"2019-06-15 17:53:20", 10.4, 1, 245.1, 2, 6, 231, "<invalid>"},
        {"2019-06-15 17:57:25", 10.6, 1, 245.8, 2, 6, 228, "<invalid>"},
        {"2019-06-15 18:06:46", 10.7, 1, 247.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 19:19:39", 12.13, 1, 257.2, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:14:57", 10.81, 1, 248.5, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:12:56", 12.03, 1, 255.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:08:18", 10.7, 1, 247.8, 2, 6, 232, "<invalid>"},
        {"2019-06-15 19:13:58", 11.93, 1, 255.8, 2, 6, 231, "<invalid>"},
        {"2019-06-15 18:16:29", 10.91, 1, 248.5, 2, 6, 232, "<invalid>"},
        {"2019-06-15 19:21:41", 12.23, 1, 257.2, 2, 6, 231, "<invalid>"},
        {"2019-06-15 18:23:41", 11.11, 1, 249.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 19:22:12", 12.23, 1, 257.2, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:17:01", 10.91, 1, 248.5, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:15:31", 12.13, 1, 255.8, 2, 6, 231, "<invalid>"},
        {"2019-06-15 18:10:21", 10.81, 1, 247.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 19:08:18", 12.03, 1, 255.1, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:04:38", 10.7, 1, 247.1, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:01:38", 11.83, 1, 254.5, 2, 6, 232, "<invalid>"},
        {"2019-06-15 18:05:08", 10.7, 1, 247.1, 2, 6, 229, "<invalid>"},
        {"2019-06-15 19:02:08", 11.83, 1, 254.5, 2, 6, 232, "<invalid>"},
        {"2019-06-15 20:01:11", 12.95, 1, 261.8, 2, 6, 232, "<invalid>"},
        {"2019-06-15 19:04:11", 11.83, 1, 254.5, 2, 6, 230, "<invalid>"},
        {"2019-06-15 20:03:14", 13.05, 1, 262.5, 2, 6, 231, "<invalid>"},
        {"2019-06-15 18:57:01", 11.72, 1, 253.8, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:56:32", 12.85, 1, 261.8, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:58:33", 11.72, 1, 254.5, 2, 6, 230, "<invalid>"},
        {"2019-06-15 19:27:49", 12.34, 1, 257.8, 2, 6, 232, "<invalid>"},
        {"2019-06-15 18:33:55", 11.21, 1, 251.1, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:31:55", 12.34, 1, 258.5, 2, 6, 232, "<invalid>"},
        {"2019-06-15 18:34:25", 11.21, 1, 251.1, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:32:25", 12.34, 1, 258.5, 2, 6, 230, "<invalid>"},
        {"2019-06-15 18:20:05", 11.01, 1, 249.1, 2, 6, 231, "<invalid>"},
        {"2019-06-15 19:25:16", 12.23, 1, 257.8, 2, 6, 231, "<invalid>"},
        {"2019-06-15 20:02:43", 12.95, 1, 262.5, 2, 6, 232, "<invalid>"}
      ]
    end

    # 127/220V three-phase net
    defp charges_fixture(:voltage_correction_220_to_127_p1, _fast_charger_type) do
      [
        {"2019-12-02 21:18:54.708", 0, 0, 384.6, 3, 0, 236, "<invalid>"},
        {"2019-12-02 21:19:22.967", 0, 7, 383.2, 3, 19, 230, "<invalid>"},
        {"2019-12-02 21:20:04.112", 0, 7, 383.9, 3, 19, 229, "<invalid>"},
        {"2019-12-02 21:20:46.253", 0.1, 7, 385.3, 3, 19, 227, "<invalid>"},
        {"2019-12-02 21:21:27.86", 0.1, 7, 385.3, 3, 19, 228, "<invalid>"},
        {"2019-12-02 21:22:09.022", 0.21, 7, 386, 3, 19, 228, "<invalid>"},
        {"2019-12-02 21:22:51.276", 0.31, 7, 386.7, 3, 19, 230, "<invalid>"},
        {"2019-12-02 21:23:32.805", 0.31, 7, 386.7, 3, 19, 229, "<invalid>"},
        {"2019-12-02 21:24:14.25", 0.52, 7, 388, 3, 19, 228, "<invalid>"},
        {"2019-12-02 21:24:56.097", 0.63, 7, 388.7, 3, 19, 228, "<invalid>"},
        {"2019-12-02 21:25:38.088", 0.63, 7, 388.7, 3, 19, 228, "<invalid>"},
        {"2019-12-02 21:26:19.473", 0.73, 7, 389.4, 3, 19, 230, "<invalid>"},
        {"2019-12-02 21:27:01.547", 0.73, 7, 389.4, 3, 19, 227, "<invalid>"},
        {"2019-12-02 21:27:43.065", 0.84, 7, 390.1, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:28:24.479", 0.94, 7, 390.8, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:29:06.282", 1.05, 7, 391.5, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:29:48.009", 1.15, 7, 392.2, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:30:29.955", 1.15, 7, 392.2, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:31:12.162", 1.26, 7, 392.9, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:31:53.96", 1.36, 7, 393.5, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:32:36.03", 1.36, 7, 393.5, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:33:18.241", 1.47, 7, 394.2, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:34:00.488", 1.68, 7, 395.6, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:34:42.099", 1.68, 7, 395.6, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:35:23.683", 1.78, 7, 396.3, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:36:05.927", 1.89, 7, 397, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:36:48.091", 1.89, 7, 397, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:37:30.408", 1.99, 7, 397.7, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:38:12.724", 2.09, 7, 398.4, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:38:54.008", 2.2, 7, 399.1, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:39:35.848", 2.3, 7, 399.7, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:40:18.089", 2.3, 7, 399.7, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:40:59.779", 2.41, 7, 400.4, 3, 19, 221, "<invalid>"},
        {"2019-12-02 21:41:41.946", 2.41, 7, 400.4, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:42:23.597", 2.62, 7, 401.8, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:43:05.121", 2.72, 7, 402.5, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:43:47.366", 2.72, 7, 402.5, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:44:29.628", 2.83, 7, 403.2, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:45:10.752", 2.83, 7, 403.2, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:45:54.097", 2.93, 7, 403.9, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:46:36.332", 3.04, 7, 404.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:47:18.578", 3.04, 7, 404.6, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:48:00.181", 3.25, 7, 405.9, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:48:41.828", 3.35, 7, 406.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:49:23.454", 3.35, 7, 406.6, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:50:05.092", 3.46, 7, 407.3, 3, 19, 218, "<invalid>"},
        {"2019-12-02 21:50:46.622", 3.46, 7, 407.3, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:51:28.802", 3.67, 7, 408.7, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:52:10.412", 3.77, 7, 409.4, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:54:15.2", 3.98, 7, 410.1, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:52:52.108", 3.77, 7, 409.4, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:56:20.662", 4.08, 7, 411.4, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:54:57.014", 3.98, 7, 410.8, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:55:17.941", 3.98, 7, 410.8, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:55:39.038", 4.19, 7, 412.1, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:57:02.908", 4.29, 7, 412.8, 3, 19, 219, "<invalid>"},
        {"2019-12-02 21:57:44.704", 4.4, 7, 413.5, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:58:26.747", 4.4, 7, 413.5, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:59:08.529", 4.5, 7, 414.2, 3, 19, 220, "<invalid>"},
        {"2019-12-02 21:59:50.195", 4.5, 7, 414.2, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:00:32.164", 4.61, 7, 414.9, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:01:20.166", 4.82, 7, 416.3, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:02:02.669", 4.82, 7, 416.3, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:02:45.921", 4.92, 7, 416.9, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:03:27.83", 5.03, 7, 417.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:04:10.408", 5.03, 7, 417.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:04:52.09", 5.24, 7, 419, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:05:34.258", 5.34, 7, 419.7, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:06:15.861", 5.34, 7, 419.7, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:06:58.087", 5.45, 7, 420.4, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:07:40.541", 5.45, 7, 420.4, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:08:22.578", 5.55, 7, 421.1, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:09:04.802", 5.76, 7, 422.5, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:09:47.723", 5.76, 7, 422.5, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:10:29.288", 5.87, 7, 423.1, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:11:10.881", 5.87, 7, 423.1, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:11:53.484", 5.97, 7, 423.8, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:12:35.582", 6.08, 7, 424.5, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:15:24.338", 6.39, 7, 426.6, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:12:56.16", 6.08, 7, 424.5, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:15:45.445", 6.39, 7, 426.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:13:17.615", 6.08, 7, 424.5, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:17:50.954", 6.6, 7, 428, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:14:42.096", 6.18, 7, 425.2, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:15:03.213", 6.39, 7, 426.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:18:12.036", 6.81, 7, 428, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:18:53.479", 6.81, 7, 429.3, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:19:35.845", 6.91, 7, 430, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:20:18.73", 6.91, 7, 430, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:21:01.831", 7.02, 7, 430.7, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:21:43.867", 7.12, 7, 431.4, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:22:26.091", 7.12, 7, 431.4, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:23:07.861", 7.23, 7, 432.1, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:23:49.034", 7.44, 7, 432.8, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:24:31.533", 7.44, 7, 433.5, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:25:12.794", 7.54, 7, 434.1, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:25:55.351", 7.54, 7, 434.1, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:26:38.247", 7.65, 7, 434.8, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:27:20.476", 7.75, 7, 435.5, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:28:01.806", 7.75, 7, 435.5, 3, 19, 217, "<invalid>"},
        {"2019-12-02 22:28:44.348", 7.96, 7, 436.9, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:29:25.925", 7.96, 7, 436.9, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:29:47.058", 8.07, 7, 437.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:30:07.643", 8.07, 7, 437.6, 3, 19, 219, "<invalid>"},
        {"2019-12-02 22:30:49.205", 8.17, 7, 438.3, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:31:30.782", 8.17, 7, 438.3, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:32:12.345", 8.27, 7, 439, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:32:54.036", 8.38, 7, 439.6, 3, 19, 218, "<invalid>"},
        {"2019-12-02 22:33:14.632", 8.48, 0, 440.3, nil, 0, 1, "<invalid>"}
      ]
    end

    defp charges_fixture(:voltage_correction_220_to_127_p2, _fast_charger_type) do
      [
        {"2019-12-11 20:00:30.611", 0, 7, 189.2, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:03:06.06", 0.21, 7, 190.6, 3, 19, 226, "<invalid>"},
        {"2019-12-11 20:05:54.979", 0.52, 7, 192.7, 3, 19, 225, "<invalid>"},
        {"2019-12-11 20:08:43.586", 0.84, 7, 195.4, 3, 19, 225, "<invalid>"},
        {"2019-12-11 20:20:32.911", 2.2, 7, 203.7, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:36:15.923", 4.19, 7, 216.7, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:48:48.709", 5.55, 7, 225.7, 3, 19, 224, "<invalid>"},
        {"2019-12-11 20:09:25.816", 0.94, 7, 195.4, 3, 19, 225, "<invalid>"},
        {"2019-12-11 20:22:38.203", 2.41, 7, 205, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:38:21.007", 4.4, 7, 218.1, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:50:54.207", 5.87, 7, 227.7, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:09:46.948", 1.05, 7, 196.1, 3, 19, 225, "<invalid>"},
        {"2019-12-11 20:22:59.247", 2.62, 7, 206.4, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:35:13.206", 3.98, 7, 215.3, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:48:07.059", 5.66, 7, 226.4, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:10:07.965", 1.05, 7, 196.1, 3, 19, 225, "<invalid>"},
        {"2019-12-11 20:23:19.796", 2.62, 7, 206.4, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:35:34.331", 3.98, 7, 215.3, 3, 19, 227, "<invalid>"},
        {"2019-12-11 20:54:45.074", 6.39, 7, 231.2, 3, 19, 229, "<invalid>"},
        {"2019-12-11 20:20:12.37", 2.2, 7, 203.7, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:33:05.897", 3.77, 7, 214, 3, 19, 230, "<invalid>"},
        {"2019-12-11 20:47:04.357", 5.45, 7, 225, 3, 19, 228, "<invalid>"},
        {"2019-12-11 20:59:40.253", 6.91, 7, 234.6, 3, 19, 228, "<invalid>"},
        {"2019-12-11 21:04:34.609", 7.54, 7, 238.7, 3, 19, 228, "<invalid>"},
        {"2019-12-11 21:07:21.909", 7.86, 7, 240.8, 3, 19, 230, "<invalid>"},
        {"2019-12-11 21:16:24.458", 9.01, 7, 248.4, 3, 19, 225, "<invalid>"},
        {"2019-12-11 21:32:45.057", 10.79, 7, 260.1, 3, 19, 218, "<invalid>"},
        {"2019-12-11 21:46:20.299", 12.46, 7, 271.1, 3, 19, 217, "<invalid>"},
        {"2019-12-11 22:00:56.484", 14.14, 7, 282.1, 3, 19, 219, "<invalid>"},
        {"2019-12-11 22:14:31.831", 15.71, 7, 292.4, 3, 19, 221, "<invalid>"},
        {"2019-12-11 21:19:53.063", 9.43, 7, 251.1, 3, 19, 225, "<invalid>"},
        {"2019-12-11 21:33:05.576", 10.79, 7, 260.1, 3, 19, 219, "<invalid>"},
        {"2019-12-11 21:48:25.755", 12.67, 7, 272.5, 3, 19, 216, "<invalid>"},
        {"2019-12-11 22:03:01.937", 14.35, 7, 283.5, 3, 19, 221, "<invalid>"},
        {"2019-12-11 21:09:05.967", 8.07, 7, 242.2, 3, 19, 228, "<invalid>"},
        {"2019-12-11 21:21:38.258", 9.53, 7, 251.8, 3, 19, 226, "<invalid>"},
        {"2019-12-11 21:34:49.733", 11.1, 7, 262.1, 3, 19, 219, "<invalid>"},
        {"2019-12-11 21:47:01.509", 12.57, 7, 271.8, 3, 19, 218, "<invalid>"},
        {"2019-12-11 22:01:38.483", 14.14, 7, 282.1, 3, 19, 219, "<invalid>"},
        {"2019-12-11 21:09:27.061", 8.07, 7, 242.2, 3, 19, 227, "<invalid>"},
        {"2019-12-11 21:23:23.003", 9.85, 7, 253.9, 3, 19, 225, "<invalid>"},
        {"2019-12-11 21:37:59.359", 11.52, 7, 264.9, 3, 19, 218, "<invalid>"},
        {"2019-12-11 21:50:51.09", 12.88, 7, 273.8, 3, 19, 219, "<invalid>"},
        {"2019-12-11 22:03:43.516", 14.35, 7, 283.5, 3, 19, 221, "<invalid>"},
        {"2019-12-11 21:12:35.281", 8.48, 7, 244.9, 3, 19, 224, "<invalid>"},
        {"2019-12-11 21:27:12.129", 10.16, 7, 256, 3, 19, 226, "<invalid>"},
        {"2019-12-11 21:41:27.803", 11.84, 7, 267, 3, 19, 218, "<invalid>"},
        {"2019-12-11 21:56:03.068", 13.62, 7, 278.6, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:09:17.682", 14.98, 7, 287.6, 3, 19, 220, "<invalid>"},
        {"2019-12-11 22:16:58.434", 15.92, 7, 293.8, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:22:58.725", 16.65, 7, 298.6, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:35:57.595", 18.23, 7, 308.9, 3, 19, 219, "<invalid>"},
        {"2019-12-11 22:47:50.642", 19.48, 7, 317.2, 3, 19, 219, "<invalid>"},
        {"2019-12-11 23:00:45.599", 20.95, 7, 326.8, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:18:40.807", 23.04, 7, 340.6, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:35:49.403", 24.93, 7, 353, 3, 19, 223, "<invalid>"},
        {"2019-12-11 22:29:19.552", 17.39, 7, 303.4, 3, 19, 220, "<invalid>"},
        {"2019-12-11 22:44:18.708", 19.06, 7, 314.4, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:57:57.935", 20.63, 7, 324.8, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:14:08.435", 22.52, 7, 337.1, 3, 19, 220, "<invalid>"},
        {"2019-12-11 23:27:04.02", 23.88, 7, 346.1, 3, 19, 222, "<invalid>"},
        {"2019-12-11 22:21:55.362", 16.44, 7, 297.2, 3, 19, 219, "<invalid>"},
        {"2019-12-11 22:38:23.606", 18.43, 7, 310.3, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:53:25.912", 20.11, 7, 321.3, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:06:47.865", 21.68, 7, 331.6, 3, 19, 220, "<invalid>"},
        {"2019-12-11 23:19:23.058", 23.15, 7, 341.3, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:31:58.257", 24.61, 7, 350.9, 3, 19, 223, "<invalid>"},
        {"2019-12-11 22:25:48.366", 16.97, 7, 300.7, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:39:05.155", 18.43, 7, 310.3, 3, 19, 220, "<invalid>"},
        {"2019-12-11 22:54:07.703", 20.11, 7, 321.3, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:07:29.837", 21.68, 7, 331.6, 3, 19, 220, "<invalid>"},
        {"2019-12-11 23:20:04.705", 23.15, 7, 341.3, 3, 19, 221, "<invalid>"},
        {"2019-12-11 23:35:28.817", 24.93, 7, 353, 3, 19, 223, "<invalid>"},
        {"2019-12-11 22:33:31.039", 17.81, 7, 306.2, 3, 19, 221, "<invalid>"},
        {"2019-12-11 22:46:04.855", 19.27, 7, 315.8, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:02:53.591", 21.16, 7, 328.2, 3, 19, 220, "<invalid>"},
        {"2019-12-11 23:14:51.046", 22.62, 7, 337.8, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:27:45.449", 24.09, 7, 347.5, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:38:17.199", 25.24, 7, 355, 3, 19, 223, "<invalid>"},
        {"2019-12-11 23:50:53.037", 26.71, 7, 364.6, 3, 19, 223, "<invalid>"},
        {"2019-12-12 00:04:32.158", 28.28, 7, 375, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:18:12.625", 29.96, 7, 386, 3, 19, 225, "<invalid>"},
        {"2019-12-12 00:34:39.496", 31.84, 7, 398.4, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:50:05.071", 33.62, 7, 410.1, 3, 19, 229, "<invalid>"},
        {"2019-12-11 23:38:59.363", 25.35, 7, 355.7, 3, 19, 223, "<invalid>"},
        {"2019-12-11 23:55:48.181", 27.34, 7, 368.8, 3, 19, 222, "<invalid>"},
        {"2019-12-12 00:10:06.316", 28.91, 7, 379.1, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:22:03.708", 30.38, 7, 388.7, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:35:21.754", 31.95, 7, 399.1, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:49:02.862", 33.52, 7, 409.4, 3, 19, 228, "<invalid>"},
        {"2019-12-11 23:40:45.602", 25.45, 7, 356.4, 3, 19, 224, "<invalid>"},
        {"2019-12-11 23:47:23.053", 26.29, 7, 361.9, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:54:44.627", 27.23, 7, 368.1, 3, 19, 224, "<invalid>"},
        {"2019-12-12 00:01:02.897", 27.86, 7, 372.2, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:06:58.75", 28.59, 7, 377, 3, 19, 225, "<invalid>"},
        {"2019-12-12 00:16:05.924", 29.75, 7, 384.6, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:24:09.517", 30.58, 7, 390.1, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:30:27.998", 31.42, 7, 395.6, 3, 19, 228, "<invalid>"},
        {"2019-12-12 00:37:07.362", 32.16, 7, 400.4, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:45:10.563", 33.1, 7, 406.6, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:52:52.653", 34.04, 7, 412.8, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:00:33.433", 34.98, 7, 419, 3, 19, 229, "<invalid>"},
        {"2019-12-11 23:41:06.754", 25.66, 7, 357.8, 3, 19, 224, "<invalid>"},
        {"2019-12-11 23:44:15.528", 25.87, 7, 359.1, 3, 19, 222, "<invalid>"},
        {"2019-12-11 23:47:44.165", 26.29, 7, 361.9, 3, 19, 223, "<invalid>"},
        {"2019-12-11 23:50:32.486", 26.71, 7, 364.6, 3, 19, 224, "<invalid>"},
        {"2019-12-11 23:53:40.587", 27.02, 7, 366.7, 3, 19, 224, "<invalid>"},
        {"2019-12-11 23:57:53.688", 27.44, 7, 369.5, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:01:45.044", 27.97, 7, 372.9, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:05:35.506", 28.39, 7, 375.7, 3, 19, 225, "<invalid>"},
        {"2019-12-12 00:09:04.172", 28.8, 7, 378.4, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:09:45.769", 28.91, 7, 379.1, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:10:47.381", 29.01, 7, 379.8, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:11:07.92", 29.01, 7, 379.8, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:13:38.078", 29.33, 7, 381.8, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:17:51.522", 29.85, 7, 385.3, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:21:42.397", 30.38, 7, 388.7, 3, 19, 226, "<invalid>"},
        {"2019-12-12 00:28:00.806", 31, 7, 392.9, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:35:00.023", 31.95, 7, 399.1, 3, 19, 227, "<invalid>"},
        {"2019-12-12 00:41:19.521", 32.57, 7, 403.2, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:47:17.272", 33.31, 7, 408, 3, 19, 228, "<invalid>"},
        {"2019-12-12 00:53:55.438", 34.15, 7, 413.5, 3, 19, 228, "<invalid>"},
        {"2019-12-12 01:00:12.045", 34.77, 7, 417.6, 3, 19, 228, "<invalid>"},
        {"2019-12-12 01:06:54.883", 35.61, 7, 423.1, 3, 19, 230, "<invalid>"},
        {"2019-12-12 00:26:15.207", 30.9, 7, 392.2, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:32:33.499", 31.53, 7, 396.3, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:39:12.339", 32.26, 7, 401.1, 3, 19, 229, "<invalid>"},
        {"2019-12-12 00:46:56.132", 33.2, 7, 407.3, 3, 19, 230, "<invalid>"},
        {"2019-12-12 00:53:13.756", 34.04, 7, 412.8, 3, 19, 228, "<invalid>"},
        {"2019-12-12 00:59:30.074", 34.77, 7, 417.6, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:06:12.634", 35.61, 7, 423.1, 3, 19, 228, "<invalid>"},
        {"2019-12-12 01:05:51.2", 35.51, 7, 422.5, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:06:33.768", 35.61, 7, 423.1, 3, 19, 231, "<invalid>"},
        {"2019-12-12 01:08:39.832", 35.82, 7, 424.5, 3, 19, 229, "<invalid>"},
        {"2019-12-12 01:10:05.088", 35.93, 7, 425.2, 3, 19, 231, "<invalid>"},
        {"2019-12-12 01:11:28.822", 36.24, 7, 427.3, 3, 19, 229, "<invalid>"},
        {"2019-12-12 01:12:52.623", 36.35, 7, 428, 3, 19, 231, "<invalid>"},
        {"2019-12-12 01:14:17.1", 36.45, 7, 428.6, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:15:40.97", 36.66, 7, 430, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:17:04.812", 36.87, 7, 431.4, 3, 19, 231, "<invalid>"},
        {"2019-12-12 01:18:29.296", 37.08, 7, 432.8, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:19:53.134", 37.18, 7, 433.5, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:21:17.606", 37.39, 7, 434.8, 3, 19, 231, "<invalid>"},
        {"2019-12-12 01:22:40.779", 37.6, 7, 436.2, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:25:29.126", 37.81, 7, 437.6, 3, 19, 229, "<invalid>"},
        {"2019-12-12 01:25:49.702", 37.92, 7, 438.3, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:24:26.386", 37.71, 7, 436.9, 3, 19, 230, "<invalid>"},
        {"2019-12-12 01:30:44.002", 38.44, 7, 441.7, 3, 19, 233, "<invalid>"},
        {"2019-12-12 01:29:19.552", 38.34, 7, 441, 3, 19, 232, "<invalid>"},
        {"2019-12-12 01:28:16.161", 38.23, 7, 440.3, 3, 19, 232, "<invalid>"},
        {"2019-12-12 01:29:40.624", 38.34, 7, 441, 3, 19, 231, "<invalid>"}
      ]
    end

    defp charges_fixture(:negative_energy_added, _fast_charger_type) do
      [
        {"2019-10-25 09:32:52", 29.83, 0, 1607.7, 3, 1, 233, "<invalid>"},
        {"2019-10-25 09:32:59", 29.83, 1, 1607.7, 3, 2, 231, "<invalid>"},
        {"2019-10-25 09:33:31", 29.93, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 09:34:02", 30.04, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:34:32", 30.14, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:35:04", 30.25, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:35:35", 30.46, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:36:07", 30.56, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:36:38", 30.67, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:37:09", 30.77, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:38:26", 31.2, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:39:13", 31.3, 17, 1607.7, 3, 24, 232, "<invalid>"},
        {"2019-10-25 09:39:44", 31.51, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:40:15", 31.62, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:40:47", 31.72, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:41:18", 31.93, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:41:49", 32.04, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:42:21", 32.15, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 09:42:53", 32.25, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:43:24", 32.46, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 09:43:56", 32.57, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:44:27", 32.67, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:44:58", 32.78, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:45:29", 32.99, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:46:00", 33.09, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 09:46:32", 33.2, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:47:02", 33.41, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:47:33", 33.52, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:48:04", 33.62, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:48:35", 33.73, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 09:49:08", 33.83, 17, 1607.7, 3, 24, 232, "<invalid>"},
        {"2019-10-25 09:49:39", 34.04, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:50:10", 34.15, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:50:40", 34.25, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:51:14", 34.46, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:51:45", 34.57, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:52:16", 34.67, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:52:46", 34.78, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:53:19", 34.99, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:53:50", 35.1, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:54:21", 35.2, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:54:51", 35.31, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:55:24", 35.52, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:55:55", 35.62, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 09:56:26", 35.73, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:56:57", 35.83, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:57:28", 35.94, 17, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 09:58:00", 36.15, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:58:30", 36.26, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 09:59:01", 36.36, 17, 1607.7, 3, 24, 232, "<invalid>"},
        {"2019-10-25 09:59:33", 36.57, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:00:04", 36.68, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 10:00:37", 36.78, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 10:01:09", 36.89, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:01:40", 37.1, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:02:11", 37.2, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:02:42", 37.31, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:03:14", 37.52, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:03:45", 37.63, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 10:04:16", 37.73, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:04:47", 37.84, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:05:18", 0, 0, 1607.7, 3, 0, 233, "<invalid>"},
        {"2019-10-25 10:05:33", 0.11, 13, 1607.7, 3, 19, 232, "<invalid>"},
        {"2019-10-25 10:06:04", 0.21, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:06:37", 0.32, 17, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:07:08", 0.42, 17, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:07:39", 0.53, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:08:10", 0.74, 0, 1607.7, nil, 0, 1, "<invalid>"},
        {"2019-10-25 10:08:25", 0, 2, 1607.7, 3, 2, 233, "<invalid>"},
        {"2019-10-25 10:08:58", 0.11, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:09:30", 0.21, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:10:01", 0.32, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:10:33", 0.42, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:11:04", 0.63, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:11:35", 0.74, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:12:06", 0.84, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 10:12:38", 1.05, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 10:13:09", 1.16, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:13:40", 1.26, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:14:11", 1.37, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:14:43", 1.58, 16, 1607.7, 3, 24, 228, "<invalid>"},
        {"2019-10-25 10:15:14", 1.69, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:15:45", 1.79, 16, 1607.7, 3, 24, 227, "<invalid>"},
        {"2019-10-25 10:16:16", 1.9, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:16:48", 2.11, 16, 1607.7, 3, 24, 227, "<invalid>"},
        {"2019-10-25 10:17:19", 2.21, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:17:50", 2.32, 16, 1607.7, 3, 24, 229, "<invalid>"},
        {"2019-10-25 10:18:21", 2.42, 17, 1607.7, 3, 24, 231, "<invalid>"},
        {"2019-10-25 10:18:53", 2.63, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:19:25", 2.74, 17, 1607.7, 3, 24, 230, "<invalid>"},
        {"2019-10-25 10:19:56", 2.85, 16, 1607.7, 3, 24, 227, "<invalid>"},
        {"2019-10-25 10:20:26", 2.95, 0, 1607.7, nil, 0, 1, "<invalid>"}
      ]
    end
  end
end
