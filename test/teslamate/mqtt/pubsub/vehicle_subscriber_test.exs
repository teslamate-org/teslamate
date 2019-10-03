defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriberTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
  alias TeslaMate.Vehicles.Vehicle.Summary

  defp start_subscriber(name, car_id) do
    publisher_name = :"mqtt_publisher_#{name}"
    vehicles_name = :"vehicles_#{name}"

    {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})
    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})

    start_supervised(
      {VehicleSubscriber,
       [
         name: name,
         car_id: car_id,
         deps_publisher: {MqttPublisherMock, publisher_name},
         deps_vehicles: {VehiclesMock, vehicles_name}
       ]}
    )
  end

  test "publishes vehicle data", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe, 0}}

    summary = %Summary{
      display_name: "Foo",
      odometer: 42_000,
      windows_open: true,
      shift_state: "D",
      state: :online,
      since: DateTime.utc_now(),
      latitude: 37.889602,
      longitude: 41.129182,
      speed: 40,
      outside_temp: 15,
      inside_temp: 20.0,
      locked: true,
      sentry_mode: false,
      plugged_in: false
    }

    send(pid, summary)

    for {key, val} <- Map.from_struct(summary), not is_nil(val) and key != :since do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: true, qos: 1]}}
    end

    iso_time = DateTime.to_iso8601(summary.since)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/since", ^iso_time, [retain: true, qos: 1]}}

    for key <- [
          :charge_energy_added,
          :charger_actual_current,
          :charger_phases,
          :charger_power,
          :charger_voltage,
          :scheduled_charging_start_time,
          :time_to_full_charge
        ] do
      topic = "teslamate/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "", [retain: true, qos: 1]}}
    end

    refute_receive _
  end

  test "publishes charging data", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe, 0}}

    summary = %Summary{
      plugged_in: false,
      battery_level: 60.0,
      charge_energy_added: 25,
      charge_limit_soc: 90,
      charge_port_door_open: false,
      charger_actual_current: 42,
      charger_phases: 3,
      charger_power: 50,
      charger_voltage: 16,
      est_battery_range_km: 220.05,
      ideal_battery_range_km: 230.52,
      rated_battery_range_km: 230.52,
      scheduled_charging_start_time: DateTime.utc_now() |> DateTime.add(60 * 60 * 10, :second),
      time_to_full_charge: (DateTime.utc_now() |> DateTime.to_unix()) + :timer.minutes(25)
    }

    send(pid, summary)

    for {key, val} <- Map.from_struct(summary),
        not is_nil(val) and key != :scheduled_charging_start_time do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: true, qos: 1]}}
    end

    iso_time = DateTime.to_iso8601(summary.scheduled_charging_start_time)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/scheduled_charging_start_time", ^iso_time,
                     [retain: true, qos: 1]}}

    refute_receive _
  end
end
