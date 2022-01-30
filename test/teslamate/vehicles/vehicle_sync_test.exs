defmodule TeslaMate.Vehicles.VehicleSyncTest do
  use TeslaMate.VehicleCase, async: false

  describe "Summary" do
    alias TeslaMate.Vehicles.Vehicle.Summary
    alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
    alias TeslaMate.Log.Car
    alias TeslaMate.Log

    defp start_subscriber(name, %Car{id: car_id}) do
      publisher_name = :"mqtt_publisher_#{name}"

      {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})

      start_supervised(
        {VehicleSubscriber,
         [
           name: name,
           car_id: car_id,
           namespace: nil,
           deps_publisher: {MqttPublisherMock, publisher_name}
         ]}
      )
    end

    test "restores and publishes last known values", %{test: name} do
      events = [
        {:ok, %TeslaApi.Vehicle{state: "asleep", display_name: "bar"}},
        fn -> Process.sleep(10_000) end
      ]

      {:ok, car} =
        Log.create_car(%{
          eid: 43_903_421,
          model: "S",
          vid: 43_903_421,
          name: "foo",
          trim_badging: "P100D",
          vin: "19023450213412345F"
        })

      {:ok, _} =
        Log.insert_position(
          car,
          %{
            date: DateTime.utc_now(),
            latitude: 37.8895442,
            longitude: 41.1288167,
            speed: nil,
            power: 0,
            odometer: 91887.725564,
            ideal_battery_range_km: 315.06,
            battery_level: 64,
            outside_temp: 16.5,
            elevation: nil,
            fan_status: 0,
            driver_temp_setting: 15.0,
            passenger_temp_setting: 15.0,
            is_climate_on: false,
            is_rear_defroster_on: false,
            is_front_defroster_on: false,
            inside_temp: 20.1,
            battery_heater: false,
            battery_heater_on: false,
            battery_heater_no_power: nil,
            est_battery_range_km: 268.07,
            rated_battery_range_km: 315.06,
            usable_battery_level: 64
          }
        )

      :ok = start_vehicle(name, events, car: car, log: false)
      {:ok, subscriber} = start_subscriber(name, car)

      assert_receive {:pubsub, {:broadcast, _, _, %Summary{state: :asleep} = summary}}

      assert summary == %Summary{
               battery_level: 64,
               car: car,
               charge_energy_added: :unknown,
               charge_limit_soc: nil,
               charge_port_door_open: :unknown,
               charger_actual_current: :unknown,
               charger_phases: :unknown,
               charger_power: :unknown,
               charger_voltage: :unknown,
               display_name: "bar",
               doors_open: nil,
               elevation: nil,
               est_battery_range_km: 268.07,
               exterior_color: nil,
               frunk_open: nil,
               geofence: nil,
               heading: nil,
               healthy: true,
               ideal_battery_range_km: 315.06,
               inside_temp: Decimal.from_float(20.1),
               is_climate_on: nil,
               is_preconditioning: nil,
               is_user_present: nil,
               latitude: Decimal.from_float(37.889544),
               locked: nil,
               longitude: Decimal.from_float(41.128817),
               model: "S",
               odometer: 91887.73,
               outside_temp: Decimal.from_float(16.5),
               plugged_in: :unknown,
               rated_battery_range_km: 315.06,
               scheduled_charging_start_time: :unknown,
               sentry_mode: nil,
               shift_state: :unknown,
               since: summary.since,
               speed: nil,
               spoiler_type: nil,
               state: :asleep,
               time_to_full_charge: :unknown,
               trim_badging: "P100D",
               trunk_open: nil,
               update_available: nil,
               usable_battery_level: 64,
               version: nil,
               wheel_type: nil,
               windows_open: nil
             }

      send(subscriber, summary)

      for {key, val} <- [
            battery_level: 64,
            display_name: "bar",
            est_battery_range_km: 268.07,
            geofence: nil,
            healthy: true,
            ideal_battery_range_km: 315.06,
            inside_temp: 20.1,
            latitude: 37.889544,
            longitude: 41.128817,
            model: "S",
            odometer: 91887.73,
            outside_temp: 16.5,
            rated_battery_range_km: 315.06,
            since: DateTime.to_iso8601(summary.since),
            state: :asleep,
            trim_badging: "P100D",
            usable_battery_level: 64
          ] do
        topic = "teslamate/cars/#{car.id}/#{key}"
        data = to_string(val)
        assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: true, qos: 1]}}
      end

      refute_receive _
    end
  end
end
