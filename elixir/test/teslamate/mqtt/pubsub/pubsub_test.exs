defmodule TeslaMate.Mqtt.PubSubTest do
  use TeslaMate.DataCase, async: false

  import TestHelper, only: [drain_discovery_configs: 0]

  alias TeslaMate.Log
  alias TeslaMate.Mqtt.PubSub
  alias TeslaMate.Vehicles
  alias TeslaMate.Vehicles.Vehicle.Summary

  describe "subscribers follow the vehicle list" do
    setup %{test: name} do
      {:ok, car_a} = Log.create_car(%{name: "A", eid: 10, vid: 10, vin: "VINA"})
      {:ok, car_b} = Log.create_car(%{name: "B", eid: 11, vid: 11, vin: "VINB"})
      {:ok, removed} = Log.create_car(%{name: "Removed", eid: 12, vid: 12, vin: "VINR"})

      vehicles_name = :"vehicles_#{name}"
      publisher_name = :"mqtt_publisher_#{name}"

      {:ok, _pid} =
        start_supervised(
          {VehiclesMock, name: vehicles_name, pid: self(), summaries: [%Summary{car: car_a}]}
        )

      {:ok, _pid} = start_supervised({MqttPublisherMock, name: publisher_name, pid: self()})

      {:ok, pubsub} =
        start_supervised(
          {PubSub,
           name: :"pubsub_#{name}",
           discovery: true,
           deps_vehicles: {VehiclesMock, vehicles_name},
           deps_publisher: {MqttPublisherMock, publisher_name}}
        )

      # Start-up clears the configs of every car without a logger: removed and B
      removed_topic = "homeassistant/device/teslamate_#{removed.id}/config"
      assert_receive {MqttPublisherMock, {:publish, ^removed_topic, "", _}}
      :ok = drain_discovery_configs()

      [car_a: car_a, car_b: car_b, vehicles: vehicles_name, pubsub: pubsub]
    end

    defp subscribers(pubsub) do
      %PubSub{supervisor: supervisor} = :sys.get_state(pubsub)

      supervisor
      |> Supervisor.which_children()
      |> Map.new(fn {car_id, pid, _type, _modules} -> {car_id, pid} end)
    end

    test "starts one subscriber per vehicle at start-up", %{car_a: car_a, pubsub: pubsub} do
      assert_receive {VehiclesMock, {:subscribe_to_summary, car_id}}
      assert car_id == car_a.id
      assert Map.keys(subscribers(pubsub)) == [car_a.id]
    end

    test "adds a subscriber for a discovered vehicle without touching the others", ctx do
      %{car_a: car_a, car_b: car_b, vehicles: vehicles, pubsub: pubsub} = ctx
      assert_receive {VehiclesMock, {:subscribe_to_summary, _}}
      %{} = before = subscribers(pubsub)

      :ok = VehiclesMock.set_summaries(vehicles, [%Summary{car: car_a}, %Summary{car: car_b}])
      :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, "vehicles", {Vehicles, :vehicles_changed})

      assert_receive {VehiclesMock, {:subscribe_to_summary, car_id}}
      assert car_id == car_b.id

      after_ = subscribers(pubsub)
      assert Map.keys(after_) |> Enum.sort() == Enum.sort([car_a.id, car_b.id])
      assert after_[car_a.id] == before[car_a.id]

      # A discovery only adds vehicles, so nothing is cleared in Home Assistant
      refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, "", _}}
    end

    test "ignores a change that brought no new vehicle", %{car_a: car_a, pubsub: pubsub} do
      assert_receive {VehiclesMock, {:subscribe_to_summary, _}}
      before = subscribers(pubsub)

      :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, "vehicles", {Vehicles, :vehicles_changed})

      assert subscribers(pubsub) == before
      assert Map.keys(before) == [car_a.id]
      refute_receive {VehiclesMock, {:subscribe_to_summary, _}}
    end
  end

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
