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

  test "migrates legacy enabled components before cleanup and disabled components after cleanup",
       %{test: name} do
    publisher_name = start_publisher(name)

    opts =
      migration_opts(car_id: 0, namespace: nil, base_url: "https://teslamate.example.com/")

    started_at = System.monotonic_time(:millisecond)
    :ok = HomeAssistant.migrate(@summary, opts, {MqttPublisherMock, publisher_name})
    assert System.monotonic_time(:millisecond) - started_at >= 2 * @migration_delay

    messages = receive_configs()

    {migrations, [{topic, migration_payload, publish_opts} | remaining]} =
      Enum.split_while(messages, fn {topic, _payload, _opts} ->
        topic != "homeassistant/device/teslamate_0/config"
      end)

    {cleanup, [{final_topic, final_payload, final_publish_opts}]} =
      Enum.split_while(remaining, fn {topic, _payload, _opts} ->
        topic != "homeassistant/device/teslamate_0/config"
      end)

    assert migrations != []

    assert Enum.all?(
             migrations,
             &match?({_topic, @migration_payload, [retain: true, qos: 1]}, &1)
           )

    assert topic == "homeassistant/device/teslamate_0/config"
    assert publish_opts == [retain: true, qos: 1]
    assert final_topic == topic
    assert final_publish_opts == publish_opts

    migration_topics = Enum.map(migrations, &elem(&1, 0))
    cleanup_topics = Enum.map(cleanup, &elem(&1, 0))

    assert MapSet.subset?(MapSet.new(migration_topics), MapSet.new(cleanup_topics))
    assert Enum.all?(cleanup, &match?({_topic, "", [retain: true, qos: 1]}, &1))

    removed_update_available_topic =
      "homeassistant/binary_sensor/teslamate_0/update_available/config"

    refute removed_update_available_topic in migration_topics
    assert removed_update_available_topic in cleanup_topics

    update_available_topic = "homeassistant/sensor/teslamate_0/update_available/config"
    refute update_available_topic in migration_topics
    refute update_available_topic in cleanup_topics

    for position <- ["fl", "fr", "rl", "rr"] do
      removed_topic =
        "homeassistant/sensor/teslamate_0/tpms_pressure_#{position}_psi/config"

      refute removed_topic in migration_topics
      assert removed_topic in cleanup_topics
    end

    migration_decoded = Jason.decode!(migration_payload)
    decoded = Jason.decode!(final_payload)

    components = decoded["components"]
    assert map_size(components) > length(migrations)

    assert "homeassistant/device_tracker/teslamate_0/location/config" in migration_topics

    for {component_id, legacy_topic} <- [
          {"latitude", "homeassistant/sensor/teslamate_0/latitude/config"},
          {"raw_location", "homeassistant/sensor/teslamate_0/location/config"},
          {"charge_current_request",
           "homeassistant/sensor/teslamate_0/charge_current_request/config"},
          {"service_mode", "homeassistant/binary_sensor/teslamate_0/service_mode/config"},
          {"driver_front_window_open",
           "homeassistant/binary_sensor/teslamate_0/driver_front_window_open/config"},
          {"driver_front_door_open",
           "homeassistant/binary_sensor/teslamate_0/driver_front_door_open/config"}
        ] do
      assert Map.has_key?(components, component_id)
      refute legacy_topic in migration_topics
      refute legacy_topic in cleanup_topics
    end

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
        exterior_color: "DeepBlue",
        wheel_type: "AeroTurbine19",
        spoiler_type: "CarbonFiber",
        sun_roof_installed: true,
        version: "2026.26.1",
        car: car
    }

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    assert decoded["device"]["model"] ==
             ~s|Model S LR AWD (Deep Blue, Aero Turbine 19" Wheels, Carbon Fiber Spoiler, Sunroof)|

    assert decoded["device"]["sw_version"] == "2026.26.1"
  end

  test "publishes device metadata sources as disabled diagnostics", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    expected = %{
      "display_name" => {"Display Name", "mdi:form-textbox"},
      "exterior_color" => {"Exterior Color", "mdi:palette"},
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

    assert decoded["components"]["exterior_color"]["value_template"] ==
             "{{ value | regex_replace('(?<=[a-z])(?=[A-Z])', ' ') }}"

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

  test "humanizes enum-like sensor values with Home Assistant templates", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    components = decoded["components"]

    assert components["state"]["value_template"] == "{{ value | title }}"

    assert components["charging_state"]["value_template"] ==
             "{{ value | regex_replace('(?<=[a-z])(?=[A-Z])', ' ') }}"

    assert components["climate_keeper_mode"]["value_template"] == "{{ value | title }}"

    assert components["exterior_color"]["value_template"] ==
             "{{ value | regex_replace('(?<=[a-z])(?=[A-Z])', ' ') }}"

    assert components["sun_roof_state"]["value_template"] ==
             "{{ value | replace('_', ' ') | title }}"
  end

  test "derives charging status from the charging state", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    components = decoded["components"]

    charging_state = components["charging_state"]
    assert charging_state["platform"] == "sensor"
    assert charging_state["state_topic"] == "teslamate/cars/0/charging_state"

    charging = components["charging"]
    assert charging["platform"] == "binary_sensor"
    assert charging["name"] == "Charging"
    assert charging["device_class"] == "battery_charging"
    assert charging["payload_on"] == "true"
    assert charging["payload_off"] == "false"
    assert charging["value_template"] == "{{ 'true' if value == 'Charging' else 'false' }}"
    assert charging["icon"] == "mdi:battery-charging"
    assert charging["state_topic"] == "teslamate/cars/0/charging_state"
    assert charging["unique_id"] == "teslamate_0_charging"
    assert charging["object_id"] == "tesla_charging_state"
    refute Map.has_key?(charging, "component_id")
  end

  test "derives the parking brake from documented shift states", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    parking_brake = decoded["components"]["park_brake"]

    assert parking_brake["name"] == "Parking Brake"

    assert parking_brake["value_template"] ==
             "{% if value in ['', 'P'] %}ON{% elif value in ['D', 'N', 'R'] %}OFF{% else %}None{% endif %}"
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

  test "aligns measurement sensors with the custom integration", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    sensor = %{"platform" => "sensor"}
    measurement = Map.put(sensor, "state_class", "measurement")
    integer_measurement = Map.put(measurement, "suggested_display_precision", 0)
    integer_angle_measurement = Map.put(integer_measurement, "state_class", "measurement_angle")

    distance =
      Map.merge(integer_measurement, %{
        "device_class" => "distance",
        "unit_of_measurement" => "km",
        "icon" => "mdi:map-marker-distance"
      })

    temperature =
      Map.merge(measurement, %{
        "device_class" => "temperature",
        "unit_of_measurement" => "°C",
        "suggested_display_precision" => 1,
        "icon" => "mdi:thermometer-lines"
      })

    expected = %{
      "charge_energy_added" =>
        {"charge_energy_added",
         Map.merge(sensor, %{
           "name" => "Energy Added",
           "device_class" => "energy",
           "state_class" => "total_increasing",
           "unit_of_measurement" => "kWh",
           "suggested_display_precision" => 1,
           "icon" => "mdi:battery-charging"
         })},
      "charge_limit_soc" =>
        {"charge_limit_soc",
         Map.merge(integer_measurement, %{
           "name" => "Charge Limit",
           "unit_of_measurement" => "%",
           "icon" => "mdi:battery-charging-90"
         })},
      "charger_actual_current" =>
        {"charger_actual_current",
         Map.merge(integer_measurement, %{
           "name" => "Charger Current",
           "device_class" => "current",
           "unit_of_measurement" => "A"
         })},
      "charger_power" =>
        {"charger_power",
         Map.merge(integer_measurement, %{
           "name" => "Charger Power",
           "device_class" => "power",
           "unit_of_measurement" => "kW"
         })},
      "charger_voltage" =>
        {"charger_voltage",
         Map.merge(integer_measurement, %{
           "name" => "Charger Voltage",
           "device_class" => "voltage",
           "unit_of_measurement" => "V"
         })},
      "elevation" =>
        {"elevation",
         Map.merge(integer_measurement, %{
           "name" => "Elevation",
           "device_class" => "distance",
           "unit_of_measurement" => "m",
           "icon" => "mdi:image-filter-hdr"
         })},
      "heading" =>
        {"heading",
         Map.merge(integer_angle_measurement, %{
           "name" => "Heading",
           "unit_of_measurement" => "°",
           "icon" => "mdi:compass"
         })},
      "speed" =>
        {"speed",
         Map.merge(integer_measurement, %{
           "name" => "Speed",
           "device_class" => "speed",
           "unit_of_measurement" => "km/h",
           "icon" => "mdi:speedometer"
         })},
      "est_battery_range" =>
        {"est_battery_range_km", Map.put(distance, "name", "Range (Estimated)")},
      "ideal_battery_range" =>
        {"ideal_battery_range_km", Map.put(distance, "name", "Range (Ideal)")},
      "rated_battery_range" =>
        {"rated_battery_range_km", Map.put(distance, "name", "Range (Rated)")},
      "inside_temp" => {"inside_temp", Map.put(temperature, "name", "Temperature (Inside)")},
      "outside_temp" => {"outside_temp", Map.put(temperature, "name", "Temperature (Outside)")},
      "odometer" =>
        {"odometer",
         Map.merge(sensor, %{
           "name" => "Odometer",
           "device_class" => "distance",
           "state_class" => "total_increasing",
           "unit_of_measurement" => "km",
           "suggested_display_precision" => 0,
           "icon" => "mdi:counter"
         })},
      "power" =>
        {"power",
         Map.merge(integer_measurement, %{
           "name" => "Power",
           "device_class" => "power",
           "unit_of_measurement" => "kW"
         })},
      "scheduled_charging_start_time" =>
        {"scheduled_charging_start_time",
         Map.merge(sensor, %{
           "name" => "Charging Start Time",
           "device_class" => "timestamp"
         })},
      "since" =>
        {"since",
         Map.merge(sensor, %{
           "name" => "Last Seen",
           "device_class" => "timestamp",
           "icon" => "mdi:timer-sand"
         })},
      "time_to_full_charge" =>
        {"time_to_full_charge",
         Map.merge(measurement, %{
           "name" => "Charging Time Remaining",
           "device_class" => "duration",
           "unit_of_measurement" => "h",
           "icon" => "mdi:timer"
         })},
      "usable_battery_level" =>
        {"usable_battery_level",
         Map.merge(measurement, %{
           "name" => "Usable Battery",
           "device_class" => "battery",
           "unit_of_measurement" => "%"
         })}
    }

    for {object_id, {topic_key, expected_config}} <- expected do
      config = decoded["components"][object_id]

      assert Map.drop(config, ["object_id", "unique_id"]) ==
               Map.put(expected_config, "state_topic", "teslamate/cars/0/#{topic_key}")
    end
  end

  test "locked binary sensor is inverted", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["locked"]
    assert config["platform"] == "binary_sensor"
    assert config["name"] == "Lock"
    assert config["payload_on"] == "false"
    assert config["payload_off"] == "true"
    assert config["device_class"] == "lock"
    assert config["state_topic"] == "teslamate/cars/0/locked"
  end

  test "aligns vehicle status binary sensors with the custom integration", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    expected = [
      {"charge_port_door_open", "Charge Port", "opening", "mdi:ev-plug-tesla"},
      {"frunk_open", "Frunk", "door", "mdi:car"},
      {"trunk_open", "Trunk", "door", "mdi:car"},
      {"is_climate_on", "Climate", "running", "mdi:air-conditioner"},
      {"is_preconditioning", "Preconditioning", "running", "mdi:air-conditioner"},
      {"is_user_present", "User", "presence", "mdi:human-greeting"},
      {"plugged_in", "Plug", "plug", "mdi:ev-station"},
      {"service_mode", "Service Mode", "running", "mdi:wrench"},
      {"sentry_mode", "Sentry Mode", "running", "mdi:cctv"}
    ]

    for {object_id, entity_name, device_class, icon} <- expected do
      config = decoded["components"][object_id]

      assert config["platform"] == "binary_sensor"
      assert config["name"] == entity_name
      assert config["device_class"] == device_class
      assert config["payload_on"] == "true"
      assert config["payload_off"] == "false"
      assert config["icon"] == icon
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "entity_category")
      refute Map.has_key?(config, "enabled_by_default")
    end
  end

  test "publishes aggregate and individual cabin door sensors", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    for {object_id, entity_name} <- [
          {"doors_open", "Doors"},
          {"driver_front_door_open", "Door (Driver Front)"},
          {"driver_rear_door_open", "Door (Driver Rear)"},
          {"passenger_front_door_open", "Door (Passenger Front)"},
          {"passenger_rear_door_open", "Door (Passenger Rear)"}
        ] do
      config = decoded["components"][object_id]

      assert config["platform"] == "binary_sensor"
      assert config["name"] == entity_name
      assert config["device_class"] == "door"
      assert config["payload_on"] == "true"
      assert config["payload_off"] == "false"
      assert config["icon"] == "mdi:car-door"
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "entity_category")
      refute Map.has_key?(config, "enabled_by_default")
    end
  end

  test "publishes aggregate and individual cabin window sensors", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    for {object_id, entity_name} <- [
          {"windows_open", "Windows"},
          {"driver_front_window_open", "Window (Driver Front)"},
          {"driver_rear_window_open", "Window (Driver Rear)"},
          {"passenger_front_window_open", "Window (Passenger Front)"},
          {"passenger_rear_window_open", "Window (Passenger Rear)"}
        ] do
      config = decoded["components"][object_id]

      assert config["platform"] == "binary_sensor"
      assert config["name"] == entity_name
      assert config["device_class"] == "window"
      assert config["payload_on"] == "true"
      assert config["payload_off"] == "false"
      assert config["icon"] == "mdi:car-door"
      assert config["state_topic"] == "teslamate/cars/0/#{object_id}"
      refute Map.has_key?(config, "entity_category")
      refute Map.has_key?(config, "enabled_by_default")
    end
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
        "device_class" => "running",
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
    assert raw_location["unique_id"] == "teslamate_0_raw_location"
    assert raw_location["object_id"] == "tesla_location"
    refute Map.has_key?(raw_location, "component_id")
    refute Map.has_key?(raw_location, "entity_category")

    tracker = decoded["components"]["location"]
    assert tracker["platform"] == "device_tracker"
    assert Map.has_key?(tracker, "name")
    assert tracker["name"] == nil
    assert tracker["json_attributes_topic"] == "teslamate/cars/0/location"
    assert tracker["unique_id"] == "teslamate_0_location"
    refute tracker["unique_id"] == raw_location["unique_id"]
    refute Map.has_key?(tracker, "enabled_by_default")
  end

  test "health binary sensor reports problems", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["healthy"]
    assert config["platform"] == "binary_sensor"
    assert config["name"] == "Health"
    assert config["device_class"] == "problem"
    assert config["entity_category"] == "diagnostic"
    assert config["payload_on"] == "false"
    assert config["payload_off"] == "true"
    assert config["icon"] == "mdi:heart-pulse"
    assert config["state_topic"] == "teslamate/cars/0/healthy"
  end

  test "publishes active route entities with canonical values and robust availability", %{
    test: name
  } do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    components = decoded["components"]

    availability = %{
      "topic" => "teslamate/cars/0/active_route",
      "value_template" =>
        "{{ 'online' if value_json is mapping and not value_json.get('error') else 'offline' }}"
    }

    for {object_id, entity_name, field} <- [
          {"active_route_destination", "Active Route Destination", "destination"},
          {"active_route_energy_at_arrival", "Active Route Energy At Arrival",
           "energy_at_arrival"},
          {"active_route_distance_to_arrival", "Active Route Distance To Arrival",
           "miles_to_arrival"},
          {"active_route_minutes_to_arrival", "Active Route Minutes To Arrival",
           "minutes_to_arrival"},
          {"active_route_traffic_minutes_delay", "Active Route Traffic Minutes Delay",
           "traffic_minutes_delay"}
        ] do
      config = components[object_id]

      assert config["name"] == entity_name
      assert config["state_topic"] == "teslamate/cars/0/active_route"
      assert config["availability"] == availability

      assert config["value_template"] ==
               "{% if value_json is mapping and not value_json.get('error') and value_json.get('#{field}') is not none %}{{ value_json.get('#{field}') }}{% endif %}"
    end

    distance = components["active_route_distance_to_arrival"]
    assert distance["device_class"] == "distance"
    assert distance["unit_of_measurement"] == "mi"
    refute String.contains?(distance["value_template"], "1.609")

    tracker = components["active_route_location"]
    assert tracker["name"] == "Active Route Location"
    assert tracker["availability"] == availability
    assert tracker["json_attributes_topic"] == "teslamate/cars/0/active_route"

    assert tracker["json_attributes_template"] ==
             "{% if value_json is mapping and not value_json.get('error') and value_json.get('location') is mapping %}{{ value_json.get('location') | tojson }}{% else %}{}{% endif %}"
  end

  test "publishes battery as device entity", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["battery_level"]
    assert config["name"] == "Battery"
    assert config["device_class"] == "battery"
    assert config["state_class"] == "measurement"
    assert config["unit_of_measurement"] == "%"
    refute Map.has_key?(config, "icon")
  end

  test "publishes charger phases as an integer measurement", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    config = decoded["components"]["charger_phases"]
    assert config["name"] == "Charger Phases"
    assert config["state_class"] == "measurement"
    assert config["unit_of_measurement"] == "phases"
    assert config["suggested_display_precision"] == 0
    assert config["icon"] == "mdi:sine-wave"
  end

  test "publishes software update entities", %{test: name} do
    publisher_name = start_publisher(name)
    summary = %{@summary | update_available: true}

    :ok = HomeAssistant.publish(summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()
    components = decoded["components"]

    update = components["update"]
    assert update["platform"] == "update"
    assert update["name"] == "Update"
    assert update["device_class"] == "firmware"
    assert update["entity_category"] == "diagnostic"
    assert update["state_topic"] == "teslamate/cars/0/software_update"
    refute Map.has_key?(update, "latest_version_topic")
    refute Map.has_key?(update, "command_topic")

    version = components["version"]
    assert version["platform"] == "sensor"
    assert version["name"] == "Version"
    assert version["entity_category"] == "diagnostic"
    assert version["enabled_by_default"] == false
    assert version["icon"] == "mdi:numeric"

    update_version = components["update_version"]
    assert update_version["platform"] == "sensor"
    assert update_version["entity_category"] == "diagnostic"
    assert update_version["enabled_by_default"] == false
    assert update_version["icon"] == "mdi:numeric"

    update_available = components["update_available"]
    assert update_available["platform"] == "sensor"
    assert update_available["entity_category"] == "diagnostic"
    assert update_available["enabled_by_default"] == false
    refute Map.has_key?(update_available, "device_class")
    refute Map.has_key?(update_available, "icon")
    refute Map.has_key?(update_available, "payload_on")
    refute Map.has_key?(update_available, "payload_off")
  end

  test "publishes tire pressures in bar without derived psi sensors", %{test: name} do
    publisher_name = start_publisher(name)

    :ok = HomeAssistant.publish(@summary, [car_id: 0], {MqttPublisherMock, publisher_name})

    {_topic, decoded} = receive_device_config()

    for {position, entity_name} <- [
          {"fl", "Tire Pressure (Front Left)"},
          {"fr", "Tire Pressure (Front Right)"},
          {"rl", "Tire Pressure (Rear Left)"},
          {"rr", "Tire Pressure (Rear Right)"}
        ] do
      refute Map.has_key?(decoded["components"], "tpms_pressure_#{position}_psi")

      config = decoded["components"]["tpms_pressure_#{position}"]
      assert config["platform"] == "sensor"
      assert config["name"] == entity_name
      assert config["device_class"] == "pressure"
      assert config["state_class"] == "measurement"
      assert config["unit_of_measurement"] == "bar"
      assert config["suggested_display_precision"] == 1
      assert config["icon"] == "mdi:gauge"
      assert config["state_topic"] == "teslamate/cars/0/tpms_pressure_#{position}"
    end
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

    assert Enum.any?(legacy_cleanup, fn {topic, _, _} ->
             topic == "homeassistant/binary_sensor/teslamate_0/update_available/config"
           end)

    assert Enum.any?(legacy_cleanup, fn {topic, _, _} ->
             topic == "homeassistant/sensor/teslamate_0/tpms_pressure_fl_psi/config"
           end)

    refute Enum.any?(legacy_cleanup, fn {topic, _, _} ->
             topic == "homeassistant/update/teslamate_0/update/config"
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
             HomeAssistant.migrate(
               @summary,
               migration_opts(car_id: 0),
               {MqttPublisherMock, publisher_name}
             )

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
