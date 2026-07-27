defmodule TeslaMate.Mqtt.PubSub.HomeAssistantTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Mqtt.PubSub.HomeAssistant
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.Car

  defp start_publisher(name) do
    publisher_name = :"mqtt_publisher_#{name}"

    {:ok, _pid} =
      start_supervised({MqttPublisherMock, name: publisher_name, pid: self(), responses: %{}})

    publisher_name
  end

  @summary %Summary{
    display_name: "Foo",
    model: "3",
    healthy: true,
    state: :online,
    latitude: 37.889602,
    longitude: 41.129182,
    car: %Car{id: 0, name: "Tesla Model 3", model: "3"}
  }

  test "publishes a discovery config per entity", %{test: name} do
    publisher_name = start_publisher(name)

    opts = [car_id: 0, namespace: nil, base_url: "https://teslamate.example.com/"]
    :ok = HomeAssistant.publish(@summary, opts, {MqttPublisherMock, publisher_name})

    # Collect every config topic published within a short window
    {topics, payloads} =
      for _ <- 1..200,
          reduce: {MapSet.new(), []} do
        {topics, payloads} ->
          receive do
            {MqttPublisherMock,
             {:publish, "homeassistant/" <> _ = topic, payload, [retain: true, qos: 1]}} ->
              {MapSet.put(topics, topic), [Jason.decode!(payload) | payloads]}
          after
            0 -> {topics, payloads}
          end
      end

    topics_count = MapSet.size(topics)
    assert topics_count > 0
    assert topics_count == length(payloads)

    for decoded <- payloads do
      assert Map.has_key?(decoded, "unique_id")
      assert Map.has_key?(decoded, "default_entity_id")
      refute Map.has_key?(decoded, "object_id")
      device = decoded["device"]
      assert device["identifiers"] == ["teslamate_car_0"]
      assert device["manufacturer"] == "Tesla"
      assert device["configuration_url"] == "https://teslamate.example.com/"
    end
  end

  test "device name falls back to car.name when display_name is nil", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | display_name: nil}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_one_config()
    assert decoded["device"]["name"] == "Tesla Model 3"
  end

  test "device name falls back to Tesla #<car_id> when display_name and car.name are nil",
       %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | display_name: nil, car: nil}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_one_config()
    assert decoded["device"]["name"] == "Tesla #0"
  end

  test "uses custom discovery prefix", %{test: name} do
    publisher_name = start_publisher(name)

    :ok =
      HomeAssistant.publish(
        @summary,
        [car_id: 0, discovery_prefix: "custom/discovery"],
        {MqttPublisherMock, publisher_name}
      )

    assert_receive {MqttPublisherMock,
                    {:publish, "custom/discovery/" <> _ = topic, _payload, [retain: true, qos: 1]}}

    assert String.starts_with?(topic, "custom/discovery/")
  end

  test "uses the default discovery prefix when an empty prefix is passed", %{test: name} do
    publisher_name = start_publisher(name)

    :ok =
      HomeAssistant.publish(
        @summary,
        [car_id: 0, discovery_prefix: ""],
        {MqttPublisherMock, publisher_name}
      )

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _, _, [retain: true, qos: 1]}}
  end

  test "preserves entity IDs from the documented manual configuration", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/sensor/teslamate_0/speed/config", fn decoded ->
      assert decoded["default_entity_id"] == "sensor.tesla_speed"
    end)

    find_config("homeassistant/sensor/teslamate_0/est_battery_range_km/config", fn decoded ->
      assert decoded["default_entity_id"] == "sensor.tesla_est_battery_range"
    end)

    find_config("homeassistant/binary_sensor/teslamate_0/park_brake/config", fn decoded ->
      assert decoded["default_entity_id"] == "binary_sensor.tesla_park_brake"
    end)

    find_config("homeassistant/device_tracker/teslamate_0/location/config", fn decoded ->
      assert decoded["default_entity_id"] == "device_tracker.tesla_location"
    end)
  end

  test "covers all current non-deprecated MQTT topic groups", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    for {component, object_id} <- [
          {"sensor", "charging_state"},
          {"sensor", "charge_current_request"},
          {"sensor", "charge_current_request_max"},
          {"sensor", "center_display_state"},
          {"sensor", "download_perc"},
          {"sensor", "install_perc"},
          {"sensor", "sun_roof_state"},
          {"sensor", "sun_roof_percent_open"},
          {"binary_sensor", "driver_front_window_open"},
          {"binary_sensor", "driver_rear_window_open"},
          {"binary_sensor", "passenger_front_window_open"},
          {"binary_sensor", "passenger_rear_window_open"},
          {"binary_sensor", "driver_front_door_open"},
          {"binary_sensor", "driver_rear_door_open"},
          {"binary_sensor", "passenger_front_door_open"},
          {"binary_sensor", "passenger_rear_door_open"},
          {"binary_sensor", "service_mode"},
          {"binary_sensor", "sun_roof_installed"},
          {"binary_sensor", "tpms_soft_warning_fl"},
          {"binary_sensor", "tpms_soft_warning_fr"},
          {"binary_sensor", "tpms_soft_warning_rl"},
          {"binary_sensor", "tpms_soft_warning_rr"}
        ] do
      target = "homeassistant/#{component}/teslamate_0/#{object_id}/config"

      find_config(target, fn decoded ->
        assert decoded["state_topic"] == "teslamate/cars/0/#{object_id}"
      end)
    end
  end

  test "uses a reset-aware state class for session charge energy", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/sensor/teslamate_0/charge_energy_added/config", fn decoded ->
      assert decoded["state_class"] == "total_increasing"
    end)
  end

  test "locked binary sensor is inverted", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/binary_sensor/teslamate_0/locked/config", fn decoded ->
      assert decoded["payload_on"] == "false"
      assert decoded["payload_off"] == "true"
      assert decoded["device_class"] == "lock"
      assert decoded["state_topic"] == "teslamate/cars/0/locked"
    end)
  end

  test "active route sensors include availability and template", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/sensor/teslamate_0/active_route_destination/config", fn decoded ->
      assert decoded["state_topic"] == "teslamate/cars/0/active_route"
      assert String.contains?(decoded["value_template"], "value_json.destination")
      assert %{"topic" => "teslamate/cars/0/active_route"} = decoded["availability"]
    end)
  end

  test "psi sensor derives value from the bar topic", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/sensor/teslamate_0/tpms_pressure_fl_psi/config", fn decoded ->
      assert decoded["state_topic"] == "teslamate/cars/0/tpms_pressure_fl"
      assert decoded["unit_of_measurement"] == "psi"
      assert String.contains?(decoded["value_template"], "14.50377")
    end)
  end

  test "clear publishes empty payloads per entity", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.clear(0, [], {MqttPublisherMock, publisher_name})

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/sensor/teslamate_0/display_name/config", "",
                     [retain: true, qos: 1]}}

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/binary_sensor/teslamate_0/locked/config", "",
                     [retain: true, qos: 1]}}
  end

  defp receive_one_config(timeout \\ 200) do
    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/" <> _ = topic, payload, [retain: true, qos: 1]}},
                   timeout

    {topic, Jason.decode!(payload)}
  end

  # Drains the mailbox looking for a specific config topic, invoking `fun`
  # with the decoded payload once found.
  defp find_config(target, fun, timeout \\ 500) do
    receive do
      {MqttPublisherMock, {:publish, ^target, payload, [retain: true, qos: 1]}} ->
        fun.(Jason.decode!(payload))
    after
      timeout -> flunk("Did not receive #{target}")
    end
  end
end
