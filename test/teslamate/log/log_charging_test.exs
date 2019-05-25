defmodule TeslaMate.LogChargingTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Log.{Car, ChargingProcess, Charge}
  alias TeslaMate.Log

  def car_fixture(attrs \\ %{}) do
    {:ok, car} =
      attrs
      |> Enum.into(%{efficiency: 0.153, eid: 42, model: "M3", vid: 42})
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

  describe "close_charging_process/1" do
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
          outside_temp: 14.5
        }
      ]

      for c <- charges do
        assert {:ok, %Charge{} = charge} = Log.insert_charge(charging_process_id, c)
      end

      assert {:ok, %ChargingProcess{} = cproc} = Log.close_charging_process(charging_process_id)

      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
      assert cproc.calculated_max_range == 497
      assert cproc.charge_energy_added == 0.72
      assert cproc.duration_min == 4
      assert cproc.end_battery_level == 54
      assert cproc.start_battery_level == 50
      assert cproc.start_range_km == 266.6
      assert cproc.end_range_km == 268.6
      assert cproc.outside_temp_avg == 15.25
    end

    test "closes charging process with zero charges " do
      assert %Car{id: car_id} = car_fixture()
      assert {:ok, charging_process_id} = Log.start_charging_process(car_id, @valid_pos_attrs)
      assert {:ok, %ChargingProcess{} = cproc} = Log.close_charging_process(charging_process_id)

      assert %DateTime{} = cproc.start_date
      assert %DateTime{} = cproc.end_date
    end
  end
end
