---
title: HomeAssistant Integration
sidebar_label: HomeAssistant
---

Whilst HomeAssistant provides an official component for Tesla vehicles, the component has not been updated recently, and does not have the sophistication of TeslaMate's polling mechanism, resulting in the component's default values keeping the vehicle awake and draining the battery.

The ultimate goal of this guide is to consume as much of the TeslaMate polling data as possible to replace the majority of the official Tesla component's polling functionality.

If your intention is to only use read-only sensor values, those provided by TeslaMate via MQTT are sufficient, and you do not need to utilise the official Tesla component. If however you would like to be able to write values to the Tesla API (Lock/Unlock Doors or automate Climate), there is a solution which involves configuring an extremely high polling interval for the Tesla component and using automation to populate the values from the TeslaMate MQTT parameters.

**Screenshots**

import useBaseUrl from '@docusaurus/useBaseUrl';

<img alt="HASS Screenshot" src={useBaseUrl('img/hass-dashboard.png')} />

**Current Status**

- Sensors: All sensors exposed by the Tesla component are available
- Locks: Not implemented
- Climate: Not implemented

## Configuration

### automation.yaml

The following provides an automation to update the location of the `device_tracker.tesla_location` tracker when new lat/lon values are published to MQTT. You can use this to:

- Plot the location of your Tesla on a map (see the _ui-lovelace.yaml_ file for an example of this)
- Calculate the proximity of your Tesla to another location such as home (see _configuration.yaml_, below)

```yml title="automation.yaml"
- alias: Update Tesla location as MQTT location updates
  initial_state: on
  trigger:
    - platform: mqtt
      topic: teslamate/cars/1/latitude
    - platform: mqtt
      topic: teslamate/cars/1/longitude
  action:
    - service: device_tracker.see
      data_template:
        dev_id: tesla_location
        gps:
          [
            "{{ states.sensor.tesla_latitude.state }}",
            "{{ states.sensor.tesla_longitude.state }}",
          ]
```

### configuration.yaml

Proximity sensors allow us to calculate the proximity of the Tesla `device_tracker` to defined zones. This can be useful for:

- Automatic Garage Door opening when you arrive home
- Notifications when the vehicle is arriving

```yml title="configuration.yaml"
automation: !include automation.yaml

proximity:
  home_tesla:
    zone: home
    devices:
      - device_tracker.tesla_location
    tolerance: 10
    unit_of_measurement: km

tesla:
  username: !secret tesla_username
  password: !secret tesla_password
  scan_interval: 3600

sensor: !include sensor.yaml
```

### known_devices.yaml (define a tracker for Tesla)

This is required for the automation above (in the _automation.yaml_ section). It defines the device_tracker object that we use to represent the location of your Tesla vehicle.

```yml title="known_devices.yaml"
tesla_location:
  hide_if_away: false
  icon: mdi:car
  mac:
  name: Tesla
  picture:
  track: true
```

### sensor.yaml (sensor: section of configuration.yaml)

