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

  test "publishes one device discovery config containing every entity", %{test: name} do
    publisher_name = start_publisher(name)

    opts = [car_id: 0, namespace: nil, base_url: "https://teslamate.example.com/"]
    :ok = HomeAssistant.publish(@summary, opts, {MqttPublisherMock, publisher_name})

    {topic, decoded} = receive_device_config()
    assert topic == "homeassistant/device/teslamate_0/config"

    components = decoded["components"]
    assert map_size(components) > 1

    for config <- Map.values(components) do
      assert Map.has_key?(config, "platform")
      assert Map.has_key?(config, "unique_id")
      assert Map.has_key?(config, "object_id")
    end

    device = decoded["device"]
    assert device["identifiers"] == ["teslamate_car_0"]
    assert device["manufacturer"] == "Tesla"
    assert device["configuration_url"] == "https://teslamate.example.com/"
    assert device["model"] == "Model 3"
    refute Map.has_key?(device, "sw_version")

    assert decoded["origin"]["name"] == "TeslaMate"
    assert is_binary(decoded["origin"]["sw_version"])
    assert decoded["origin"]["support_url"] == "https://docs.teslamate.org/"

    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}
  end

  test "publishes rich model and firmware metadata", %{test: name} do
    publisher_name = start_publisher(name)
    car = %{@summary.car | marketing_name: "LR AWD"}

    summary = %{
      @summary
      | model: "S",
        trim_badging: "74D",
        wheel_type: "AeroTurbine19",
        spoiler_type: "CarbonFiber",
        sun_roof_installed: true,
        version: "2026.26.1",
        car: car
    }

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    assert decoded["device"]["model"] ==
             ~s|Model S LR AWD (Aero Turbine 19" Wheels, Carbon Fiber Spoiler, Sunroof)|

    assert decoded["device"]["sw_version"] == "2026.26.1"
  end

  test "falls back to raw trim badging when the marketing name is unavailable", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | trim_badging: "74D"}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    assert decoded["device"]["model"] == "Model 3 74D"
  end

  test "falls back to Tesla when the model is unknown", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | model: nil, trim_badging: "FOUNDATION"}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    assert decoded["device"]["model"] == "Tesla"
  end

  test "does not prefix Cybertruck with Model", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | model: "Cybertruck", trim_badging: "FOUNDATION"}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    assert decoded["device"]["model"] == "Cybertruck FOUNDATION"
  end

  test "omits an absent spoiler from the rich model", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{
      @summary
      | trim_badging: "Long Range",
        wheel_type: "Induction",
        spoiler_type: "None",
        sun_roof_installed: false
    }

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    assert decoded["device"]["model"] == "Model 3 Long Range (Induction Wheels)"
  end

  test "formats wheel types with optional suffixes" do
    wheel_types = [
      {"AeroTurbine19", ~s|Aero Turbine 19" Wheels|},
      {"Pinwheel18", ~s|Pinwheel 18" Wheels|},
      {"Slipstream19Carbon", ~s|Slipstream 19" Carbon Wheels|}
    ]

    for {wheel_type, expected} <- wheel_types do
      device = HomeAssistant.device(%{@summary | wheel_type: wheel_type}, car_id: 0)
      assert device.model == "Model 3 (#{expected})"
    end
  end

  test "device name falls back to car.name when display_name is nil", %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | display_name: nil}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    assert decoded["device"]["name"] == "Tesla Model 3"
  end

  test "device name falls back to Tesla #<car_id> when display_name and car.name are nil",
       %{test: name} do
    publisher_name = start_publisher(name)

    summary = %{@summary | display_name: nil, car: nil}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
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
                    {:publish, "custom_prefix/device/teslamate_0/config", _payload,
                     [retain: true, qos: 1]}}
  end

  test "scopes device topic, unique_id and device by namespace", %{test: name} do
    publisher_name = start_publisher(name)

    :ok =
      HomeAssistant.publish(
        @summary,
        [car_id: 0, namespace: "ns1"],
        {MqttPublisherMock, publisher_name}
      )

    {topic, decoded} = receive_device_config()
    assert topic == "homeassistant/device/teslamate_ns1_0/config"

    speed = decoded["components"]["speed"]
    assert speed["object_id"] == "tesla_speed"
    assert speed["unique_id"] == "teslamate_ns1_0_speed"
    assert speed["state_topic"] == "teslamate/ns1/cars/0/speed"
    assert decoded["device"]["identifiers"] == ["teslamate_ns1_car_0"]

    assert decoded["components"]["display_name"]["unique_id"] ==
             "teslamate_ns1_0_display_name"
  end

  test "locked binary sensor is inverted", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["locked"]
    assert config["platform"] == "binary_sensor"
    assert config["payload_on"] == "false"
    assert config["payload_off"] == "true"
    assert config["device_class"] == "lock"
    assert config["state_topic"] == "teslamate/cars/0/locked"
  end

  test "active route sensors include availability and template", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["active_route_destination"]
    assert config["state_topic"] == "teslamate/cars/0/active_route"
    assert String.contains?(config["value_template"], "value_json.destination")
    assert %{"topic" => "teslamate/cars/0/active_route"} = config["availability"]
  end

  test "psi sensor derives value from the bar topic", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["tpms_pressure_fl_psi"]
    assert config["state_topic"] == "teslamate/cars/0/tpms_pressure_fl"
    assert config["unit_of_measurement"] == "psi"
    assert String.contains?(config["value_template"], "14.50377")
  end

  test "entity ids match the manual mqtt_sensors.yaml naming", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    assert decoded["components"]["speed"]["object_id"] == "tesla_speed"
    assert decoded["components"]["speed"]["unique_id"] == "teslamate_0_speed"

    assert decoded["components"]["est_battery_range"]["object_id"] ==
             "tesla_est_battery_range"

    assert decoded["components"]["est_battery_range"]["unique_id"] ==
             "teslamate_0_est_battery_range"

    assert decoded["components"]["healthy"]["object_id"] == "tesla_healthy"
    assert decoded["components"]["healthy"]["unique_id"] == "teslamate_0_healthy"
  end

  test "clear publishes an empty device discovery payload", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.clear(0, [car_id: 0], {MqttPublisherMock, publisher_name})

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/teslamate_0/config", "",
                     [retain: true, qos: 1]}}

    refute_receive {MqttPublisherMock, {:publish, "homeassistant/" <> _, _, _}}
  end

  defp receive_device_config(timeout \\ 200) do
    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/" <> _ = topic, payload,
                     [retain: true, qos: 1]}},
                   timeout

    {topic, Jason.decode!(payload)}
  end
end
