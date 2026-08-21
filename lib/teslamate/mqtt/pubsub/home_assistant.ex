defmodule TeslaMate.Mqtt.PubSub.HomeAssistant do
  @moduledoc """
  Publishes Home Assistant MQTT device discovery configuration payloads, one
  per vehicle, so users can opt out of manually configuring the MQTT sensors
  in `configuration.yaml`.

  See: https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery
  """

  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Vehicles.Vehicle
  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.Car

  @discovery_prefix "homeassistant"
  @migration_delay :timer.seconds(1)
  @migration_payload Jason.encode!(%{migrate_discovery: true})
  @node "teslamate"
  @legacy_discovery_entities [
    {"sensor", "display_name"},
    {"sensor", "state"},
    {"sensor", "charging_state"},
    {"sensor", "since"},
    {"sensor", "version"},
    {"sensor", "update_version"},
    {"sensor", "model"},
    {"sensor", "trim_badging"},
    {"sensor", "exterior_color"},
    {"sensor", "wheel_type"},
    {"sensor", "spoiler_type"},
    {"sensor", "geofence"},
    {"sensor", "shift_state"},
    {"binary_sensor", "park_brake"},
    {"sensor", "power"},
    {"sensor", "speed"},
    {"sensor", "heading"},
    {"sensor", "elevation"},
    {"sensor", "inside_temp"},
    {"sensor", "outside_temp"},
    {"sensor", "odometer"},
    {"sensor", "est_battery_range"},
    {"sensor", "rated_battery_range"},
    {"sensor", "ideal_battery_range"},
    {"sensor", "battery_level"},
    {"sensor", "usable_battery_level"},
    {"sensor", "charge_energy_added"},
    {"sensor", "charge_limit_soc"},
    {"sensor", "charger_actual_current"},
    {"sensor", "charger_phases"},
    {"sensor", "charger_power"},
    {"sensor", "charger_voltage"},
    {"sensor", "scheduled_charging_start_time"},
    {"sensor", "time_to_full_charge"},
    {"sensor", "tpms_pressure_fl"},
    {"sensor", "tpms_pressure_fr"},
    {"sensor", "tpms_pressure_rl"},
    {"sensor", "tpms_pressure_rr"},
    {"sensor", "active_route_destination"},
    {"sensor", "active_route_energy_at_arrival"},
    {"sensor", "active_route_distance_to_arrival"},
    {"sensor", "active_route_minutes_to_arrival"},
    {"sensor", "active_route_traffic_minutes_delay"},
    {"device_tracker", "location"},
    {"device_tracker", "active_route_location"},
    {"binary_sensor", "healthy"},
    {"binary_sensor", "sentry_mode"},
    {"binary_sensor", "windows_open"},
    {"binary_sensor", "doors_open"},
    {"binary_sensor", "trunk_open"},
    {"binary_sensor", "frunk_open"},
    {"binary_sensor", "is_user_present"},
    {"binary_sensor", "is_climate_on"},
    {"binary_sensor", "is_preconditioning"},
    {"binary_sensor", "plugged_in"},
    {"binary_sensor", "charge_port_door_open"},
    {"binary_sensor", "locked"}
  ]
  @removed_legacy_discovery_entities [
    {"binary_sensor", "update_available"},
    {"sensor", "tpms_pressure_fl_psi"},
    {"sensor", "tpms_pressure_fr_psi"},
    {"sensor", "tpms_pressure_rl_psi"},
    {"sensor", "tpms_pressure_rr_psi"}
  ]
  @version Mix.Project.config()[:version]

  @type publish_opts :: [
          car_id: pos_integer(),
          namespace: String.t() | nil,
          base_url: String.t() | nil,
          discovery_prefix: String.t(),
          migration_delay: non_neg_integer()
        ]

  @doc """
  Publishes a device discovery configuration payload containing every entity
  derived from the given vehicle summary.

  The payload is published retained (QoS 1) to
  `<discovery_prefix>/device/<node>/config` where `node` is
  `#{@node}_<car_id>` (with the `MQTT_NAMESPACE` inserted after `#{@node}` when
  set). Returns `:ok` on success.
  """
  @spec publish(term(), publish_opts(), term()) :: :ok | {:error, term()}
  def publish(%Summary{} = summary, opts, publisher) do
    {prefix, node, device_payload} = discovery_config(summary, opts)

    publish_device_config(prefix, node, device_payload, publisher)
  end

  @doc """
  Migrates any existing single-component discovery configs to a device
  discovery config and then clears the old retained configs. Components that
  are disabled by default are omitted from the first device config and added
  in a final device config after legacy cleanup. This prevents Home Assistant
  from treating cleanup on a legacy topic as removal of a disabled component
  from the shared device topic.

  Publishing stops at the first error. Every legacy migration marker must be
  published successfully before waiting for Home Assistant to process the
  markers and publishing the migration device config. Legacy cleanup starts
  only after that config succeeds. After cleanup, Home Assistant is given the
  same processing delay before the complete device config is published.
  Retrying safely restarts the sequence.
  """
  @spec migrate(term(), publish_opts(), term()) :: :ok | {:error, term()}
  def migrate(%Summary{} = summary, opts, publisher) do
    entity_configs = entities()
    {prefix, node, device_payload} = discovery_config(summary, opts, entity_configs)
    migration_delay = Keyword.get(opts, :migration_delay, @migration_delay)

    migration_entity_configs =
      Enum.reject(entity_configs, fn {_component, _object_id, config} ->
        Map.get(config, :enabled_by_default, true) == false
      end)

    {^prefix, ^node, migration_device_payload} =
      discovery_config(summary, opts, migration_entity_configs)

    with :ok <- publish_legacy_configs(prefix, node, @migration_payload, publisher),
         :ok <- Process.sleep(migration_delay),
         :ok <- publish_device_config(prefix, node, migration_device_payload, publisher),
         :ok <- publish_legacy_configs(prefix, node, "", publisher),
         :ok <- Process.sleep(migration_delay) do
      publish_device_config(prefix, node, device_payload, publisher)
    end
  end

  defp discovery_config(%Summary{} = summary, opts) do
    discovery_config(summary, opts, entities())
  end

  defp discovery_config(%Summary{} = summary, opts, entity_configs) do
    car_id = Keyword.fetch!(opts, :car_id)
    namespace = Keyword.get(opts, :namespace)
    prefix = Keyword.get(opts, :discovery_prefix, @discovery_prefix)
    node = node(car_id, namespace)

    components =
      Map.new(entity_configs, fn {component, object_id, config} ->
        component_id = Map.get(config, :component_id, object_id)

        config
        |> Map.delete(:component_id)
        |> resolve_topics(car_id, namespace)
        |> Map.put(:platform, component)
        |> Map.put(:unique_id, "#{node}_#{component_id}")
        |> Map.put(:object_id, "tesla_#{object_id}")
        |> then(&{component_id, &1})
      end)

    device_payload =
      %{
        components: components,
        device: device(summary, opts),
        origin: origin()
      }
      |> Jason.encode!()

    {prefix, node, device_payload}
  end

  defp publish_device_config(prefix, node, payload, publisher) do
    call(publisher, :publish, [
      device_discovery_topic(prefix, node),
      payload,
      [retain: true, qos: 1]
    ])
  end

  @doc """
  Builds the Home Assistant device metadata rendered into the discovery
  configuration payload.
  """
  @spec device(Summary.t(), publish_opts()) :: map()
  def device(%Summary{} = summary, opts) do
    car_id = Keyword.fetch!(opts, :car_id)
    namespace = Keyword.get(opts, :namespace)
    base_url = Keyword.get(opts, :base_url)
    name = summary.display_name || car_name(summary) || "Tesla ##{car_id}"
    model = model_name(summary) || "Tesla"

    %{
      identifiers: [device_identifier(car_id, namespace)],
      manufacturer: "Tesla",
      name: name,
      model: model
    }
    |> maybe_put(:configuration_url, base_url)
    |> maybe_put(:sw_version, non_empty(summary.version))
  end

  @doc """
  Publishes empty retained payloads to clear a vehicle's device discovery topic
  and any legacy single-component topics, so its entities are removed from Home
  Assistant when discovery is disabled or the vehicle is removed.
  """
  @spec clear(pos_integer(), publish_opts(), term()) :: :ok | {:error, term()}
  def clear(car_id, opts, publisher) do
    namespace = Keyword.get(opts, :namespace)
    prefix = Keyword.get(opts, :discovery_prefix, @discovery_prefix)
    node = node(car_id, namespace)

    with :ok <-
           call(publisher, :publish, [
             device_discovery_topic(prefix, node),
             "",
             [retain: true, qos: 1]
           ]) do
      publish_legacy_configs(prefix, node, "", publisher)
    end
  end

  defp publish_legacy_configs(prefix, node, payload, publisher) do
    entities =
      for {component, object_id, _config} <- entities(),
          {component, object_id} in @legacy_discovery_entities,
          do: {component, object_id}

    entities =
      if payload == "", do: entities ++ @removed_legacy_discovery_entities, else: entities

    Enum.reduce_while(entities, :ok, fn {component, object_id}, _acc ->
      topic = component_discovery_topic(prefix, component, node, object_id)

      case call(publisher, :publish, [topic, payload, [retain: true, qos: 1]]) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp device_discovery_topic(prefix, node) do
    Enum.join([prefix, "device", node, "config"], "/")
  end

  defp component_discovery_topic(prefix, component, node, object_id) do
    Enum.join([prefix, component, node, object_id, "config"], "/")
  end

  defp origin do
    %{
      name: "TeslaMate",
      sw_version: @version,
      support_url: "https://docs.teslamate.org/"
    }
  end

  defp resolve_topics(config, car_id, namespace) do
    Enum.reduce(config, %{}, fn
      {:state_topic_key, key}, acc ->
        Map.put(acc, :state_topic, topic(key, car_id, namespace))

      {:json_attributes_topic_key, key}, acc ->
        Map.put(acc, :json_attributes_topic, topic(key, car_id, namespace))

      {:availability_topic_key, key}, acc ->
        availability = %{
          topic: topic(key, car_id, namespace),
          value_template: active_route_availability_template()
        }

        Map.put(acc, :availability, availability)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp topic(key, car_id, namespace) do
    ["teslamate", namespace, "cars", car_id, key]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("/")
  end

  defp node(car_id, namespace) do
    [@node, namespace, car_id]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("_")
  end

  defp model_name(%Summary{} = summary) do
    model =
      case non_empty(summary.model) do
        nil ->
          nil

        model ->
          [
            Vehicle.format_model(model),
            marketing_name(summary) || non_empty(summary.trim_badging)
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")
      end

    details =
      []
      |> maybe_add_exterior_color(summary.exterior_color)
      |> maybe_add_wheels(summary.wheel_type)
      |> maybe_add_spoiler(summary.spoiler_type)
      |> maybe_add_sunroof(summary.sun_roof_installed)

    case {model, details} do
      {nil, _details} -> nil
      {model, []} -> model
      {model, details} -> "#{model} (#{Enum.join(details, ", ")})"
    end
  end

  defp maybe_add_exterior_color(details, exterior_color) do
    case non_empty(exterior_color) do
      nil -> details
      exterior_color -> details ++ [split_camel_case(exterior_color)]
    end
  end

  defp maybe_add_wheels(details, wheel_type) do
    case non_empty(wheel_type) do
      nil -> details
      wheel_type -> details ++ ["#{format_wheel_type(wheel_type)} Wheels"]
    end
  end

  defp maybe_add_spoiler(details, spoiler_type) do
    case format_spoiler_type(spoiler_type) do
      nil -> details
      spoiler_type -> details ++ ["#{spoiler_type} Spoiler"]
    end
  end

  defp maybe_add_sunroof(details, true), do: details ++ ["Sunroof"]
  defp maybe_add_sunroof(details, _sun_roof_installed), do: details

  defp format_wheel_type(wheel_type) do
    case Regex.named_captures(
           ~r/^(?<name>[A-Za-z]+)(?<size>\d+)(?<suffix>[A-Za-z]*)$/,
           wheel_type
         ) do
      %{"name" => name, "size" => size, "suffix" => suffix} ->
        [split_camel_case(name), "#{size}\"", split_camel_case(suffix)]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")

      nil ->
        split_camel_case(wheel_type)
    end
  end

  defp format_spoiler_type(spoiler_type) do
    case non_empty(spoiler_type) do
      nil ->
        nil

      spoiler_type ->
        if String.downcase(spoiler_type) == "none", do: nil, else: split_camel_case(spoiler_type)
    end
  end

  defp split_camel_case(value), do: Regex.replace(~r/(?<=[a-z])(?=[A-Z])/, value, " ")

  defp humanize_value_template(:title_case), do: "{{ value | title }}"

  defp humanize_value_template(:camel_case),
    do: "{{ value | regex_replace('(?<=[a-z])(?=[A-Z])', ' ') }}"

  defp humanize_value_template(:snake_case),
    do: "{{ value | replace('_', ' ') | title }}"

  defp active_route_availability_template do
    "{{ 'online' if value_json is mapping and not value_json.get('error') else 'offline' }}"
  end

  defp active_route_value_template(key) do
    "{% if value_json is mapping and not value_json.get('error') and value_json.get('#{key}') is not none %}{{ value_json.get('#{key}') }}{% endif %}"
  end

  defp active_route_location_template do
    "{% if value_json is mapping and not value_json.get('error') and value_json.get('location') is mapping %}{{ value_json.get('location') | tojson }}{% else %}{}{% endif %}"
  end

  defp non_empty(value) when is_binary(value) and value != "", do: value
  defp non_empty(_value), do: nil

  defp device_identifier(car_id, namespace) do
    [@node, namespace, "car", car_id] |> Enum.reject(&is_nil/1) |> Enum.join("_")
  end

  defp car_name(%Summary{car: %Car{name: name}}) when is_binary(name) and name != "", do: name
  defp car_name(_), do: nil

  defp marketing_name(%Summary{car: %Car{marketing_name: name}}), do: non_empty(name)
  defp marketing_name(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp entities do
    true_false = %{payload_on: "true", payload_off: "false"}

    [
      # --- Generic sensors (string/raw values) ---
      {"sensor", "display_name",
       %{
         state_topic_key: :display_name,
         name: "Display Name",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:form-textbox"
       }},
      {"sensor", "latitude",
       %{
         state_topic_key: :latitude,
         name: "Latitude",
         enabled_by_default: false,
         state_class: "measurement",
         unit_of_measurement: "°",
         icon: "mdi:latitude"
       }},
      {"sensor", "location",
       %{
         component_id: "raw_location",
         state_topic_key: :location,
         name: "Location",
         enabled_by_default: false,
         icon: "mdi:car"
       }},
      {"sensor", "longitude",
       %{
         state_topic_key: :longitude,
         name: "Longitude",
         enabled_by_default: false,
         state_class: "measurement",
         unit_of_measurement: "°",
         icon: "mdi:longitude"
       }},
      {"sensor", "state",
       %{
         state_topic_key: :state,
         name: "State",
         icon: "mdi:car-connected",
         value_template: humanize_value_template(:title_case)
       }},
      {"sensor", "charging_state",
       %{
         state_topic_key: :charging_state,
         name: "Charging State",
         icon: "mdi:ev-station",
         value_template: humanize_value_template(:camel_case)
       }},
      {"binary_sensor", "charging_state",
       %{
         component_id: "charging",
         state_topic_key: :charging_state,
         name: "Charging",
         device_class: "battery_charging",
         payload_on: "true",
         payload_off: "false",
         value_template: "{{ 'true' if value == 'Charging' else 'false' }}",
         icon: "mdi:battery-charging"
       }},
      {"sensor", "climate_keeper_mode",
       %{
         state_topic_key: :climate_keeper_mode,
         name: "Climate Keeper",
         icon: "mdi:air-conditioner",
         value_template: humanize_value_template(:title_case)
       }},
      {"sensor", "center_display_state",
       %{
         state_topic_key: :center_display_state,
         name: "Center Display",
         icon: "mdi:television",
         value_template:
           "{% set states = {0: 'off', 2: 'standby', 3: 'charging', 4: 'on', 5: 'large_charging', 6: 'ready_to_unlock', 7: 'sentry_mode', 8: 'dog_mode', 9: 'media'} %}{% set state = states.get(value | int(-1)) %}{% if state %}{{ state }}{% endif %}"
       }},
      {"sensor", "since",
       %{
         state_topic_key: :since,
         name: "Last Seen",
         device_class: "timestamp",
         icon: "mdi:timer-sand"
       }},
      {"sensor", "version",
       %{
         state_topic_key: :version,
         name: "Version",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:numeric"
       }},
      {"sensor", "update_available",
       %{
         state_topic_key: :update_available,
         name: "Update Available",
         entity_category: "diagnostic",
         enabled_by_default: false
       }},
      {"sensor", "update_version",
       %{
         state_topic_key: :update_version,
         name: "Update Version",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:numeric"
       }},
      {"sensor", "model",
       %{
         state_topic_key: :model,
         name: "Model",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:form-textbox"
       }},
      {"sensor", "trim_badging",
       %{
         state_topic_key: :trim_badging,
         name: "Trim Badging",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:shield-star-outline"
       }},
      {"sensor", "exterior_color",
       %{
         state_topic_key: :exterior_color,
         name: "Exterior Color",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:palette",
         value_template: humanize_value_template(:camel_case)
       }},
      {"sensor", "wheel_type",
       %{
         state_topic_key: :wheel_type,
         name: "Wheel Type",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:tire"
       }},
      {"sensor", "spoiler_type",
       %{
         state_topic_key: :spoiler_type,
         name: "Spoiler Type",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:car-sports"
       }},
      {"sensor", "geofence", %{state_topic_key: :geofence, name: "Geofence", icon: "mdi:earth"}},
      {"sensor", "shift_state",
       %{state_topic_key: :shift_state, name: "Shift State", icon: "mdi:car-shift-pattern"}},

      # Park brake - binary sensor derived from shift_state
      {"binary_sensor", "park_brake",
       %{
         state_topic_key: :shift_state,
         name: "Parking Brake",
         value_template:
           "{% if value in ['', 'P'] %}ON{% elif value in ['D', 'N', 'R'] %}OFF{% else %}None{% endif %}",
         icon: "mdi:car-brake-parking"
       }},

      # --- Numeric sensors ---
      {"sensor", "power",
       %{
         state_topic_key: :power,
         name: "Power",
         device_class: "power",
         state_class: "measurement",
         unit_of_measurement: "kW",
         suggested_display_precision: 0
       }},
      {"sensor", "speed",
       %{
         state_topic_key: :speed,
         name: "Speed",
         device_class: "speed",
         state_class: "measurement",
         unit_of_measurement: "km/h",
         suggested_display_precision: 0,
         icon: "mdi:speedometer"
       }},
      {"sensor", "heading",
       %{
         state_topic_key: :heading,
         name: "Heading",
         state_class: "measurement_angle",
         unit_of_measurement: "°",
         suggested_display_precision: 0,
         icon: "mdi:compass"
       }},
      {"sensor", "elevation",
       %{
         state_topic_key: :elevation,
         name: "Elevation",
         device_class: "distance",
         state_class: "measurement",
         unit_of_measurement: "m",
         suggested_display_precision: 0,
         icon: "mdi:image-filter-hdr"
       }},
      {"sensor", "inside_temp",
       %{
         state_topic_key: :inside_temp,
         name: "Temperature (Inside)",
         device_class: "temperature",
         state_class: "measurement",
         unit_of_measurement: "°C",
         suggested_display_precision: 1,
         icon: "mdi:thermometer-lines"
       }},
      {"sensor", "outside_temp",
       %{
         state_topic_key: :outside_temp,
         name: "Temperature (Outside)",
         device_class: "temperature",
         state_class: "measurement",
         unit_of_measurement: "°C",
         suggested_display_precision: 1,
         icon: "mdi:thermometer-lines"
       }},
      {"sensor", "odometer",
       %{
         state_topic_key: :odometer,
         name: "Odometer",
         device_class: "distance",
         state_class: "total_increasing",
         unit_of_measurement: "km",
         suggested_display_precision: 0,
         icon: "mdi:counter"
       }},
      {"sensor", "est_battery_range",
       %{
         state_topic_key: :est_battery_range_km,
         name: "Range (Estimated)",
         device_class: "distance",
         state_class: "measurement",
         unit_of_measurement: "km",
         suggested_display_precision: 0,
         icon: "mdi:map-marker-distance"
       }},
      {"sensor", "rated_battery_range",
       %{
         state_topic_key: :rated_battery_range_km,
         name: "Range (Rated)",
         device_class: "distance",
         state_class: "measurement",
         unit_of_measurement: "km",
         suggested_display_precision: 0,
         icon: "mdi:map-marker-distance"
       }},
      {"sensor", "ideal_battery_range",
       %{
         state_topic_key: :ideal_battery_range_km,
         name: "Range (Ideal)",
         device_class: "distance",
         state_class: "measurement",
         unit_of_measurement: "km",
         suggested_display_precision: 0,
         icon: "mdi:map-marker-distance"
       }},
      {"sensor", "battery_level",
       %{
         state_topic_key: :battery_level,
         name: "Battery",
         device_class: "battery",
         state_class: "measurement",
         unit_of_measurement: "%"
       }},
      {"sensor", "usable_battery_level",
       %{
         state_topic_key: :usable_battery_level,
         name: "Usable Battery",
         device_class: "battery",
         state_class: "measurement",
         unit_of_measurement: "%"
       }},
      {"sensor", "charge_energy_added",
       %{
         state_topic_key: :charge_energy_added,
         name: "Energy Added",
         device_class: "energy",
         state_class: "total_increasing",
         unit_of_measurement: "kWh",
         suggested_display_precision: 1,
         icon: "mdi:battery-charging"
       }},
      {"sensor", "charge_limit_soc",
       %{
         state_topic_key: :charge_limit_soc,
         name: "Charge Limit",
         state_class: "measurement",
         unit_of_measurement: "%",
         suggested_display_precision: 0,
         icon: "mdi:battery-charging-90"
       }},
      {"sensor", "charger_actual_current",
       %{
         state_topic_key: :charger_actual_current,
         name: "Charger Current",
         device_class: "current",
         state_class: "measurement",
         unit_of_measurement: "A",
         suggested_display_precision: 0
       }},
      {"sensor", "charge_current_request",
       %{
         state_topic_key: :charge_current_request,
         name: "Charge Current Request",
         device_class: "current",
         state_class: "measurement",
         unit_of_measurement: "A",
         suggested_display_precision: 0
       }},
      {"sensor", "charge_current_request_max",
       %{
         state_topic_key: :charge_current_request_max,
         name: "Charge Current Request (Max)",
         device_class: "current",
         state_class: "measurement",
         unit_of_measurement: "A",
         suggested_display_precision: 0
       }},
      {"sensor", "charger_phases",
       %{
         state_topic_key: :charger_phases,
         name: "Charger Phases",
         state_class: "measurement",
         unit_of_measurement: "phases",
         suggested_display_precision: 0,
         icon: "mdi:sine-wave"
       }},
      {"sensor", "charger_power",
       %{
         state_topic_key: :charger_power,
         name: "Charger Power",
         device_class: "power",
         state_class: "measurement",
         unit_of_measurement: "kW",
         suggested_display_precision: 0
       }},
      {"sensor", "charger_voltage",
       %{
         state_topic_key: :charger_voltage,
         name: "Charger Voltage",
         device_class: "voltage",
         state_class: "measurement",
         unit_of_measurement: "V",
         suggested_display_precision: 0
       }},
      {"sensor", "scheduled_charging_start_time",
       %{
         state_topic_key: :scheduled_charging_start_time,
         name: "Charging Start Time",
         device_class: "timestamp"
       }},
      {"sensor", "time_to_full_charge",
       %{
         state_topic_key: :time_to_full_charge,
         name: "Charging Time Remaining",
         device_class: "duration",
         state_class: "measurement",
         unit_of_measurement: "h",
         icon: "mdi:timer"
       }},
      {"sensor", "download_perc",
       %{
         state_topic_key: :download_perc,
         name: "Software Update Download",
         entity_category: "diagnostic",
         enabled_by_default: false,
         state_class: "measurement",
         unit_of_measurement: "%",
         suggested_display_precision: 0,
         icon: "mdi:download"
       }},
      {"sensor", "install_perc",
       %{
         state_topic_key: :install_perc,
         name: "Software Update Installation",
         entity_category: "diagnostic",
         enabled_by_default: false,
         state_class: "measurement",
         unit_of_measurement: "%",
         suggested_display_precision: 0,
         icon: "mdi:update"
       }},

      # --- Software update ---
      {"update", "update",
       %{
         state_topic_key: :software_update,
         name: "Update",
         device_class: "firmware",
         entity_category: "diagnostic"
       }},
      {"sensor", "sun_roof_state",
       %{
         state_topic_key: :sun_roof_state,
         name: "Sunroof State",
         icon: "mdi:car-convertible",
         value_template: humanize_value_template(:snake_case)
       }},
      {"sensor", "sun_roof_percent_open",
       %{
         state_topic_key: :sun_roof_percent_open,
         name: "Sunroof Open",
         state_class: "measurement",
         unit_of_measurement: "%",
         suggested_display_precision: 0,
         icon: "mdi:car-convertible"
       }},

      # TPMS pressure (bar)
      {"sensor", "tpms_pressure_fl",
       %{
         state_topic_key: :tpms_pressure_fl,
         name: "Tire Pressure (Front Left)",
         device_class: "pressure",
         state_class: "measurement",
         unit_of_measurement: "bar",
         suggested_display_precision: 1,
         icon: "mdi:gauge"
       }},
      {"sensor", "tpms_pressure_fr",
       %{
         state_topic_key: :tpms_pressure_fr,
         name: "Tire Pressure (Front Right)",
         device_class: "pressure",
         state_class: "measurement",
         unit_of_measurement: "bar",
         suggested_display_precision: 1,
         icon: "mdi:gauge"
       }},
      {"sensor", "tpms_pressure_rl",
       %{
         state_topic_key: :tpms_pressure_rl,
         name: "Tire Pressure (Rear Left)",
         device_class: "pressure",
         state_class: "measurement",
         unit_of_measurement: "bar",
         suggested_display_precision: 1,
         icon: "mdi:gauge"
       }},
      {"sensor", "tpms_pressure_rr",
       %{
         state_topic_key: :tpms_pressure_rr,
         name: "Tire Pressure (Rear Right)",
         device_class: "pressure",
         state_class: "measurement",
         unit_of_measurement: "bar",
         suggested_display_precision: 1,
         icon: "mdi:gauge"
       }},

      # --- Active route sensors (derived from the JSON active_route topic) ---
      {"sensor", "active_route_destination",
       %{
         state_topic_key: :active_route,
         name: "Active Route Destination",
         icon: "mdi:map-marker",
         value_template: active_route_value_template("destination"),
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_energy_at_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active Route Energy At Arrival",
         device_class: "battery",
         unit_of_measurement: "%",
         icon: "mdi:battery-80",
         value_template: active_route_value_template("energy_at_arrival"),
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_distance_to_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active Route Distance To Arrival",
         device_class: "distance",
         unit_of_measurement: "mi",
         icon: "mdi:map-marker-distance",
         value_template: active_route_value_template("miles_to_arrival"),
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_minutes_to_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active Route Minutes To Arrival",
         device_class: "duration",
         unit_of_measurement: "min",
         icon: "mdi:clock-outline",
         value_template: active_route_value_template("minutes_to_arrival"),
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_traffic_minutes_delay",
       %{
         state_topic_key: :active_route,
         name: "Active Route Traffic Minutes Delay",
         device_class: "duration",
         unit_of_measurement: "min",
         icon: "mdi:clock-alert-outline",
         value_template: active_route_value_template("traffic_minutes_delay"),
         availability_topic_key: :active_route
       }},

      # --- Device trackers (JSON attributes) ---
      {"device_tracker", "location",
       %{json_attributes_topic_key: :location, name: nil, icon: "mdi:crosshairs-gps"}},
      {"device_tracker", "active_route_location",
       %{
         json_attributes_topic_key: :active_route,
         name: "Active Route Location",
         icon: "mdi:crosshairs-gps",
         json_attributes_template: active_route_location_template(),
         availability_topic_key: :active_route
       }},

      # --- Binary sensors (generic true/false on/off) ---
      {"binary_sensor", "healthy",
       %{
         state_topic_key: :healthy,
         name: "Health",
         device_class: "problem",
         entity_category: "diagnostic",
         payload_on: "false",
         payload_off: "true",
         icon: "mdi:heart-pulse"
       }},
      {"binary_sensor", "sun_roof_installed",
       Map.merge(true_false, %{
         state_topic_key: :sun_roof_installed,
         name: "Sunroof Installed",
         entity_category: "diagnostic",
         enabled_by_default: false,
         icon: "mdi:car-convertible"
       })},
      {"binary_sensor", "service_mode",
       Map.merge(true_false, %{
         state_topic_key: :service_mode,
         name: "Service Mode",
         device_class: "running",
         icon: "mdi:wrench"
       })},
      {"binary_sensor", "tpms_soft_warning_fl",
       Map.merge(true_false, %{
         state_topic_key: :tpms_soft_warning_fl,
         name: "Tire Soft (Front Left)",
         device_class: "problem",
         entity_category: "diagnostic",
         icon: "mdi:car-tire-alert"
       })},
      {"binary_sensor", "tpms_soft_warning_fr",
       Map.merge(true_false, %{
         state_topic_key: :tpms_soft_warning_fr,
         name: "Tire Soft (Front Right)",
         device_class: "problem",
         entity_category: "diagnostic",
         icon: "mdi:car-tire-alert"
       })},
      {"binary_sensor", "tpms_soft_warning_rl",
       Map.merge(true_false, %{
         state_topic_key: :tpms_soft_warning_rl,
         name: "Tire Soft (Rear Left)",
         device_class: "problem",
         entity_category: "diagnostic",
         icon: "mdi:car-tire-alert"
       })},
      {"binary_sensor", "tpms_soft_warning_rr",
       Map.merge(true_false, %{
         state_topic_key: :tpms_soft_warning_rr,
         name: "Tire Soft (Rear Right)",
         device_class: "problem",
         entity_category: "diagnostic",
         icon: "mdi:car-tire-alert"
       })},
      {"binary_sensor", "sentry_mode",
       Map.merge(true_false, %{
         state_topic_key: :sentry_mode,
         name: "Sentry Mode",
         device_class: "running",
         icon: "mdi:cctv"
       })},
      {"binary_sensor", "windows_open",
       Map.merge(true_false, %{
         state_topic_key: :windows_open,
         name: "Windows",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "driver_front_window_open",
       Map.merge(true_false, %{
         state_topic_key: :driver_front_window_open,
         name: "Window (Driver Front)",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "driver_rear_window_open",
       Map.merge(true_false, %{
         state_topic_key: :driver_rear_window_open,
         name: "Window (Driver Rear)",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "passenger_front_window_open",
       Map.merge(true_false, %{
         state_topic_key: :passenger_front_window_open,
         name: "Window (Passenger Front)",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "passenger_rear_window_open",
       Map.merge(true_false, %{
         state_topic_key: :passenger_rear_window_open,
         name: "Window (Passenger Rear)",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "doors_open",
       Map.merge(true_false, %{
         state_topic_key: :doors_open,
         name: "Doors",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "driver_front_door_open",
       Map.merge(true_false, %{
         state_topic_key: :driver_front_door_open,
         name: "Door (Driver Front)",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "driver_rear_door_open",
       Map.merge(true_false, %{
         state_topic_key: :driver_rear_door_open,
         name: "Door (Driver Rear)",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "passenger_front_door_open",
       Map.merge(true_false, %{
         state_topic_key: :passenger_front_door_open,
         name: "Door (Passenger Front)",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "passenger_rear_door_open",
       Map.merge(true_false, %{
         state_topic_key: :passenger_rear_door_open,
         name: "Door (Passenger Rear)",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "trunk_open",
       Map.merge(true_false, %{
         state_topic_key: :trunk_open,
         name: "Trunk",
         device_class: "door",
         icon: "mdi:car"
       })},
      {"binary_sensor", "frunk_open",
       Map.merge(true_false, %{
         state_topic_key: :frunk_open,
         name: "Frunk",
         device_class: "door",
         icon: "mdi:car"
       })},
      {"binary_sensor", "is_user_present",
       Map.merge(true_false, %{
         state_topic_key: :is_user_present,
         name: "User",
         device_class: "presence",
         icon: "mdi:human-greeting"
       })},
      {"binary_sensor", "is_climate_on",
       Map.merge(true_false, %{
         state_topic_key: :is_climate_on,
         name: "Climate",
         device_class: "running",
         icon: "mdi:air-conditioner"
       })},
      {"binary_sensor", "is_preconditioning",
       Map.merge(true_false, %{
         state_topic_key: :is_preconditioning,
         name: "Preconditioning",
         device_class: "running",
         icon: "mdi:air-conditioner"
       })},
      {"binary_sensor", "plugged_in",
       Map.merge(true_false, %{
         state_topic_key: :plugged_in,
         name: "Plug",
         device_class: "plug",
         icon: "mdi:ev-station"
       })},
      {"binary_sensor", "charge_port_door_open",
       Map.merge(true_false, %{
         state_topic_key: :charge_port_door_open,
         name: "Charge Port",
         device_class: "opening",
         icon: "mdi:ev-plug-tesla"
       })},

      # Lock - inverted (locked when "false")
      {"binary_sensor", "locked",
       %{
         state_topic_key: :locked,
         name: "Lock",
         device_class: "lock",
         payload_on: "false",
         payload_off: "true"
       }}
    ]
  end
end
