defmodule TeslaMate.Mqtt.PubSubTest do
  use TeslaMate.DataCase, async: false

  alias TeslaMate.Log
  alias TeslaMate.Mqtt.PubSub
  alias TeslaMate.Vehicles
  alias TeslaMate.Vehicles.Vehicle.Summary

  describe "subscribers follow the vehicle list" do
    setup %{test: name} do
      {:ok, car_a} = Log.create_car(%{name: "A", eid: 10, vid: 10, vin: "VINA"})
      {:ok, car_b} = Log.create_car(%{name: "B", eid: 11, vid: 11, vin: "VINB"})

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
           deps_vehicles: {VehiclesMock, vehicles_name},
           deps_publisher: {MqttPublisherMock, publisher_name}}
        )

      [car_a: car_a, car_b: car_b, vehicles: vehicles_name, pubsub: pubsub]
    end

    defp subscribed_car_ids(pubsub) do
      %PubSub{supervisor: supervisor} = :sys.get_state(pubsub)

      supervisor
      |> Supervisor.which_children()
      |> Enum.map(fn {car_id, _pid, _type, _modules} -> car_id end)
      |> Enum.sort()
    end

    test "starts one subscriber per vehicle", %{car_a: car_a, pubsub: pubsub} do
      assert_receive {VehiclesMock, {:subscribe_to_summary, car_id}}
      assert car_id == car_a.id
      assert subscribed_car_ids(pubsub) == [car_a.id]
    end

    test "adds and removes subscribers when the vehicles are reloaded", ctx do
      %{car_a: car_a, car_b: car_b, vehicles: vehicles, pubsub: pubsub} = ctx
      assert_receive {VehiclesMock, {:subscribe_to_summary, _}}

      :ok = VehiclesMock.set_summaries(vehicles, [%Summary{car: car_b}])
      :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, Vehicles.topic(), {Vehicles, :reloaded})

      assert_receive {VehiclesMock, {:subscribe_to_summary, car_id}}
      assert car_id == car_b.id
      assert subscribed_car_ids(pubsub) == [car_b.id]
      refute car_a.id in subscribed_car_ids(pubsub)
    end

    test "keeps running subscribers on a reload without changes", ctx do
      %{car_a: car_a, pubsub: pubsub} = ctx
      assert_receive {VehiclesMock, {:subscribe_to_summary, _}}

      %PubSub{supervisor: supervisor} = :sys.get_state(pubsub)
      [{_, pid_before, _, _}] = Supervisor.which_children(supervisor)

      :ok = Phoenix.PubSub.broadcast(TeslaMate.PubSub, Vehicles.topic(), {Vehicles, :reloaded})

      assert subscribed_car_ids(pubsub) == [car_a.id]
      [{_, pid_after, _, _}] = Supervisor.which_children(supervisor)
      assert pid_before == pid_after
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
