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

mqtt: !include mqtt_sensors.yaml
sensor: !include sensor.yaml
binary_sensor: !include binary_sensor.yaml
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

### mqtt_sensors.yaml (mqtt: section of configuration.yaml)

Don't forget to replace `<teslamate url>` and `<your tesla model>` with correct corresponding values.

```yml title="mqtt_sensors.yaml"
- sensor:
    name: Display Name
    object_id: tesla_display_name # entity_id
    unique_id: teslamate_1_display_name # internal id, used for device grouping
    availability: &teslamate_availability
      - topic: teslamate/cars/1/healthy
        payload_available: 'true'
        payload_not_available: 'false'
    device: &teslamate_device_info
      identifiers: [teslamate_car_1]
      configuration_url: https://teslamate.zxxz.io/
      manufacturer: Tesla
      model: Model 3
      name: Tesla Model 3
    state_topic: "teslamate/cars/1/display_name"
    icon: mdi:car

- sensor:
    name: State
    object_id: tesla_state
    unique_id: teslamate_1_state
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/state"
    icon: mdi:car-connected

- sensor:
    name: Since
    object_id: tesla_since
    unique_id: teslamate_1_since
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/since"
    device_class: timestamp
    icon: mdi:clock-outline

- sensor:
    name: Version
    object_id: tesla_version
    unique_id: teslamate_1_version
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/version"
    icon: mdi:alphabetical

- sensor:
    name: Update Version
    object_id: tesla_update_version
    unique_id: teslamate_1_update_version
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/update_version"
    icon: mdi:alphabetical

- sensor:
    name: Model
    object_id: tesla_model
    unique_id: teslamate_1_model
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/model"

- sensor:
    name: Trim Badging
    object_id: tesla_trim_badging
    unique_id: teslamate_1_trim_badging
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/trim_badging"
    icon: mdi:shield-star-outline

- sensor:
    name: Exterior Color
    object_id: tesla_exterior_color
    unique_id: teslamate_1_exterior_color
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/exterior_color"
    icon: mdi:palette

- sensor:
    name: Wheel Type
    object_id: tesla_wheel_type
    unique_id: teslamate_1_wheel_type
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/wheel_type"

- sensor:
    name: Spoiler Type
    object_id: tesla_spoiler_type
    unique_id: teslamate_1_spoiler_type
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/spoiler_type"
    icon: mdi:car-sports

- sensor:
    name: Geofence
    object_id: tesla_geofence
    unique_id: teslamate_1_geofence
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/geofence"
    icon: mdi:earth

- sensor:
    name: Latitude
    object_id: tesla_latitude
    unique_id: teslamate_1_latitude
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/latitude"
    unit_of_measurement: °
    icon: mdi:crosshairs-gps

- sensor:
    name: Longitude
    object_id: tesla_longitude
    unique_id: teslamate_1_longitude
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/longitude"
    unit_of_measurement: °
    icon: mdi:crosshairs-gps

- sensor:
    name: Shift State
    object_id: tesla_shift_state
    unique_id: teslamate_1_shift_state
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/shift_state"
    icon: mdi:car-shift-pattern

- sensor:
    name: Power
    object_id: tesla_power
    unique_id: teslamate_1_power
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/power"
    device_class: power
    unit_of_measurement: kW
    icon: mdi:flash

- sensor:
    name: Speed
    object_id: tesla_speed
    unique_id: teslamate_1_speed
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/speed"
    unit_of_measurement: "km/h"
    icon: mdi:speedometer

- sensor:
    name: Heading
    object_id: tesla_heading
    unique_id: teslamate_1_heading
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/heading"
    unit_of_measurement: °
    icon: mdi:compass

- sensor:
    name: Elevation
    object_id: tesla_elevation
    unique_id: teslamate_1_elevation
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/elevation"
    unit_of_measurement: m
    icon: mdi:image-filter-hdr

- sensor:
    name: Inside Temp
    object_id: tesla_inside_temp
    unique_id: teslamate_1_inside_temp
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/inside_temp"
    device_class: temperature
    unit_of_measurement: °C
    icon: mdi:thermometer-lines

- sensor:
    name: Outside Temp
    object_id: tesla_outside_temp
    unique_id: teslamate_1_outside_temp
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/outside_temp"
    device_class: temperature
    unit_of_measurement: °C
    icon: mdi:thermometer-lines

- sensor:
    name: Odometer
    object_id: tesla_odometer
    unique_id: teslamate_1_odometer
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/odometer"
    unit_of_measurement: km
    icon: mdi:counter

- sensor:
    name: Est Battery Range
    object_id: tesla_est_battery_range_km
    unique_id: teslamate_1_est_battery_range_km
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/est_battery_range_km"
    unit_of_measurement: km
    icon: mdi:gauge

- sensor:
    name: Rated Battery Range
    object_id: tesla_rated_battery_range_km
    unique_id: teslamate_1_rated_battery_range_km
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/rated_battery_range_km"
    unit_of_measurement: km
    icon: mdi:gauge

- sensor:
    name: Ideal Battery Range
    object_id: tesla_ideal_battery_range_km
    unique_id: teslamate_1_ideal_battery_range_km
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/ideal_battery_range_km"
    unit_of_measurement: km
    icon: mdi:gauge

- sensor:
    name: Battery Level
    object_id: tesla_battery_level
    unique_id: teslamate_1_battery_level
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/battery_level"
    device_class: battery
    unit_of_measurement: "%"
    icon: mdi:battery-80
    
- sensor:
    name: Usable Battery Level
    object_id: tesla_usable_battery_level
    unique_id: teslamate_1_usable_battery_level
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/usable_battery_level"
    unit_of_measurement: "%"
    icon: mdi:battery-80

- sensor:
    name: Charge Energy Added
    object_id: tesla_charge_energy_added
    unique_id: teslamate_1_charge_energy_added
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charge_energy_added"
    device_class: energy
    unit_of_measurement: kWh
    icon: mdi:battery-charging

- sensor:
    name: Charge Limit Soc
    object_id: tesla_charge_limit_soc
    unique_id: teslamate_1_charge_limit_soc
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charge_limit_soc"
    unit_of_measurement: "%"
    icon: mdi:battery-charging-100

- sensor:
    name: Charger Actual Current
    object_id: tesla_charger_actual_current
    unique_id: teslamate_1_charger_actual_current
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charger_actual_current"
    device_class: current
    unit_of_measurement: A
    icon: mdi:lightning-bolt

- sensor:
    name: Charger Phases
    object_id: tesla_charger_phases
    unique_id: teslamate_1_charger_phases
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charger_phases"
    icon: mdi:sine-wave

- sensor:
    name: Charger Power
    object_id: tesla_charger_power
    unique_id: teslamate_1_charger_power
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charger_power"
    device_class: power
    unit_of_measurement: kW
    icon: mdi:lightning-bolt

- sensor:
    name: Charger Voltage
    object_id: tesla_charger_voltage
    unique_id: teslamate_1_charger_voltage
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/charger_voltage"
    device_class: voltage
    unit_of_measurement: V
    icon: mdi:lightning-bolt

- sensor:
    name: Scheduled Charging Start Time
    object_id: tesla_scheduled_charging_start_time
    unique_id: teslamate_1_scheduled_charging_start_time
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/scheduled_charging_start_time"
    device_class: timestamp
    icon: mdi:clock-outline

- sensor:
    name: Time To Full Charge
    object_id: tesla_time_to_full_charge
    unique_id: teslamate_1_time_to_full_charge
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/time_to_full_charge"
    unit_of_measurement: h
    icon: mdi:clock-outline

- sensor:
    name: TPMS Pressure Front Left
    object_id: tesla_tpms_fl
    unique_id: teslamate_1_tpms_fl
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/tpms_pressure_fl"
    unit_of_measurement: bar
    icon: mdi:car-tire-alert

- sensor:
    name: TPMS Pressure Front Right
    object_id: tesla_tpms_fr
    unique_id: teslamate_1_tpms_fr
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/tpms_pressure_fr"
    unit_of_measurement: bar
    icon: mdi:car-tire-alert

- sensor:
    name: TPMS Pressure Rear Left
    object_id: tesla_tpms_rl
    unique_id: teslamate_1_tpms_rl
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/tpms_pressure_rl"
    unit_of_measurement: bar
    icon: mdi:car-tire-alert

- sensor:
    name: TPMS Pressure Rear Right
    object_id: tesla_tpms_rr
    unique_id: teslamate_1_tpms_rr
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/tpms_pressure_rr"
    unit_of_measurement: bar
    icon: mdi:car-tire-alert

- binary_sensor:
    name: Healthy
    object_id: tesla_healthy
    unique_id: teslamate_1_healthy
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/healthy"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:heart-pulse

- binary_sensor:
    name: Update Available
    object_id: tesla_update_available
    unique_id: teslamate_1_update_available
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/update_available"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:alarm

- binary_sensor:
    name: Locked
    object_id: tesla_locked
    unique_id: teslamate_1_locked
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: lock
    state_topic: "teslamate/cars/1/locked"
    payload_on: "false"
    payload_off: "true"

- binary_sensor:
    name: Sentry Mode
    object_id: tesla_sentry_mode
    unique_id: teslamate_1_sentry_mode
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/sentry_mode"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:cctv

- binary_sensor:
    name: Windows Open
    object_id: tesla_windows_open
    unique_id: teslamate_1_windows_open
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: window
    state_topic: "teslamate/cars/1/windows_open"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:car-door

- binary_sensor:
    name: Doors Open
    object_id: tesla_doors_open
    unique_id: teslamate_1_doors_open
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: door
    state_topic: "teslamate/cars/1/doors_open"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:car-door

- binary_sensor:
    name: Trunk Open
    object_id: tesla_trunk_open
    unique_id: teslamate_1_trunk_open
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: opening
    state_topic: "teslamate/cars/1/trunk_open"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:car-side

- binary_sensor:
    name: Frunk Open
    object_id: tesla_frunk_open
    unique_id: teslamate_1_frunk_open
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: opening
    state_topic: "teslamate/cars/1/frunk_open"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:car-side

- binary_sensor:
    name: Is User Present
    object_id: tesla_is_user_present
    unique_id: teslamate_1_is_user_present
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: presence
    state_topic: "teslamate/cars/1/is_user_present"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:human-greeting

- binary_sensor:
    name: Is Climate On
    object_id: tesla_is_climate_on
    unique_id: teslamate_1_is_climate_on
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/is_climate_on"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:fan

- binary_sensor:
    name: Is Preconditioning
    object_id: tesla_is_preconditioning
    unique_id: teslamate_1_is_preconditioning
    availability: *teslamate_availability
    device: *teslamate_device_info
    state_topic: "teslamate/cars/1/is_preconditioning"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:fan

- binary_sensor:
    name: Plugged In
    object_id: tesla_plugged_in
    unique_id: teslamate_1_plugged_in
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: plug
    state_topic: "teslamate/cars/1/plugged_in"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:ev-station

- binary_sensor:
    name: Charge Port Door OPEN
    object_id: tesla_charge_port_door_open
    unique_id: teslamate_1_charge_port_door_open
    availability: *teslamate_availability
    device: *teslamate_device_info
    device_class: opening
    state_topic: "teslamate/cars/1/charge_port_door_open"
    payload_on: "true"
    payload_off: "false"
    icon: mdi:ev-plug-tesla

```

