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
    active_topic = "homeassistant/sensor/teslamate_#{active_car.id}/display_name/config"
    removed_topic = "homeassistant/sensor/teslamate_#{removed_car.id}/display_name/config"
    removed_locked_topic = "homeassistant/binary_sensor/teslamate_#{removed_car.id}/locked/config"

    :ok =
      PubSub.clear_removed_vehicles(vehicles,
        deps_publisher: {MqttPublisherMock, publisher_name}
      )

    # Active vehicle is untouched
    refute_receive {MqttPublisherMock, {:publish, ^active_topic, _, _}}

    # Removed vehicle's discovery configs are cleared
    assert_receive {MqttPublisherMock, {:publish, ^removed_topic, "", [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, ^removed_locked_topic, "", [retain: true, qos: 1]}}
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