```yml title="sensor.yaml"
- platform: mqtt
  name: tesla_battery_level
  state_topic: "teslamate/cars/1/battery_level"
  unit_of_measurement: "%"
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_energy_added
  state_topic: "teslamate/cars/1/charge_energy_added"
  unit_of_measurement: "kWh"
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_limit
  state_topic: "teslamate/cars/1/charge_limit_soc"
  unit_of_measurement: "%"
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_port_door_open
  state_topic: "teslamate/cars/1/charge_port_door_open"
  icon: mdi:car-door

- platform: mqtt
  name: tesla_charger_actual_current
  state_topic: "teslamate/cars/1/charger_actual_current"
  unit_of_measurement: "A"
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charger_phases
  state_topic: "teslamate/cars/1/charger_phases"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_charger_power
  state_topic: "teslamate/cars/1/charger_power"
  unit_of_measurement: "kW"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_charger_voltage
  state_topic: "teslamate/cars/1/charger_voltage"
  unit_of_measurement: "V"
  icon: mdi:gauge

- platform: mqtt
  name: tesla_display_name
  state_topic: "teslamate/cars/1/display_name"
  icon: mdi:car

- platform: mqtt
  name: tesla_estimated_range
  state_topic: "teslamate/cars/1/est_battery_range_km"
  unit_of_measurement: "km"
  icon: mdi:map-marker-path

- platform: mqtt
  name: tesla_healthy
  state_topic: "teslamate/cars/1/healthy"
  icon: mdi:car-connected

- platform: mqtt
  name: tesla_ideal_range
  state_topic: "teslamate/cars/1/ideal_battery_range_km"
  unit_of_measurement: "km"
  icon: mdi:map-marker-path

- platform: mqtt
  name: tesla_inside_temp
  state_topic: "teslamate/cars/1/inside_temp"
  unit_of_measurement: °C
  icon: mdi:thermometer-lines

- platform: mqtt
  name: tesla_latitude
  state_topic: "teslamate/cars/1/latitude"
  icon: mdi:crosshairs-gps

- platform: mqtt
  name: tesla_locked
  state_topic: "teslamate/cars/1/locked"
  icon: mdi:lock

- platform: mqtt
  name: tesla_longitude
  state_topic: "teslamate/cars/1/longitude"
  icon: mdi:crosshairs-gps

- platform: mqtt
  name: tesla_odometer
  state_topic: "teslamate/cars/1/odometer"
  unit_of_measurement: km
  icon: mdi:gauge

- platform: mqtt
  name: tesla_outside_temp
  state_topic: "teslamate/cars/1/outside_temp"
  unit_of_measurement: °C
  icon: mdi:thermometer-lines

- platform: template
  sensors:
    tesla_park_brake:
      friendly_name: Park Brake
      value_template: >-
        {% if is_state('sensor.tesla_shift_state', 'P') %}
          true
        {% else %}
          false
        {% endif %}

- platform: mqtt
  name: tesla_plugged_in
  state_topic: "teslamate/cars/1/plugged_in"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_rated_range
  state_topic: "teslamate/cars/1/rated_battery_range_km"
  unit_of_measurement: "km"
  icon: mdi:map-marker-path

- platform: mqtt
  name: tesla_scheduled_charging_start
  state_topic: "teslamate/cars/1/scheduled_charging_start_time"
  icon: mdi:clock-outline

- platform: mqtt
  name: tesla_sentry_mode
  state_topic: "teslamate/cars/1/sentry_mode"
  icon: mdi:cctv

- platform: mqtt
  name: tesla_shift_state
  state_topic: "teslamate/cars/1/shift_state"
  icon: mdi:car-shift-pattern

- platform: mqtt
  name: tesla_speed
  state_topic: "teslamate/cars/1/speed"
  icon: mdi:speedometer

- platform: mqtt
  name: tesla_state
  state_topic: "teslamate/cars/1/state"
  icon: mdi:car-connected

- platform: mqtt
  name: tesla_time_to_full_charge
  state_topic: "teslamate/cars/1/time_to_full_charge"
  icon: mdi:clock-outline

- platform: mqtt
  name: tesla_windows_open
  state_topic: "teslamate/cars/1/windows_open"
  icon: mdi:car-door

- platform: mqtt
  name: tesla_version
  state_topic: "teslamate/cars/1/version"
  icon: mdi:alphabetical

- platform: mqtt
  name: tesla_update_available
  state_topic: "teslamate/cars/1/update_available"
  icon: mdi:gift
```

### ui-lovelace.yaml

The below is the Lovelace UI configuration used to make the example screenshot above. You will obviously want to configure this to your liking, however the example contains all of the sensors and values presented via MQTT and could be used as the basis of UI configuration.

