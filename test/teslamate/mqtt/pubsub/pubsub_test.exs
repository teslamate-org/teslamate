defmodule TeslaMate.Mqtt.PubSubTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Log
  alias TeslaMate.Mqtt.PubSub
  alias TeslaMate.Vehicles.Vehicle.Summary

  test "clears discovery configs for removed vehicles", %{test: name} do
    {:ok, active_car} = Log.create_car(%{name: "Active", eid: 1, vid: 1, vin: "VIN1"})
    {:ok, removed_car} = Log.create_car(%{name: "Removed", eid: 2, vid: 2, vin: "VIN2"})

    publisher_name = :"mqtt_publisher_#{name}"
    {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})

    vehicles = [%Summary{car: active_car}]
    active_topic = "homeassistant/device/teslamate_#{active_car.id}/config"
    removed_topic = "homeassistant/device/teslamate_#{removed_car.id}/config"

    removed_legacy_topic =
      "homeassistant/sensor/teslamate_#{removed_car.id}/display_name/config"

    :ok =
      PubSub.clear_removed_vehicles(vehicles,
        deps_publisher: {MqttPublisherMock, publisher_name}
      )

    # Active vehicle is untouched
    refute_receive {MqttPublisherMock, {:publish, ^active_topic, _, _}}

    # Removed vehicle's discovery configs are cleared
    assert_receive {MqttPublisherMock, {:publish, ^removed_topic, "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, ^removed_legacy_topic, "", [retain: true, qos: 1]}}
  end

  test "clears discovery configs under the namespace-scoped node", %{test: name} do
    {:ok, active_car} = Log.create_car(%{name: "Active", eid: 4, vid: 4, vin: "VIN4"})
    {:ok, removed_car} = Log.create_car(%{name: "Removed", eid: 5, vid: 5, vin: "VIN5"})

    publisher_name = :"mqtt_publisher_#{name}"
    {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})

    vehicles = [%Summary{car: active_car}]

    removed_topic = "homeassistant/device/teslamate_ns1_#{removed_car.id}/config"
    unscoped_topic = "homeassistant/device/teslamate_#{removed_car.id}/config"

    removed_legacy_topic =
      "homeassistant/sensor/teslamate_ns1_#{removed_car.id}/display_name/config"

    :ok =
      PubSub.clear_removed_vehicles(vehicles,
        namespace: "ns1",
        deps_publisher: {MqttPublisherMock, publisher_name}
      )

    # Cleared under the namespace-scoped node only
    assert_receive {MqttPublisherMock, {:publish, ^removed_topic, "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, ^removed_legacy_topic, "", [retain: true, qos: 1]}}

    refute_receive {MqttPublisherMock, {:publish, ^unscoped_topic, _, _}}
  end

  test "does not clear discovery configs when no vehicles are removed", %{test: name} do
    {:ok, car} = Log.create_car(%{name: "Only", eid: 3, vid: 3, vin: "VIN3"})

    publisher_name = :"mqtt_publisher_#{name}"
    {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})

    vehicles = [%Summary{car: car}]

    :ok =
      PubSub.clear_removed_vehicles(vehicles,
        deps_publisher: {MqttPublisherMock, publisher_name}
      )

    refute_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _, "", [retain: true, qos: 1]}}
  end
end
