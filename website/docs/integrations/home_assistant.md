---
title: Home Assistant Integration
sidebar_label: Home Assistant
---

## Introduction

TeslaMate publishes vehicle data over MQTT so Home Assistant can track the car and display its sensors. To control the car's locks or climate, configure a separate integration that provides those controls.

### Screenshots

import useBaseUrl from '@docusaurus/useBaseUrl';

<img alt="HASS Screenshot" src={useBaseUrl('img/hass-dashboard.png')} />

## MQTT Discovery (automatic configuration)

Connect Home Assistant's MQTT integration to the same broker as TeslaMate. Then enable [MQTT discovery](https://www.home-assistant.io/integrations/mqtt/#mqtt-discovery) in TeslaMate.

See the [environment variable reference](../configuration/environment_variables.md) for all MQTT settings.

| Variable                               | Description                                                                                    | Default         |
| -------------------------------------- | ---------------------------------------------------------------------------------------------- | --------------- |
| `MQTT_HOME_ASSISTANT_DISCOVERY`        | Set to `true` to enable discovery.                                                             | `false`         |
| `MQTT_HOME_ASSISTANT_DISCOVERY_URL`    | TeslaMate URL surfaced in the discovered device panel (e.g. `https://teslamate.example.com/`). | _none_          |
| `MQTT_HOME_ASSISTANT_DISCOVERY_PREFIX` | Discovery topic prefix. Must match Home Assistant's `discovery_prefix` setting.                | `homeassistant` |

When enabled, TeslaMate publishes one retained device discovery payload per
vehicle to `<discovery_prefix>/device/<node>/config` on the first vehicle
summary. The payload contains all of the vehicle's entities, and `<node>` is
`teslamate_<car_id>`. If
`MQTT_NAMESPACE` is set, it is inserted after `teslamate_` (e.g.
`teslamate_<namespace>_<car_id>`), so multiple TeslaMate instances sharing a
broker do not collide on the same discovery topics. TeslaMate groups the entities
under the `teslamate_car_<car_id>` device identifier (also namespace-scoped)
and includes the VIN as the device's serial number.