```yml title="ui-lovelace.yaml"
- path: car
  title: Car
  badges: []
  icon: "mdi:car-connected"
  cards:
    - type: vertical-stack
      cards:
        - type: glance
          entities:
            - entity: sensor.tesla_battery_level
              name: Battery Level
            - entity: sensor.tesla_state
              name: Car State
            - entity: sensor.tesla_plugged_in
              name: Plugged In
        - type: glance
          entities:
            - entity: sensor.tesla_park_brake
              name: Park Brake
            - entity: sensor.tesla_sentry_mode
              name: Sentry Mode
            - entity: sensor.tesla_speed
              name: Speed
        - type: glance
          entities:
            - entity: sensor.tesla_healthy
              name: Car Health
            - entity: sensor.tesla_windows_open
              name: Window Status
        - type: horizontal-stack
          cards:
            - type: "custom:button-card"
              entity: sensor.tesla_locked
              name: Charger Door
              show_state: true
              state:
                - value: locked
                  icon: "mdi:lock"
                  color: green
                  tap_action:
                    action: call-service
                    service: lock.unlock
                    service_data:
                      entity_id: lock.tesla_model_3_charger_door_lock
                - value: unlocked
                  icon: "mdi:lock-open"
                  color: red
                  tap_action:
                    action: call-service
                    service: lock.lock
                    service_data:
                      entity_id: lock.tesla_model_3_charger_door_lock
            - type: "custom:button-card"
              entity: lock.tesla_door_lock
              name: Car Door
              show_state: true
              state:
                - value: locked
                  icon: "mdi:lock"
                  color: green
                  tap_action:
                    action: call-service
                    service: lock.unlock
                    service_data:
                      entity_id: lock.tesla_model_3_door_lock
                - value: unlocked
                  icon: "mdi:lock-open"
                  color: red
                  tap_action:
                    action: call-service
                    service: lock.lock
                    service_data:
                      entity_id: lock.tesla_model_3_door_lock
    - type: vertical-stack
      cards:
        - type: map
          entities:
            - device_tracker.tesla_location
        - type: thermostat
          entity: climate.tesla_model_3_hvac_climate_system
    - type: entities
      entities:
        - entity: sensor.tesla_charge_limit
          name: SOC Charge Limit
        - entity: sensor.tesla_charge_energy_added
          name: Last Charge Energy Added
        - entity: sensor.tesla_odometer
          name: Odometer
        - entity: sensor.tesla_estimated_range
          name: Estimated Range
        - entity: sensor.tesla_rated_range
          name: Rated Range
        - entity: sensor.tesla_inside_temp
          name: Tesla Temperature (inside)
        - entity: sensor.tesla_outside_temp
          name: Tesla Temperature (outside)
        - entity: proximity.home_tesla
          name: Distance to Home
```

## Useful Automations

The below automations leverage TeslaMate MQTT topics to provide some useful automations

### Garage Door Automation based on Tesla location

This automation triggers when the Tesla transitions from not_home to home. This means that the vehicle would have had to have been outside of the home zone previously, and returned home. You may want to add conditions here to improve accuracy, such as time of day.

```yml title="automation.yaml"
- alias: Open garage if car returns home
  initial_state: on
  trigger:
    - platform: state
      entity_id: device_tracker.tesla_location
      from: "not_home"
      to: "home"
  action:
    - service: switch.turn_on
      entity_id: switch.garage_door_switch
```

### Notification for Doors and Windows left open

The following set of automations and scripts will detect when a Tesla door, frunk, trunk or window is left open. The script will notify you after the defined time period (by default, 5 minutes). If you would like to customize how the notification is performed, you can edit the `notify_tesla_open` script which is called by all of the four notifications.

By default, the script will repeatedly notify every 5 minutes. Remove the recursive `script.turn_on` sequence in the `notify_tesla_open` script if you'd only like to be informed once.

We add the random 30 second interval after each notification to avoid clobbering the notification script when we have multiple things open at once. For example, opening the door will open the door and the window. If we don't delay the calls, we will only get a message about the window (as it is the last call to the script) and if we then close the window, we won't get notifications about other things left open. This results in more notifications but less chance on missing out on knowing something was left open.

#### automation.yaml

```yml title="automation.yaml"
- alias: Set timer if teslamate reports something is open to alert us
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

