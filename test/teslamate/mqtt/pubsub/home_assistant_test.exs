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
      assert Map.has_key?(decoded, "object_id")
      device = decoded["device"]
      assert device["identifiers"] == ["teslamate_car_0"]
      assert device["manufacturer"] == "Tesla"
      assert device["configuration_url"] == "https://teslamate.example.com/"
      assert device["model"] == "Model 3"
      refute Map.has_key?(device, "sw_version")
    end
  end

  test "publishes rich model and firmware metadata", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{
      @summary
      | model: "S",
        trim_badging: "P100D",
        wheel_type: "AeroTurbine19",
        spoiler_type: "CarbonFiber",
        version: "2026.26.1"
    }

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_one_config()

    assert decoded["device"]["model"] ==
             ~s|Model S P100D (Aero Turbine 19" Wheels, Carbon Fiber Spoiler)|

    assert decoded["device"]["sw_version"] == "2026.26.1"
  end

  test "omits an absent spoiler from the rich model", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{
      @summary
      | trim_badging: "Long Range",
        wheel_type: "Induction",
        spoiler_type: "None"
    }

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_one_config()
    assert decoded["device"]["model"] == "Model 3 Long Range (Induction Wheels)"
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
        [car_id: 0, discovery_prefix: "custom_prefix"],
        {MqttPublisherMock, publisher_name}
      )

    assert_receive {MqttPublisherMock,
                    {:publish, "custom_prefix/" <> _ = topic, _payload, [retain: true, qos: 1]}}

    assert String.starts_with?(topic, "custom_prefix/")
  end

  test "scopes node, unique_id and device by namespace", %{test: name} do
    publisher_name = start_publisher(name)

    :ok =
      HomeAssistant.publish(
        @summary,
        [car_id: 0, namespace: "ns1"],
        {MqttPublisherMock, publisher_name}
      )

    find_config("homeassistant/sensor/teslamate_ns1_0/speed/config", fn decoded ->
      assert decoded["object_id"] == "tesla_speed"
      assert decoded["unique_id"] == "teslamate_ns1_0_speed"
      assert decoded["state_topic"] == "teslamate/ns1/cars/0/speed"
      assert decoded["device"]["identifiers"] == ["teslamate_ns1_car_0"]
    end)

    find_config("homeassistant/sensor/teslamate_ns1_0/display_name/config", fn decoded ->
      assert decoded["unique_id"] == "teslamate_ns1_0_display_name"
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

  test "entity ids match the manual mqtt_sensors.yaml naming", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    find_config("homeassistant/sensor/teslamate_0/speed/config", fn decoded ->
      assert decoded["object_id"] == "tesla_speed"
      assert decoded["unique_id"] == "teslamate_0_speed"
    end)

    find_config("homeassistant/sensor/teslamate_0/est_battery_range/config", fn decoded ->
      assert decoded["object_id"] == "tesla_est_battery_range"
      assert decoded["unique_id"] == "teslamate_0_est_battery_range"
    end)

    find_config("homeassistant/binary_sensor/teslamate_0/healthy/config", fn decoded ->
      assert decoded["object_id"] == "tesla_healthy"
      assert decoded["unique_id"] == "teslamate_0_healthy"
    end)
  end

  test "clear publishes empty payloads per entity", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.clear(0, [car_id: 0], {MqttPublisherMock, publisher_name})

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