### sensor.yaml (sensor: section of configuration.yaml)

```yml title="sensor.yaml"
 - platform: template
   sensors:
    tesla_est_battery_range_mi:
      friendly_name: Estimated Range (mi)
      unit_of_measurement: mi
      icon_template: mdi:gauge
      value_template: >
       {{ (states('sensor.tesla_est_battery_range_km') | float / 1.609344) | round(2) }}

    tesla_rated_battery_range_mi:
      friendly_name: Rated Range (mi)
      unit_of_measurement: mi
      icon_template: mdi:gauge
      value_template: >
       {{ (states('sensor.tesla_rated_battery_range_km') | float / 1.609344) | round(2) }}

    tesla_ideal_battery_range_mi:
      friendly_name: Ideal Range (mi)
      unit_of_measurement: mi
      icon_template: mdi:gauge
      value_template: >
       {{ (states('sensor.tesla_ideal_battery_range_km') | float / 1.609344) | round(2) }}

    tesla_odometer_mi:
      friendly_name: Odometer (mi)
      unit_of_measurement: mi
      icon_template: mdi:counter
      value_template: >
       {{ (states('sensor.tesla_odometer') | float / 1.609344) | round(2) }}

    tesla_speed_mph:
      friendly_name: Speed (MPH)
      unit_of_measurement: mph
      icon_template: mdi:speedometer
      value_template: >
       {{ (states('sensor.tesla_speed') | float / 1.609344) | round(2) }}

    tesla_elevation_ft:
      friendly_name: Elevation (ft)
      unit_of_measurement: ft
      icon_template: mdi:image-filter-hdr
      value_template: >
       {{ (states('sensor.tesla_elevation') | float * 3.2808 ) | round(2) }}

    tesla_tpms_pressure_fl_psi:
      friendly_name: Front Left Tire Pressure (psi)
      unit_of_measurement: psi
      icon_template: mdi:car-tire-alert
      value_template: >
       {{ (states('sensor.tesla_tpms_pressure_fl_bar') | float * 14.50377) | round(2) }}

    tesla_tpms_pressure_fr_psi:
      friendly_name: Front Right Tire Pressure (psi)
      unit_of_measurement: psi
      icon_template: mdi:car-tire-alert
      value_template: >
       {{ (states('sensor.tesla_tpms_pressure_fr_bar') | float * 14.50377) | round(2) }}

    tesla_tpms_pressure_rl_psi:
      friendly_name: Rear Left Tire Pressure (psi)
      unit_of_measurement: psi
      icon_template: mdi:car-tire-alert
      value_template: >
       {{ (states('sensor.tesla_tpms_pressure_rl_bar') | float * 14.50377) | round(2) }}

    tesla_tpms_pressure_rr_psi:
      friendly_name: Rear Right Tire Pressure (psi)
      unit_of_measurement: psi
      icon_template: mdi:car-tire-alert
      value_template: >
       {{ (states('sensor.tesla_tpms_pressure_rr_bar') | float * 14.50377) | round(2) }}
```

