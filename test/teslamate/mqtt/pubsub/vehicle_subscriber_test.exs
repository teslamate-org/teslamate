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

  test "", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe, 0}}

    summary = %Summary{
      display_name: "Foo",
      state: :online,
      since: DateTime.utc_now(),
      latitude: 37.889602,
      longitude: 41.129182,
      battery_level: 60.0,
      ideal_battery_range_km: 230.5,
      est_battery_range_km: 220.0,
      rated_battery_range_km: 230.5,
      charge_energy_added: 25,
      speed: 40,
      outside_temp: 15,
      inside_temp: 20.0,
      locked: true,
      sentry_mode: false,
      plugged_in: false,
      scheduled_charging_start_time: DateTime.utc_now() |> DateTime.add(60 * 60 * 10, :second),
      charge_limit_soc: 90,
      charger_power: 50
    }

    send(pid, summary)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/charge_limit_soc", "90", [retain: true, qos: 1]}}

    # assert_receive {MqttPublisherMock,
    #                 {:publish, "teslamate/cars/0/latitude", "37.889602", [retain: true, qos: 1]}}

    # assert_receive {MqttPublisherMock,
    #                 {:publish, "teslamate/cars/0/longitude", "41.129182", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/display_name", "Foo", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/inside_temp", "20.0", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/locked", "true", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/outside_temp", "15", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/plugged_in", "false", [retain: true, qos: 1]}}

    scheduled_charging_start_time_str = to_string(summary.scheduled_charging_start_time)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/scheduled_charging_start_time",
                     ^scheduled_charging_start_time_str, [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/sentry_mode", "false", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/speed", "40", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/state", "online", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/battery_level", "60.0", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/rated_battery_range_km", "230.5",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/est_battery_range_km", "220.0",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/ideal_battery_range_km", "230.5",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/charge_energy_added", "25",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/charger_power", "50", [retain: true, qos: 1]}}

    since_str = to_string(summary.since)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/since", ^since_str, [retain: true, qos: 1]}}

    # send same summary again
    send(pid, summary)

    refute_receive _
  end

  test "send empty string if scheduled_charging_start_time is nil", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe, 0}}

    summary = %Summary{
      scheduled_charging_start_time: nil
    }

    send(pid, summary)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/scheduled_charging_start_time", "",
                     [retain: true, qos: 1]}}

    refute_receive _
  end
end