TeslaMate publishes the vehicle name, each component's name and a stable
`unique_id`. Home Assistant uses its configured naming format to generate an
entity ID when it first discovers the entity. The vehicle tracker takes the
device name, while sensors have their own names such as **Range (Estimated)**.
Renaming the device keeps its current IDs until you choose
**Recreate entity IDs** from the device's menu. With the default format and no
assigned area, renaming the car to `Pearl` and recreating its IDs can produce
`device_tracker.pearl` and `sensor.pearl_state`. See
[Home Assistant's entity naming guide](https://www.home-assistant.io/docs/configuration/customizing-entities/#changing-the-attributes-of-an-entity).

On the first vehicle summary after each startup, TeslaMate clears every retained
topic from its former per-entity discovery format, waits for Home Assistant to
process the removals, and then publishes one complete device discovery payload.
For installations already using device discovery, repeating this sequence is
state-idempotent but not silent. MQTT forwards each zero-byte retained publish
to Home Assistant even when the legacy retained topic is already absent, so
Home Assistant logs one harmless "conflicting MQTT discovery message" warning
for each of the 62 legacy topics per vehicle after every TeslaMate restart.
These warnings do not change or remove any existing entity, and the retained
device payload is unchanged.

This cleanup does not use Home Assistant's discovery migration protocol. As a
result, entity registry settings and customizations from the former per-entity
format are not preserved when upgrading directly from TeslaMate 4.1.x.

:::note[Migrating from manual MQTT YAML]

Remove the TeslaMate entity definitions from your MQTT YAML first. If you used
`mqtt_sensors.yaml` only for TeslaMate, remove its include from
`configuration.yaml`. Reload the manual MQTT configuration or restart Home
Assistant before enabling discovery to avoid duplicate unique IDs.

If you used the documented `unique_id` values, left `MQTT_NAMESPACE` unset and
the entity uses the same platform (for example, `sensor`), Home Assistant may
reuse its registry entry and keep its entity ID. A namespace, a custom
`unique_id` or a change of platform can create a new entity. After discovery,
check the entity IDs referenced by your dashboards, automations and scripts.

:::

On startup, discovery configs are also cleared for cars that are no longer
tracked, e.g. because they were removed from the Tesla account or because
logging was disabled, so their entities are removed from Home Assistant.

While discovery is disabled, TeslaMate publishes a zero-byte retained payload
to the device discovery topic and to each of the 62 legacy topics of every
vehicle on each startup, so the entities of a previously enabled discovery are
removed from Home Assistant. Nothing is left on the broker, but clients
subscribed to `<discovery_prefix>/#` see these empty messages after every
TeslaMate restart, even if discovery was never enabled.

The cleanup runs on every startup because TeslaMate cannot know whether
discovery configs exist: MQTT offers no reliable way to learn that all
retained messages have been received, and storing what was published would be
a second state that can drift from the broker, e.g. after restoring a database
backup. Repeating the cleanup is harmless, and a cleanup that failed, e.g.
because the broker was unreachable, is simply retried on the next start.

For a custom MQTT setup, see the [list of TeslaMate topics and example payloads](mqtt.md#mqtt-topics).

:::note

Configs are only cleared at startup. A car removed while TeslaMate is running
keeps its entities until the next restart, and changing
`MQTT_HOME_ASSISTANT_DISCOVERY_PREFIX` does not clean up topics published under
the previous prefix.

:::

## Example configuration

The dashboard and automations below assume a freshly discovered device named
`Tesla #1`, Home Assistant's default entity ID format and no assigned area.
For that device, the tracker is `device_tracker.tesla_1` and the estimated
range is `sensor.tesla_1_range_estimated`. Find your own IDs under
**Settings > Devices & services > Entities** and filter by your vehicle.

### ui-lovelace.yaml

Replace the example lock and climate entities with the controls from your
own integration, or omit those cards. Some TeslaMate diagnostic entities are
disabled by default. You can enable the ones you want on the vehicle's device page.
To add distance from home, use the vehicle tracker with Home Assistant's
[Proximity integration](https://www.home-assistant.io/integrations/proximity/).

```yml title="ui-lovelace.yaml"
views:
  - path: car
    title: Car
    badges: []
    icon: mdi:car-connected
    cards:
      - type: vertical-stack
        cards:
          - type: glance
            entities:
              - entity: sensor.tesla_1_battery
                name: Battery Level
              - entity: sensor.tesla_1_state
                name: Car State
              - entity: binary_sensor.tesla_1_plug
                name: Plugged In
          - type: glance
            entities:
              - entity: binary_sensor.tesla_1_parking_brake
                name: Park Brake
              - entity: binary_sensor.tesla_1_sentry_mode
                name: Sentry Mode
              - entity: sensor.tesla_1_speed
                name: Speed
          - type: glance
            entities:
              - entity: binary_sensor.tesla_1_health
                name: Car Health
              - entity: binary_sensor.tesla_1_windows
                name: Window Status
          - type: horizontal-stack
            cards:
              - type: button
                entity: lock.tesla_model_3_charger_door_lock
                name: Charger Door
                show_state: true
              - type: button
                entity: lock.tesla_model_3_door_lock
                name: Car Door
                show_state: true
      - type: vertical-stack
        cards:
          - type: map
            dark_mode: true
            default_zoom: 12
            entities:
              - device_tracker.tesla_1
          - type: thermostat
            entity: climate.tesla_model_3_hvac_climate_system
      - type: entities
        entities:
          - entity: sensor.tesla_1_display_name
            name: Name
          - entity: sensor.tesla_1_state
            name: Status
          - entity: sensor.tesla_1_last_seen
            name: Last Status Change
          - entity: binary_sensor.tesla_1_health
            name: Logger Healthy
          - entity: sensor.tesla_1_version
            name: Software Version
          - entity: update.tesla_1_update
            name: Available Update Status
          - entity: sensor.tesla_1_update_version
            name: Available Update Version
          - entity: sensor.tesla_1_model
            name: Tesla Model
          - entity: sensor.tesla_1_trim_badging
            name: Trim Badge
          - entity: sensor.tesla_1_exterior_color
            name: Exterior Color
          - entity: sensor.tesla_1_wheel_type
            name: Wheel Type
          - entity: sensor.tesla_1_spoiler_type
            name: Spoiler Type
          - entity: sensor.tesla_1_geofence
            name: Geo-fence Name
          - entity: sensor.tesla_1_shift_state
            name: Shifter State
          - entity: sensor.tesla_1_speed
            name: Speed
          - entity: sensor.tesla_1_heading
            name: Heading
          - entity: sensor.tesla_1_elevation
            name: Elevation
          - entity: binary_sensor.tesla_1_lock
            name: Locked
          - entity: binary_sensor.tesla_1_sentry_mode
            name: Sentry Mode Enabled
          - entity: binary_sensor.tesla_1_windows
            name: Windows Open
          - entity: binary_sensor.tesla_1_doors
            name: Doors Open
          - entity: binary_sensor.tesla_1_trunk
            name: Trunk Open
          - entity: binary_sensor.tesla_1_frunk
            name: Frunk Open
          - entity: binary_sensor.tesla_1_user
            name: User Present
          - entity: binary_sensor.tesla_1_climate
            name: Climate On
          - entity: sensor.tesla_1_temperature_inside
            name: Inside Temperature
          - entity: sensor.tesla_1_temperature_outside
            name: Outside Temperature
          - entity: binary_sensor.tesla_1_preconditioning
            name: Preconditioning
          - entity: sensor.tesla_1_odometer
            name: Odometer
          - entity: sensor.tesla_1_range_estimated
            name: Estimated Battery Range
          - entity: sensor.tesla_1_range_rated
            name: Rated Battery Range
          - entity: sensor.tesla_1_range_ideal
            name: Ideal Battery Range
          - entity: sensor.tesla_1_battery
            name: Battery Level
          - entity: sensor.tesla_1_usable_battery
            name: Usable Battery Level
          - entity: binary_sensor.tesla_1_plug
            name: Plugged In
          - entity: sensor.tesla_1_energy_added
            name: Charge Energy Added
          - entity: sensor.tesla_1_charge_limit
            name: Charge Limit
          - entity: binary_sensor.tesla_1_charge_port
            name: Charge Port Door Open
          - entity: sensor.tesla_1_charger_current
            name: Charger Current
          - entity: sensor.tesla_1_charger_phases
            name: Charger Phases
          - entity: sensor.tesla_1_charger_power
            name: Charger Power
          - entity: sensor.tesla_1_charger_voltage
            name: Charger Voltage
          - entity: sensor.tesla_1_charging_start_time
            name: Scheduled Charging Start Time
          - entity: sensor.tesla_1_charging_time_remaining
            name: Time To Full Charge
          - entity: sensor.tesla_1_tire_pressure_front_left
            name: Front Left Tire Pressure (bar)
          - entity: sensor.tesla_1_tire_pressure_front_right
            name: Front Right Tire Pressure (bar)
          - entity: sensor.tesla_1_tire_pressure_rear_left
            name: Rear Left Tire Pressure (bar)
          - entity: sensor.tesla_1_tire_pressure_rear_right
            name: Rear Right Tire Pressure (bar)
          - entity: sensor.tesla_1_active_route_destination
            name: Active Route Destination
          - entity: sensor.tesla_1_active_route_energy_at_arrival
            name: Active Route Energy at Arrival
          - entity: sensor.tesla_1_active_route_distance_to_arrival
            name: Active Route Distance to Arrival
          - entity: sensor.tesla_1_active_route_minutes_to_arrival
            name: Active Route Minutes to Arrival
          - entity: sensor.tesla_1_active_route_traffic_minutes_delay
            name: Active Route Traffic Minutes Delay
```

## Useful Automations

### Garage Door Automation based on Tesla location

This automation turns on a separately configured garage switch when the
tracker returns home. Replace `switch.garage_door_switch` with your switch.

```yml title="automation.yaml"
- alias: Open garage if car returns home
  initial_state: on
  trigger:
    - platform: state
      entity_id: device_tracker.tesla_1
      from: "not_home"
      to: "home"
  action:
    - service: switch.turn_on
      entity_id: switch.garage_door_switch
```

### Notification for Doors and Windows left open

These examples use the raw MQTT topics for TeslaMate car ID 1 with no namespace. Replace `notify.notify_group` with your own notification action.

The following set of automations and scripts will detect when a Tesla door, frunk, trunk or window is left open. The script will notify you after the defined time period (by default, 5 minutes). If you would like to customize how the notification is performed, you can edit the `notify_tesla_open` script which is called by all of the four notifications.

By default, the script will repeatedly notify every 5 minutes. Remove the recursive `script.turn_on` sequence in the `notify_tesla_open` script if you'd only like to be informed once.

We add the random 30 second interval after each notification to avoid clobbering the notification script when we have multiple things open at once.
For example, opening the door will open the door and the window. If we don't delay the calls, we will only get a message about the window (as it is the last call to the script) and if we then close the window, we won't get notifications about other things left open. This results in more notifications but less chance on missing out on knowing something was left open.

#### automation.yaml

```yml title="automation.yaml"
- alias: Set timer if TeslaMate reports something is open to alert us
  initial_state: on
  trigger:
    - platform: mqtt
      topic: teslamate/cars/1/windows_open
      payload: "true"
    - platform: mqtt
      topic: teslamate/cars/1/doors_open
      payload: "true"
    - platform: mqtt
      topic: teslamate/cars/1/trunk_open
      payload: "true"
    - platform: mqtt
      topic: teslamate/cars/1/frunk_open
      payload: "true"
  action:
    - service: script.turn_on
      data_template:
        entity_id: script.notify_tesla_{{trigger.topic.split('/')[3]}}

- alias: Cancel notification if said door/window is closed
  initial_state: on
  trigger:
    - platform: mqtt
      topic: teslamate/cars/1/windows_open
      payload: "false"
    - platform: mqtt
      topic: teslamate/cars/1/doors_open
      payload: "false"
    - platform: mqtt
      topic: teslamate/cars/1/trunk_open
      payload: "false"
    - platform: mqtt
      topic: teslamate/cars/1/frunk_open
      payload: "false"
  action:
    - service: script.turn_off
      data_template:
        entity_id: script.notify_tesla_{{trigger.topic.split('/')[3]}}
```

#### script.yaml

```yml title="script.yaml"
notify_tesla_open:
  alias: "Notify when something on the tesla is left open"
  sequence:
    - service: notify.notify_group
      data_template:
        title: "Tesla Notification"
        message: "You have left the {{ whatsopen }} open on the Tesla!"
    - service: script.turn_on
      data_template:
        entity_id: script.notify_tesla_{{ whatsopen }}_open

notify_tesla_doors_open:
  sequence:
    - delay:
        minutes: 5
    - delay:
        seconds: "{{ range(0, 30)|random|int }}"
    - service: script.turn_on
      entity_id: script.notify_tesla_open
      data:
        variables:
          whatsopen: "doors"

notify_tesla_frunk_open:
  sequence:
    - delay:
        minutes: 5
    - delay:
        seconds: "{{ range(0, 30)|random|int }}"
    - service: script.turn_on
      entity_id: script.notify_tesla_open
      data:
        variables:
          whatsopen: "frunk"

notify_tesla_trunk_open:
  sequence:
    - delay:
        minutes: 5
    - delay:
        seconds: "{{ range(0, 30)|random|int }}"
    - service: script.turn_on
      entity_id: script.notify_tesla_open
      data:
        variables:
          whatsopen: "trunk"

notify_tesla_windows_open:
  sequence:
    - delay:
        minutes: 5
    - delay:
        seconds: "{{ range(0, 30)|random|int }}"
    - service: script.turn_on
      entity_id: script.notify_tesla_open
      data:
        variables:
          whatsopen: "windows"
```

### Notification when the car is unplugged at night

Home Assistant reports the plug's state as `off` when the car is unplugged.
Replace the mobile app notification action with your own.

```yml title="automation.yaml"
- id: plugin-tesla-notify
  alias: Notify if Tesla is unplugged at night
  triggers:
    - trigger: time
      at: "19:30:00"
  conditions:
    - condition: state
      entity_id: binary_sensor.tesla_1_plug
      state: "off"
  actions:
    - action: notify.mobile_app_pixel_6_pro
      data:
        title: "🔌 Plug in your car 🚙"
        message: >-
          Battery: {{ states('sensor.tesla_1_battery') }}%.
          Estimated range: {{ states('sensor.tesla_1_range_estimated') }}
          {{ state_attr('sensor.tesla_1_range_estimated', 'unit_of_measurement') }}.
```