### binary_sensor.yaml (binary_sensor: section of configuration.yaml)

```yml title="binary_sensor.yaml"
 - platform: template
   sensors:
    tesla_park_brake:
      friendly_name: Parking Brake
      icon_template: mdi:car-brake-parking
      value_template: >-
       {% if is_state('sensor.tesla_shift_state', 'P') %}
         ON
       {% else %}
         OFF
       {% endif %}
```

### ui-lovelace.yaml

The below is the Lovelace UI configuration used to make the example screenshot above. You will obviously want to configure this to your liking, however the example contains all of the sensors and values presented via MQTT and could be used as the basis of UI configuration.

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
              - entity: sensor.tesla_battery_level
                name: Battery Level
              - entity: sensor.tesla_state
                name: Car State
              - entity: binary_sensor.tesla_plugged_in
                name: Plugged In
          - type: glance
            entities:
              - entity: binary_sensor.tesla_park_brake
                name: Park Brake
              - entity: binary_sensor.tesla_sentry_mode
                name: Sentry Mode
              - entity: sensor.tesla_speed
                name: Speed
          - type: glance
            entities:
              - entity: binary_sensor.tesla_healthy
                name: Car Health
              - entity: binary_sensor.tesla_windows_open
                name: Window Status
          - type: horizontal-stack
            cards:
              - type: button
                entity: binary_sensor.tesla_locked
                name: Charger Door
                show_state: true
                state:
                  - value: locked
                    icon: mdi:lock
                    color: green
                    tap_action:
                      action: call-service
                      service: lock.unlock
                      service_data:
                        entity_id: lock.tesla_model_3_charger_door_lock
                  - value: unlocked
                    icon: mdi:lock-open
                    color: red
                    tap_action:
                      action: call-service
                      service: lock.lock
                      service_data:
                        entity_id: lock.tesla_model_3_charger_door_lock
              - type: button
                entity: lock.tesla_door_lock
                name: Car Door
                show_state: true
                state:
                  - value: locked
                    icon: mdi:lock
                    color: green
                    tap_action:
                      action: call-service
                      service: lock.unlock
                      service_data:
                        entity_id: lock.tesla_model_3_door_lock
                  - value: unlocked
                    icon: mdi:lock-open
                    color: red
                    tap_action:
                      action: call-service
                      service: lock.lock
                      service_data:
                        entity_id: lock.tesla_model_3_door_lock
      - type: vertical-stack
        cards:
          - type: map
            dark_mode: true
            default_zoom: 12
            entities:
              - device_tracker.tesla_location
          - type: thermostat
            entity: climate.tesla_model_3_hvac_climate_system
      - type: entities
        entities:
          - entity: sensor.tesla_display_name
            name: Name
          - entity: sensor.tesla_state
            name: Status
          - entity: sensor.tesla_since
            name: Last Status Change
          - entity: binary_sensor.tesla_healthy
            name: Logger Healthy
          - entity: sensor.tesla_version
            name: Software Version
          - entity: binary_sensor.tesla_update_available
            name: Available Update Status
          - entity: sensor.tesla_update_version
            name: Available Update Version
          - entity: sensor.tesla_model
            name: Tesla Model
          - entity: sensor.tesla_trim_badging
            name: Trim Badge
          - entity: sensor.tesla_exterior_color
            name: Exterior Color
          - entity: sensor.tesla_wheel_type
            name: Wheel Type
          - entity: sensor.tesla_spoiler_type
            name: Spoiler Type
          - entity: sensor.tesla_geofence
            name: Geo-fence Name
          - entity: proximity.home_tesla
            name: Distance to Home
          - entity: sensor.tesla_latitude
            name: Latitude
          - entity: sensor.tesla_longitude
            name: Longitude
          - entity: sensor.tesla_shift_state
            name: Shifter State
          - entity: sensor.tesla_speed
            name: Speed
          - entity: sensor.tesla_speed_mph
            name: Speed (MPH)
          - entity: sensor.tesla_heading
            name: Heading
          - entity: sensor.tesla_elevation
            name: Elevation (m)
          - entity: sensor.tesla_elevation_ft
            name: Elevation (ft)
          - entity: binary_sensor.tesla_locked
            name: Locked
          - entity: binary_sensor.tesla_sentry_mode
            name: Sentry Mode Enabled
          - entity: binary_sensor.tesla_windows_open
            name: Windows Open
          - entity: binary_sensor.tesla_doors_open
            name: Doors Open
          - entity: binary_sensor.tesla_trunk_open
            name: Trunk Open
          - entity: binary_sensor.tesla_frunk_open
            name: Frunk Open
          - entity: binary_sensor.tesla_is_user_present
            name: User Present
          - entity: binary_sensor.tesla_is_climate_on
            name: Climate On
          - entity: sensor.tesla_inside_temp
            name: Inside Temperature
          - entity: sensor.tesla_outside_temp
            name: Outside Temperature
          - entity: binary_sensor.tesla_is_preconditioning
            name: Preconditioning
          - entity: sensor.tesla_odometer
            name: Odometer
          - entity: sensor.tesla_odometer_mi
            name: Odometer (miles)
          - entity: sensor.tesla_est_battery_range_km
            name: Battery Range (km)
          - entity: sensor.tesla_est_battery_range_mi
            name: Estimated Battery Range (mi)
          - entity: sensor.tesla_rated_battery_range_km
            name: Rated Battery Range (km)
          - entity: sensor.tesla_rated_battery_range_mi
            name: Rated Battery Range (mi)
          - entity: sensor.tesla_ideal_battery_range_km
            name: Ideal Battery Range (km)
          - entity: sensor.tesla_ideal_battery_range_mi
            name: Ideal Battery Range (mi)
          - entity: sensor.tesla_battery_level
            name: Battery Level
          - entity: sensor.tesla_usable_battery_level
            name: Usable Battery Level
          - entity: binary_sensor.tesla_plugged_in
            name: Plugged In
          - entity: sensor.tesla_charge_energy_added
            name: Charge Energy Added
          - entity: sensor.tesla_charge_limit_soc
            name: Charge Limit
          - entity: binary_sensor.tesla_charge_port_door_open
            name: Charge Port Door Open
          - entity: sensor.tesla_charger_actual_current
            name: Charger Current
          - entity: sensor.tesla_charger_phases
            name: Charger Phases
          - entity: sensor.tesla_charger_power
            name: Charger Power
          - entity: sensor.tesla_charger_voltage
            name: Charger Voltage
          - entity: sensor.tesla_scheduled_charging_start_time
            name: Scheduled Charging Start Time
          - entity: sensor.tesla_time_to_full_charge
            name: Time To Full Charge
          - entity: sensor.tesla_tpms_pressure_fl_bar
            name: Front Left Tire Pressure (bar)
          - entity: sensor.tesla_tpms_pressure_fl_psi
            name: Front Left Tire Pressure (psi)
          - entity: sensor.tesla_tpms_pressure_fr_bar
            name: Front Right Tire Pressure (bar)
          - entity: sensor.tesla_tpms_pressure_fr_psi
            name: Front Right Tire Pressure (psi)
          - entity: sensor.tesla_tpms_pressure_rl_bar
            name: Rear Left Tire Pressure (bar)
          - entity: sensor.tesla_tpms_pressure_rl_psi
            name: Rear Left Tire Pressure (psi)
          - entity: sensor.tesla_tpms_pressure_rr_bar
            name: Rear Right Tire Pressure (bar)
          - entity: sensor.tesla_tpms_pressure_rr_psi
            name: Rear Right Tire Pressure (psi)
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
          
- id: plugin-tesla-notify
  alias: Notify if Tesla not plugged in at night
  trigger:
  - platform: time
    at: '19:30:00'
condition: and
conditions:
  - condition: state
    entity_id: sensor.tesla_plugged_in
    state: 'false'
  action:
  - service: notify.mobile_app_pixel_6_pro
    data:
      title: 🔌 Plug in your car 🚙
      message: 'Tesla: {{states(''sensor.tesla_battery_level'')}}% - {{states(''sensor.tesla_ideal_range'')|round(0)}}
        km'
  initial_state: true
  mode: single
```

