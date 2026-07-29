defmodule TeslaMate.Mqtt.PubSub.HomeAssistant do
  @moduledoc """
  Publishes Home Assistant MQTT discovery configuration payloads, one per
  vehicle entity, so users can opt out of manually configuring the MQTT
  sensors in `configuration.yaml`.

  See: https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery
  """

  import Core.Dependency, only: [call: 3]

  alias TeslaMate.Vehicles.Vehicle.Summary
  alias TeslaMate.Log.Car

  @discovery_prefix "homeassistant"
  @node "teslamate"

  @type publish_opts :: [
          car_id: pos_integer(),
          namespace: String.t() | nil,
          base_url: String.t() | nil,
          discovery_prefix: String.t()
        ]

  @doc """
  Publishes discovery configuration payloads for every entity derived from
  the given vehicle summary.

  Each payload is published retained (QoS 1) to
  `<discovery_prefix>/<component>/<node>_<car_id>/<object_id>/config` where
  `node` is `#{@node}`. Returns `:ok` on success.
  """
  @spec publish(term(), publish_opts(), term()) :: :ok | {:error, term()}
  def publish(%Summary{} = summary, opts, publisher) do
    car_id = Keyword.fetch!(opts, :car_id)
    namespace = Keyword.get(opts, :namespace)
    base_url = Keyword.get(opts, :base_url)
    prefix = Keyword.get(opts, :discovery_prefix, @discovery_prefix)
    node = "#{@node}_#{car_id}"

    device = device(summary, car_id, base_url)

    Enum.reduce_while(entities(), :ok, fn {component, object_id, config}, _acc ->
      topic = discovery_topic(prefix, component, node, object_id)

      payload =
        config
        |> resolve_topics(car_id, namespace)
        |> Map.put(:unique_id, "teslamate_#{car_id}_#{object_id}")
        |> Map.put(:object_id, object_id)
        |> Map.put(:device, device)
        |> Jason.encode!()

      case call(publisher, :publish, [topic, payload, [retain: true, qos: 1]]) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Publishes an empty retained payload to clear a discovery topic, so entities
  are removed from Home Assistant when discovery is disabled or a vehicle is
  removed.
  """
  @spec clear(pos_integer(), publish_opts(), term()) :: :ok | {:error, term()}
  def clear(car_id, opts, publisher) do
    prefix = Keyword.get(opts, :discovery_prefix, @discovery_prefix)
    node = "#{@node}_#{car_id}"

    Enum.reduce_while(entities(), :ok, fn {component, object_id, _config}, _acc ->
      topic = discovery_topic(prefix, component, node, object_id)

      case call(publisher, :publish, [topic, "", [retain: true, qos: 1]]) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp discovery_topic(prefix, component, node, object_id) do
    Enum.join([prefix, component, node, object_id, "config"], "/")
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
          value_template: "{{ 'offline' if value_json.error else 'online' }}"
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

  defp device(%Summary{} = summary, car_id, base_url) do
    name = summary.display_name || car_name(summary) || "Tesla ##{car_id}"
    model = summary.model || "Tesla"

    %{identifiers: ["teslamate_car_#{car_id}"], manufacturer: "Tesla", name: name, model: model}
    |> maybe_put(:configuration_url, base_url)
  end

  defp car_name(%Summary{car: %Car{name: name}}) when is_binary(name) and name != "", do: name
  defp car_name(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp entities do
    true_false = %{payload_on: "true", payload_off: "false"}

    [
      # --- Generic sensors (string/raw values) ---
      {"sensor", "display_name",
       %{state_topic_key: :display_name, name: "Display Name", icon: "mdi:car"}},
      {"sensor", "state", %{state_topic_key: :state, name: "State", icon: "mdi:car-connected"}},
      {"sensor", "since",
       %{
         state_topic_key: :since,
         name: "Since",
         device_class: "timestamp",
         icon: "mdi:clock-outline"
       }},
      {"sensor", "version",
       %{state_topic_key: :version, name: "Version", icon: "mdi:alphabetical"}},
      {"sensor", "update_version",
       %{state_topic_key: :update_version, name: "Update Version", icon: "mdi:alphabetical"}},
      {"sensor", "model", %{state_topic_key: :model, name: "Model"}},
      {"sensor", "trim_badging",
       %{state_topic_key: :trim_badging, name: "Trim Badging", icon: "mdi:shield-star-outline"}},
      {"sensor", "exterior_color",
       %{state_topic_key: :exterior_color, name: "Exterior Color", icon: "mdi:palette"}},
      {"sensor", "wheel_type", %{state_topic_key: :wheel_type, name: "Wheel Type"}},
      {"sensor", "spoiler_type",
       %{state_topic_key: :spoiler_type, name: "Spoiler Type", icon: "mdi:car-sports"}},
      {"sensor", "geofence", %{state_topic_key: :geofence, name: "Geofence", icon: "mdi:earth"}},
      {"sensor", "shift_state",
       %{state_topic_key: :shift_state, name: "Shift State", icon: "mdi:car-shift-pattern"}},

      # Park brake - binary sensor derived from shift_state
      {"binary_sensor", "park_brake",
       %{
         state_topic_key: :shift_state,
         name: "Parking Brake",
         value_template: "{% if value == 'P' %}ON{% else %}OFF{% endif %}",
         icon: "mdi:car-brake-parking"
       }},

      # --- Numeric sensors ---
      {"sensor", "power",
       %{
         state_topic_key: :power,
         name: "Power",
         device_class: "power",
         unit_of_measurement: "kW",
         icon: "mdi:flash"
       }},
      {"sensor", "speed",
       %{
         state_topic_key: :speed,
         name: "Speed",
         device_class: "speed",
         unit_of_measurement: "km/h",
         icon: "mdi:speedometer"
       }},
      {"sensor", "heading",
       %{
         state_topic_key: :heading,
         name: "Heading",
         unit_of_measurement: "°",
         icon: "mdi:compass"
       }},
      {"sensor", "elevation",
       %{
         state_topic_key: :elevation,
         name: "Elevation",
         device_class: "distance",
         unit_of_measurement: "m",
         icon: "mdi:image-filter-hdr"
       }},
      {"sensor", "inside_temp",
       %{
         state_topic_key: :inside_temp,
         name: "Inside Temp",
         device_class: "temperature",
         unit_of_measurement: "°C",
         icon: "mdi:thermometer-lines"
       }},
      {"sensor", "outside_temp",
       %{
         state_topic_key: :outside_temp,
         name: "Outside Temp",
         device_class: "temperature",
         unit_of_measurement: "°C",
         icon: "mdi:thermometer-lines"
       }},
      {"sensor", "odometer",
       %{
         state_topic_key: :odometer,
         name: "Odometer",
         device_class: "distance",
         unit_of_measurement: "km",
         icon: "mdi:counter"
       }},
      {"sensor", "est_battery_range_km",
       %{
         state_topic_key: :est_battery_range_km,
         name: "Est Battery Range",
         device_class: "distance",
         unit_of_measurement: "km",
         icon: "mdi:gauge"
       }},
      {"sensor", "rated_battery_range_km",
       %{
         state_topic_key: :rated_battery_range_km,
         name: "Rated Battery Range",
         device_class: "distance",
         unit_of_measurement: "km",
         icon: "mdi:gauge"
       }},
      {"sensor", "ideal_battery_range_km",
       %{
         state_topic_key: :ideal_battery_range_km,
         name: "Ideal Battery Range",
         device_class: "distance",
         unit_of_measurement: "km",
         icon: "mdi:gauge"
       }},
      {"sensor", "battery_level",
       %{
         state_topic_key: :battery_level,
         name: "Battery Level",
         device_class: "battery",
         unit_of_measurement: "%",
         icon: "mdi:battery-80"
       }},
      {"sensor", "usable_battery_level",
       %{
         state_topic_key: :usable_battery_level,
         name: "Usable Battery Level",
         device_class: "battery",
         unit_of_measurement: "%",
         icon: "mdi:battery-80"
       }},
      {"sensor", "charge_energy_added",
       %{
         state_topic_key: :charge_energy_added,
         name: "Charge Energy Added",
         device_class: "energy",
         state_class: "total",
         unit_of_measurement: "kWh",
         icon: "mdi:battery-charging"
       }},
      {"sensor", "charge_limit_soc",
       %{
         state_topic_key: :charge_limit_soc,
         name: "Charge Limit Soc",
         device_class: "battery",
         unit_of_measurement: "%",
         icon: "mdi:battery-charging-100"
       }},
      {"sensor", "charger_actual_current",
       %{
         state_topic_key: :charger_actual_current,
         name: "Charger Actual Current",
         device_class: "current",
         unit_of_measurement: "A",
         icon: "mdi:lightning-bolt"
       }},
      {"sensor", "charger_phases",
       %{state_topic_key: :charger_phases, name: "Charger Phases", icon: "mdi:sine-wave"}},
      {"sensor", "charger_power",
       %{
         state_topic_key: :charger_power,
         name: "Charger Power",
         device_class: "power",
         unit_of_measurement: "kW",
         icon: "mdi:lightning-bolt"
       }},
      {"sensor", "charger_voltage",
       %{
         state_topic_key: :charger_voltage,
         name: "Charger Voltage",
         device_class: "voltage",
         unit_of_measurement: "V",
         icon: "mdi:lightning-bolt"
       }},
      {"sensor", "scheduled_charging_start_time",
       %{
         state_topic_key: :scheduled_charging_start_time,
         name: "Scheduled Charging Start Time",
         device_class: "timestamp",
         icon: "mdi:clock-outline"
       }},
      {"sensor", "time_to_full_charge",
       %{
         state_topic_key: :time_to_full_charge,
         name: "Time To Full Charge",
         device_class: "duration",
         unit_of_measurement: "h",
         icon: "mdi:clock-outline"
       }},

      # TPMS pressure (bar)
      {"sensor", "tpms_pressure_fl",
       %{
         state_topic_key: :tpms_pressure_fl,
         name: "TPMS Pressure Front Left",
         device_class: "pressure",
         unit_of_measurement: "bar",
         icon: "mdi:car-tire-alert"
       }},
      {"sensor", "tpms_pressure_fr",
       %{
         state_topic_key: :tpms_pressure_fr,
         name: "TPMS Pressure Front Right",
         device_class: "pressure",
         unit_of_measurement: "bar",
         icon: "mdi:car-tire-alert"
       }},
      {"sensor", "tpms_pressure_rl",
       %{
         state_topic_key: :tpms_pressure_rl,
         name: "TPMS Pressure Rear Left",
         device_class: "pressure",
         unit_of_measurement: "bar",
         icon: "mdi:car-tire-alert"
       }},
      {"sensor", "tpms_pressure_rr",
       %{
         state_topic_key: :tpms_pressure_rr,
         name: "TPMS Pressure Rear Right",
         device_class: "pressure",
         unit_of_measurement: "bar",
         icon: "mdi:car-tire-alert"
       }},

      # TPMS pressure (psi) - derived via value_template from the bar topic
      {"sensor", "tpms_pressure_fl_psi",
       %{
         state_topic_key: :tpms_pressure_fl,
         name: "TPMS Pressure Front Left (psi)",
         device_class: "pressure",
         unit_of_measurement: "psi",
         icon: "mdi:car-tire-alert",
         value_template: "{{ (value | float * 14.50377) | round(2) }}",
         suggested_display_precision: 2
       }},
      {"sensor", "tpms_pressure_fr_psi",
       %{
         state_topic_key: :tpms_pressure_fr,
         name: "TPMS Pressure Front Right (psi)",
         device_class: "pressure",
         unit_of_measurement: "psi",
         icon: "mdi:car-tire-alert",
         value_template: "{{ (value | float * 14.50377) | round(2) }}",
         suggested_display_precision: 2
       }},
      {"sensor", "tpms_pressure_rl_psi",
       %{
         state_topic_key: :tpms_pressure_rl,
         name: "TPMS Pressure Rear Left (psi)",
         device_class: "pressure",
         unit_of_measurement: "psi",
         icon: "mdi:car-tire-alert",
         value_template: "{{ (value | float * 14.50377) | round(2) }}",
         suggested_display_precision: 2
       }},
      {"sensor", "tpms_pressure_rr_psi",
       %{
         state_topic_key: :tpms_pressure_rr,
         name: "TPMS Pressure Rear Right (psi)",
         device_class: "pressure",
         unit_of_measurement: "psi",
         icon: "mdi:car-tire-alert",
         value_template: "{{ (value | float * 14.50377) | round(2) }}",
         suggested_display_precision: 2
       }},

      # --- Active route sensors (derived from the JSON active_route topic) ---
      {"sensor", "active_route_destination",
       %{
         state_topic_key: :active_route,
         name: "Active route destination",
         icon: "mdi:map-marker",
         value_template:
           "{% if not value_json.error and value_json.destination %}{{ value_json.destination }}{% endif %}",
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_energy_at_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active route energy at arrival",
         device_class: "battery",
         unit_of_measurement: "%",
         icon: "mdi:battery-80",
         value_template:
           "{% if not value_json.error and value_json.energy_at_arrival %}{{ value_json.energy_at_arrival }}{% endif %}",
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_distance_to_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active route distance to arrival",
         device_class: "distance",
         unit_of_measurement: "km",
         icon: "mdi:map-marker-distance",
         value_template:
           "{% if not value_json.error and value_json.miles_to_arrival %}{{ (value_json.miles_to_arrival | float * 1.60934) | round(2) }}{% endif %}",
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_minutes_to_arrival",
       %{
         state_topic_key: :active_route,
         name: "Active route minutes to arrival",
         device_class: "duration",
         unit_of_measurement: "min",
         icon: "mdi:clock-outline",
         value_template:
           "{% if not value_json.error and value_json.minutes_to_arrival %}{{ value_json.minutes_to_arrival }}{% endif %}",
         availability_topic_key: :active_route
       }},
      {"sensor", "active_route_traffic_minutes_delay",
       %{
         state_topic_key: :active_route,
         name: "Active route traffic minutes delay",
         device_class: "duration",
         unit_of_measurement: "min",
         icon: "mdi:clock-alert-outline",
         value_template:
           "{% if not value_json.error and value_json.traffic_minutes_delay %}{{ value_json.traffic_minutes_delay }}{% endif %}",
         availability_topic_key: :active_route
       }},

      # --- Device trackers (JSON attributes) ---
      {"device_tracker", "location",
       %{json_attributes_topic_key: :location, name: "Location", icon: "mdi:crosshairs-gps"}},
      {"device_tracker", "active_route_location",
       %{
         json_attributes_topic_key: :active_route,
         name: "Active route location",
         icon: "mdi:crosshairs-gps",
         json_attributes_template:
           "{% if not value_json.error and value_json.location %}{{ value_json.location | tojson }}{% else %}{}{% endif %}",
         availability_topic_key: :active_route
       }},

      # --- Binary sensors (generic true/false on/off) ---
      {"binary_sensor", "healthy",
       Map.merge(true_false, %{
         state_topic_key: :healthy,
         name: "Healthy",
         icon: "mdi:heart-pulse"
       })},
      {"binary_sensor", "update_available",
       Map.merge(true_false, %{
         state_topic_key: :update_available,
         name: "Update Available",
         icon: "mdi:alarm"
       })},
      {"binary_sensor", "sentry_mode",
       Map.merge(true_false, %{
         state_topic_key: :sentry_mode,
         name: "Sentry Mode",
         icon: "mdi:cctv"
       })},
      {"binary_sensor", "windows_open",
       Map.merge(true_false, %{
         state_topic_key: :windows_open,
         name: "Windows Open",
         device_class: "window",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "doors_open",
       Map.merge(true_false, %{
         state_topic_key: :doors_open,
         name: "Doors Open",
         device_class: "door",
         icon: "mdi:car-door"
       })},
      {"binary_sensor", "trunk_open",
       Map.merge(true_false, %{
         state_topic_key: :trunk_open,
         name: "Trunk Open",
         device_class: "opening",
         icon: "mdi:car-side"
       })},
      {"binary_sensor", "frunk_open",
       Map.merge(true_false, %{
         state_topic_key: :frunk_open,
         name: "Frunk Open",
         device_class: "opening",
         icon: "mdi:car-side"
       })},
      {"binary_sensor", "is_user_present",
       Map.merge(true_false, %{
         state_topic_key: :is_user_present,
         name: "Is User Present",
         device_class: "presence",
         icon: "mdi:human-greeting"
       })},
      {"binary_sensor", "is_climate_on",
       Map.merge(true_false, %{
         state_topic_key: :is_climate_on,
         name: "Is Climate On",
         icon: "mdi:fan"
       })},
      {"binary_sensor", "is_preconditioning",
       Map.merge(true_false, %{
         state_topic_key: :is_preconditioning,
         name: "Is Preconditioning",
         icon: "mdi:fan"
       })},
      {"binary_sensor", "plugged_in",
       Map.merge(true_false, %{
         state_topic_key: :plugged_in,
         name: "Plugged In",
         device_class: "plug",
         icon: "mdi:ev-station"
       })},
      {"binary_sensor", "charge_port_door_open",
       Map.merge(true_false, %{
         state_topic_key: :charge_port_door_open,
         name: "Charge Port Door OPEN",
         device_class: "opening",
         icon: "mdi:ev-plug-tesla"
       })},

      # Lock - inverted (locked when "false")
      {"binary_sensor", "locked",
       %{
         state_topic_key: :locked,
         name: "Locked",
         device_class: "lock",
         payload_on: "false",
         payload_off: "true"
       }}
    ]
  end
end
