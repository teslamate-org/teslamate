defmodule TeslaMate.Mqtt.PubSub.HomeAssistantTest do
  use ExUnit.Case, async: true

  alias TeslaMate.Mqtt.PubSub.HomeAssistant
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.Car

  @migration_delay 10
  @migration_payload Jason.encode!(%{migrate_discovery: true})

  defp migration_opts(opts), do: Keyword.put(opts, :migration_delay, @migration_delay)

  defp start_publisher(name, responses \\ %{}) do
    publisher_name = :"mqtt_publisher_#{name}"

    {:ok, _pid} =
      start_supervised(
        {MqttPublisherMock, name: publisher_name, pid: self(), responses: responses}
      )

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

  test "migrates enabled components before cleanup and disabled components after cleanup", %{
    test: name
  } do
    publisher_name = start_publisher(name)

    opts =
      migration_opts(car_id: 0, namespace: nil, base_url: "https://teslamate.example.com/")

    started_at = System.monotonic_time(:millisecond)
    :ok = HomeAssistant.migrate(@summary, opts, {MqttPublisherMock, publisher_name})
    assert System.monotonic_time(:millisecond) - started_at >= @migration_delay

    messages = receive_configs()

    {migrations, [{topic, migration_payload, publish_opts} | remaining]} =
      Enum.split_while(messages, fn {topic, _payload, _opts} ->
        topic != "homeassistant/device/teslamate_0/config"
      end)

    {cleanup, [{final_topic, final_payload, final_publish_opts}]} =
      Enum.split(remaining, length(migrations))

    assert migrations != []

    assert Enum.all?(
             migrations,
             &match?({_topic, @migration_payload, [retain: true, qos: 1]}, &1)
           )

    assert topic == "homeassistant/device/teslamate_0/config"
    assert publish_opts == [retain: true, qos: 1]
    assert final_topic == topic
    assert final_publish_opts == publish_opts

    assert Enum.map(migrations, &elem(&1, 0)) == Enum.map(cleanup, &elem(&1, 0))
    assert Enum.all?(cleanup, &match?({_topic, "", [retain: true, qos: 1]}, &1))

    migration_decoded = Jason.decode!(migration_payload)
    decoded = Jason.decode!(final_payload)

    components = decoded["components"]
    assert map_size(components) == length(migrations)

    disabled_component_ids =
      for {object_id, %{"enabled_by_default" => false}} <- components, do: object_id

    assert disabled_component_ids != []

    assert Map.keys(migration_decoded["components"]) |> Enum.sort() ==
             Map.keys(components) |> Kernel.--(disabled_component_ids) |> Enum.sort()

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
  end

  test "publishes a device config without touching legacy topics", %{test: name} do
    publisher_name = start_publisher(name)

    :ok =
      HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    assert [{topic, payload, publish_opts}] = receive_configs()
    assert topic == "homeassistant/device/teslamate_0/config"
    assert publish_opts == [retain: true, qos: 1]
    assert is_map(Jason.decode!(payload)["components"])
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

  test "publishes device metadata sources as disabled diagnostics", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    expected = %{
      "display_name" => {"Display Name", "mdi:form-textbox"},
      "model" => {"Model", "mdi:form-textbox"},
      "spoiler_type" => {"Spoiler Type", "mdi:car-sports"},
      "trim_badging" => {"Trim Badging", "mdi:shield-star-outline"},
      "version" => {"Version", "mdi:numeric"},
      "wheel_type" => {"Wheel Type", "mdi:tire"}
    }

    for {object_id, {entity_name, icon}} <- expected do
      config = decoded["components"][object_id]

      assert config["platform"] == "sensor"
      assert config["name"] == entity_name
      assert config["entity_category"] == "diagnostic"
      assert config["enabled_by_default"] == false
      assert config["icon"] == icon
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
    end

    sunroof = decoded["components"]["sun_roof_installed"]
    assert sunroof["platform"] == "binary_sensor"
    assert sunroof["name"] == "Sunroof Installed"
    assert sunroof["entity_category"] == "diagnostic"
    assert sunroof["enabled_by_default"] == false
    assert sunroof["payload_on"] == "true"
    assert sunroof["payload_off"] == "false"
    assert sunroof["icon"] == "mdi:car-convertible"
    assert sunroof["state_topic"] == "teslamate/cars/0/sun_roof_installed"
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
      HomeAssistant.migrate(
        @summary,
        migration_opts(car_id: 0, namespace: "ns1"),
        {MqttPublisherMock, publisher_name}
      )

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/sensor/teslamate_ns1_0/speed/config",
                     @migration_payload, [retain: true, qos: 1]}}

    {topic, decoded} = receive_device_config()
    assert topic == "homeassistant/device/teslamate_ns1_0/config"

    speed = decoded["components"]["speed"]
    assert speed["object_id"] == "tesla_speed"
    assert speed["unique_id"] == "teslamate_ns1_0_speed"
    assert speed["state_topic"] == "teslamate/ns1/cars/0/speed"
    assert decoded["device"]["identifiers"] == ["teslamate_ns1_car_0"]
    refute Map.has_key?(decoded["components"], "display_name")

    {final_topic, final_decoded} = receive_device_config()
    assert final_topic == topic

    assert final_decoded["components"]["display_name"]["unique_id"] ==
             "teslamate_ns1_0_display_name"

    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/sensor/teslamate_ns1_0/speed/config", "",
                     [retain: true, qos: 1]}}
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

  test "publishes tire soft warnings as diagnostic problems", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    tires = [
      {"tpms_soft_warning_fl", "Tire Soft (Front Left)"},
      {"tpms_soft_warning_fr", "Tire Soft (Front Right)"},
      {"tpms_soft_warning_rl", "Tire Soft (Rear Left)"},
      {"tpms_soft_warning_rr", "Tire Soft (Rear Right)"}
    ]

    for {object_id, entity_name} <- tires do
      config = decoded["components"][object_id]

      assert config["platform"] == "binary_sensor"
      assert config["name"] == entity_name
      assert config["device_class"] == "problem"
      assert config["entity_category"] == "diagnostic"
      assert config["payload_on"] == "true"
      assert config["payload_off"] == "false"
      assert config["icon"] == "mdi:car-tire-alert"
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "enabled_by_default")
    end
  end

  test "publishes missing MQTT topics as Home Assistant entities", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    enabled = %{
      "charge_current_request" => %{
        "platform" => "sensor",
        "name" => "Charge Current Request",
        "device_class" => "current",
        "state_class" => "measurement",
        "unit_of_measurement" => "A",
        "suggested_display_precision" => 0
      },
      "charge_current_request_max" => %{
        "platform" => "sensor",
        "name" => "Charge Current Request (Max)",
        "device_class" => "current",
        "state_class" => "measurement",
        "unit_of_measurement" => "A",
        "suggested_display_precision" => 0
      },
      "climate_keeper_mode" => %{
        "platform" => "sensor",
        "name" => "Climate Keeper",
        "icon" => "mdi:air-conditioner",
        "value_template" => "{{ value | title }}"
      },
      "service_mode" => %{
        "platform" => "binary_sensor",
        "name" => "Service Mode",
        "payload_on" => "true",
        "payload_off" => "false",
        "icon" => "mdi:wrench"
      },
      "sun_roof_percent_open" => %{
        "platform" => "sensor",
        "name" => "Sunroof Open",
        "state_class" => "measurement",
        "unit_of_measurement" => "%",
        "suggested_display_precision" => 0,
        "icon" => "mdi:car-convertible"
      },
      "sun_roof_state" => %{
        "platform" => "sensor",
        "name" => "Sunroof State",
        "icon" => "mdi:car-convertible",
        "value_template" => "{{ value | replace('_', ' ') | title }}"
      }
    }

    for {object_id, expected} <- enabled do
      config = decoded["components"][object_id]

      for {key, value} <- expected, do: assert(config[key] == value)
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "enabled_by_default")
    end

    center_display = decoded["components"]["center_display_state"]
    assert center_display["platform"] == "sensor"
    assert center_display["name"] == "Center Display"
    assert center_display["icon"] == "mdi:television"
    assert center_display["state_topic"] == "teslamate/cars/0/center_display_state"
    refute Map.has_key?(center_display, "enabled_by_default")

    for {code, state} <- [
          {0, "off"},
          {2, "standby"},
          {3, "charging"},
          {4, "on"},
          {5, "large_charging"},
          {6, "ready_to_unlock"},
          {7, "sentry_mode"},
          {8, "dog_mode"},
          {9, "media"}
        ] do
      assert String.contains?(center_display["value_template"], "#{code}: '#{state}'")
    end

    for {object_id, entity_name, icon} <- [
          {"download_perc", "Software Update Download", "mdi:download"},
          {"install_perc", "Software Update Installation", "mdi:update"}
        ] do
      config = decoded["components"][object_id]

      assert config["platform"] == "sensor"
      assert config["name"] == entity_name
      assert config["entity_category"] == "diagnostic"
      assert config["enabled_by_default"] == false
      assert config["state_class"] == "measurement"
      assert config["unit_of_measurement"] == "%"
      assert config["suggested_display_precision"] == 0
      assert config["icon"] == icon
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
    end
  end

  test "publishes raw location sensors disabled by default", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    for {object_id, entity_name, icon} <- [
          {"latitude", "Latitude", "mdi:latitude"},
          {"longitude", "Longitude", "mdi:longitude"}
        ] do
      config = decoded["components"][object_id]

      assert config["platform"] == "sensor"
      assert config["name"] == entity_name
      assert config["enabled_by_default"] == false
      assert config["state_class"] == "measurement"
      assert config["unit_of_measurement"] == "°"
      assert config["icon"] == icon
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "entity_category")
    end

    raw_location = decoded["components"]["raw_location"]
    assert raw_location["platform"] == "sensor"
    assert raw_location["name"] == "Location"
    assert raw_location["enabled_by_default"] == false
    assert raw_location["icon"] == "mdi:car"
    assert raw_location["state_topic"] == "teslamate/cars/0/location"
    assert raw_location["unique_id"] == "teslamate_0_location"
    assert raw_location["object_id"] == "tesla_location"
    refute Map.has_key?(raw_location, "component_id")
    refute Map.has_key?(raw_location, "entity_category")

    tracker = decoded["components"]["location"]
    assert tracker["platform"] == "device_tracker"
    assert Map.has_key?(tracker, "name")
    assert tracker["name"] == nil
    assert tracker["json_attributes_topic"] == "teslamate/cars/0/location"
    assert tracker["unique_id"] == "teslamate_0_location"
    refute Map.has_key?(tracker, "enabled_by_default")
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

  test "clear removes device and legacy discovery payloads", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.clear(0, [car_id: 0], {MqttPublisherMock, publisher_name})

    [{device_topic, "", publish_opts} | legacy_cleanup] = receive_configs()

    assert device_topic == "homeassistant/device/teslamate_0/config"
    assert publish_opts == [retain: true, qos: 1]
    assert legacy_cleanup != []
    assert Enum.all?(legacy_cleanup, &match?({_topic, "", [retain: true, qos: 1]}, &1))

    assert Enum.any?(legacy_cleanup, fn {topic, _, _} ->
             topic == "homeassistant/sensor/teslamate_0/display_name/config"
           end)

    assert Enum.any?(legacy_cleanup, fn {topic, _, _} ->
             topic == "homeassistant/binary_sensor/teslamate_0/locked/config"
           end)
  end

  test "stops before device discovery when a migration marker fails", %{test: name} do
    legacy_topic = "homeassistant/sensor/teslamate_0/display_name/config"
    publisher_name = start_publisher(name, %{legacy_topic => [{:error, :disconnected}]})

    assert {:error, :disconnected} =
             HomeAssistant.migrate(
               @summary,
               migration_opts(car_id: 0),
               {MqttPublisherMock, publisher_name}
             )

    assert [{^legacy_topic, @migration_payload, [retain: true, qos: 1]}] = receive_configs()
  end

  test "does not clear legacy topics when device discovery publishing fails", %{test: name} do
    device_topic = "homeassistant/device/teslamate_0/config"
    publisher_name = start_publisher(name, %{device_topic => [{:error, :disconnected}]})

    assert {:error, :disconnected} =
             HomeAssistant.migrate(
               @summary,
               migration_opts(car_id: 0),
               {MqttPublisherMock, publisher_name}
             )

    messages = receive_configs()
    assert {^device_topic, _payload, [retain: true, qos: 1]} = List.last(messages)

    assert messages
           |> Enum.drop(-1)
           |> Enum.all?(&match?({_topic, @migration_payload, [retain: true, qos: 1]}, &1))
  end

  test "stops legacy cleanup on the first failure", %{test: name} do
    legacy_topic = "homeassistant/sensor/teslamate_0/display_name/config"

    publisher_name =
      start_publisher(name, %{legacy_topic => [:ok, {:error, :disconnected}]})

    assert {:error, :disconnected} =
             HomeAssistant.migrate(
               @summary,
               migration_opts(car_id: 0),
               {MqttPublisherMock, publisher_name}
             )

    messages = receive_configs()
    assert {^legacy_topic, "", [retain: true, qos: 1]} = List.last(messages)

    assert Enum.count(messages, fn {topic, payload, _opts} ->
             topic == legacy_topic and payload == @migration_payload
           end) == 1

    assert Enum.count(messages, fn {topic, _payload, _opts} ->
             topic == "homeassistant/device/teslamate_0/config"
           end) == 1
  end

  test "returns an error when the complete device config cannot be published", %{test: name} do
    device_topic = "homeassistant/device/teslamate_0/config"

    publisher_name =
      start_publisher(name, %{device_topic => [:ok, {:error, :disconnected}]})

    assert {:error, :disconnected} =
             HomeAssistant.migrate(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    messages = receive_configs()
    assert {^device_topic, final_payload, [retain: true, qos: 1]} = List.last(messages)

    assert Jason.decode!(final_payload)["components"]["display_name"]["enabled_by_default"] ==
             false

    assert Enum.count(messages, fn {topic, _payload, _opts} -> topic == device_topic end) == 2
  end

  defp receive_device_config(timeout \\ 200) do
    assert_receive {MqttPublisherMock,
                    {:publish, "homeassistant/device/" <> _ = topic, payload,
                     [retain: true, qos: 1]}},
                   timeout

    {topic, Jason.decode!(payload)}
  end

  defp receive_configs(messages \\ []) do
    receive do
      {MqttPublisherMock, {:publish, topic, payload, opts}} ->
        receive_configs([{topic, payload, opts} | messages])
    after
      0 -> Enum.reverse(messages)
    end
  end
end
