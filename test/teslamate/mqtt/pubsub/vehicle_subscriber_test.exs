defmodule TeslaMate.Mqtt.PubSub.VehicleSubscriberTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Mqtt.PubSub.VehicleSubscriber
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Locations.GeoFence

  defp start_subscriber(name, car_id, namespace \\ nil) do
    publisher_name = :"mqtt_publisher_#{name}"
    vehicles_name = :"vehicles_#{name}"

    {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})
    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})

    start_supervised(
      {VehicleSubscriber,
       [
         name: name,
         car_id: car_id,
         namespace: namespace,
         deps_publisher: {MqttPublisherMock, publisher_name},
         deps_vehicles: {VehiclesMock, vehicles_name}
       ]}
    )
  end

  test "publishes vehicle data", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{
      healthy: true,
      display_name: "Foo",
      odometer: 42_000,
      windows_open: true,
      doors_open: true,
      shift_state: "D",
      state: :online,
      since: DateTime.utc_now(),
      latitude: 37.889602,
      longitude: 41.129182,
      power: -9,
      speed: 40,
      heading: 340,
      outside_temp: 15,
      inside_temp: 20.0,
      locked: true,
      sentry_mode: false,
      plugged_in: false,
      version: "2019.42",
      update_available: false,
      update_version: "2019.43",
      is_preconditioning: true,
      is_user_present: false,
      is_climate_on: true,
      geofence: %GeoFence{id: 0, name: "Home", latitude: 0.0, longitude: 0.0, radius: 20},
      model: "S",
      trim_badging: "P100D",
      exterior_color: "White",
      spoiler_type: "None",
      wheel_type: "AeroTurbine19",
      frunk_open: true,
      trunk_open: false,
      elevation: 100
    }

    send(pid, summary)

    for {key, val} <- Map.from_struct(summary),
        not is_nil(val) and key not in [:since, :geofence] do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: true, qos: 1]}}
    end

    iso_time = DateTime.to_iso8601(summary.since)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/since", ^iso_time, [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/geofence", "Home", [retain: true, qos: 1]}}

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

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{
      plugged_in: false,
      battery_level: 60.0,
      usable_battery_level: 59,
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
      time_to_full_charge: 2.5
    }

    send(pid, summary)

    for {key, val} <- Map.from_struct(summary),
        not is_nil(val) and key != :scheduled_charging_start_time do
      topic = "teslamate/cars/0/#{key}"
      data = to_string(val)
      assert_receive {MqttPublisherMock, {:publish, ^topic, ^data, [retain: true, qos: 1]}}
    end

    # Formated dates
    iso_time = DateTime.to_iso8601(summary.scheduled_charging_start_time)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/scheduled_charging_start_time", ^iso_time,
                     [retain: true, qos: 1]}}

    # Always published
    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/shift_state", "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/geofence", "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/cars/0/trim_badging", "", [retain: true, qos: 1]}}

    refute_receive _
  end

  test "publishes geofence only if it has changed", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0)

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    geofence = %GeoFence{id: 0, name: "Home", latitude: 0.0, longitude: 0.0, radius: 20}
    other_geofence = %GeoFence{id: 0, name: "Work", latitude: 0.0, longitude: 0.0, radius: 20}

    # Send geofence 
    send(pid, %Summary{geofence: geofence, version: "1"})
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", "Home", _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "1", _}}

    # Send geofence again and expect no message
    send(pid, %Summary{geofence: geofence, version: "2"})
    refute_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", _, _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "2", _}}

    # Send another geofence
    send(pid, %Summary{geofence: other_geofence, version: "3"})
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/geofence", "Work", _}}
    assert_receive {MqttPublisherMock, {:publish, "teslamate/cars/0/version", "3", _}}
  end

  test "allows namespaces", %{test: name} do
    {:ok, pid} = start_subscriber(name, 0, "account_0")

    assert_receive {VehiclesMock, {:subscribe_to_summary, 0}}

    summary = %Summary{
      display_name: "Foo",
      state: :online
    }

    send(pid, summary)

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/display_name", "Foo",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "teslamate/account_0/cars/0/state", "online",
                     [retain: true, qos: 1]}}

    # Always published
    for key <- [
          :charge_energy_added,
          :charger_actual_current,
          :charger_phases,
          :charger_power,
          :charger_voltage,
          :scheduled_charging_start_time,
          :time_to_full_charge,
          :shift_state,
          :geofence,
          :trim_badging
        ] do
      topic = "teslamate/account_0/cars/0/#{key}"
      assert_receive {MqttPublisherMock, {:publish, ^topic, "", [retain: true, qos: 1]}}
    end

    refute_receive _
  end
end
