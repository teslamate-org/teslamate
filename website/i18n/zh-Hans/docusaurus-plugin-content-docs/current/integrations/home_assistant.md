---
title: HomeAssistant 整合
sidebar_label: HomeAssistant
---

虽然 HomeAssistant 为特斯拉汽车提供了一个官方组件，但该组件最近没有更新，也没有 TeslaMate 的复杂的轮询机制，导致该组件的默认值使车辆保持清醒并耗尽电池。

本指南的最终目标是尽可能多地消耗 TeslaMate 的投票数据，以取代大部分官方特斯拉组件的投票功能。

如果你的目的是只使用只读的传感器值，那些由 TeslaMate 通过 MQTT 提供的值就足够了，你不需要利用官方的 Tesla 组件。然而，如果你希望能够向特斯拉 API 写入数值（锁定/解锁车门或自动气候），有一个解决方案，涉及为特斯拉组件配置一个极高的轮询间隔，并使用自动化从 TeslaMate MQTT 参数中填充数值。

**截图**

import useBaseUrl from '@docusaurus/useBaseUrl';

<img alt="HASS Screenshot" src={useBaseUrl('img/hass-dashboard.png')} />

**目前状况**

- 传感器：特斯拉组件所暴露的所有传感器都可用
- 锁：未应用
- 气候：未应用

## 配置

### automation.yaml

下面提供一个自动化程序，当新的纬度/伦度值发布到 MQTT 时，更新 `device_tracker.tesla_location` 追踪器的位置。你可以用它来：

- 在地图上画出你的特斯拉的位置（见 _ui-lovelace.yaml_ 文件中的一个例子）
- 计算你的特斯拉与另一地点的距离，如家（见下面的 _configuration.yaml_）。

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
        gps: ["{{ states.sensor.tesla_latitude.state }}", "{{ states.sensor.tesla_longitude.state }}"]
```

### configuration.yaml

接近传感器使我们能够计算出特斯拉 `device_tracker` 与定义区域的接近程度。这在以下方面很有用：

- 当你到家时自动打开车库门
- 车辆到达时的通知

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

mqtt:
  sensor: !include mqtt_sensor.yaml
  binary_sensor: !include mqtt_binary_sensor.yaml
sensor: !include sensor.yaml
binary_sensor: !include binary_sensor.yaml
```

### known_devices.yaml (define a tracker for Tesla)

这是上面的自动化所需要的（在 _automation.yaml_ 部分）。它定义了 device_tracker 对象，我们用它来表示你的特斯拉车辆的位置。

```yml title="known_devices.yaml"
tesla_location:
  hide_if_away: false
  icon: mdi:car
  mac:
  name: Tesla
  picture:
  track: true
```

### mqtt_sensor.yaml (mqtt: sensor: section of configuration.yaml)

```yml title="mqtt_sensor.yaml"
- name: tesla_display_name
  state_topic: "teslamate/cars/1/display_name"
  icon: mdi:car

- name: tesla_state
  state_topic: "teslamate/cars/1/state"
  icon: mdi:car-connected

- name: tesla_since
  state_topic: "teslamate/cars/1/since"
  device_class: timestamp
  icon: mdi:clock-outline

- name: tesla_version
  state_topic: "teslamate/cars/1/version"
  icon: mdi:alphabetical

- name: tesla_update_version
  state_topic: "teslamate/cars/1/update_version"
  icon: mdi:alphabetical

- name: tesla_model
  state_topic: "teslamate/cars/1/model"

- name: tesla_trim_badging
  state_topic: "teslamate/cars/1/trim_badging"
  icon: mdi:shield-star-outline

- name: tesla_exterior_color
  state_topic: "teslamate/cars/1/exterior_color"
  icon: mdi:palette

- name: tesla_wheel_type
  state_topic: "teslamate/cars/1/wheel_type"

- name: tesla_spoiler_type
  state_topic: "teslamate/cars/1/spoiler_type"
  icon: mdi:car-sports

- name: tesla_geofence
  state_topic: "teslamate/cars/1/geofence"
  icon: mdi:earth

- name: tesla_latitude
  state_topic: "teslamate/cars/1/latitude"
  unit_of_measurement: °
  icon: mdi:crosshairs-gps

- name: tesla_longitude
  state_topic: "teslamate/cars/1/longitude"
  unit_of_measurement: °
  icon: mdi:crosshairs-gps

- name: tesla_shift_state
  state_topic: "teslamate/cars/1/shift_state"
  icon: mdi:car-shift-pattern

- name: tesla_power
  state_topic: "teslamate/cars/1/power"
  device_class: power
  unit_of_measurement: W
  icon: mdi:flash

- name: tesla_speed
  state_topic: "teslamate/cars/1/speed"
  unit_of_measurement: "km/h"
  icon: mdi:speedometer

- name: tesla_heading
  state_topic: "teslamate/cars/1/heading"
  unit_of_measurement: °
  icon: mdi:compass

- name: tesla_elevation
  state_topic: "teslamate/cars/1/elevation"
  unit_of_measurement: m
  icon: mdi:image-filter-hdr

- name: tesla_inside_temp
  state_topic: "teslamate/cars/1/inside_temp"
  device_class: temperature
  unit_of_measurement: °C
  icon: mdi:thermometer-lines

- name: tesla_outside_temp
  state_topic: "teslamate/cars/1/outside_temp"
  device_class: temperature
  unit_of_measurement: °C
  icon: mdi:thermometer-lines

- name: tesla_odometer
  state_topic: "teslamate/cars/1/odometer"
  unit_of_measurement: km
  icon: mdi:counter

- name: tesla_est_battery_range_km
  state_topic: "teslamate/cars/1/est_battery_range_km"
  unit_of_measurement: km
  icon: mdi:gauge

- name: tesla_rated_battery_range_km
  state_topic: "teslamate/cars/1/rated_battery_range_km"
  unit_of_measurement: km
  icon: mdi:gauge

- name: tesla_ideal_battery_range_km
  state_topic: "teslamate/cars/1/ideal_battery_range_km"
  unit_of_measurement: km
  icon: mdi:gauge

- name: tesla_battery_level
  state_topic: "teslamate/cars/1/battery_level"
  device_class: battery
  unit_of_measurement: "%"
  icon: mdi:battery-80

- name: tesla_usable_battery_level
  state_topic: "teslamate/cars/1/usable_battery_level"
  unit_of_measurement: "%"
  icon: mdi:battery-80

- name: tesla_charge_energy_added
  state_topic: "teslamate/cars/1/charge_energy_added"
  device_class: energy
  unit_of_measurement: kWh
  icon: mdi:battery-charging

- name: tesla_charge_limit_soc
  state_topic: "teslamate/cars/1/charge_limit_soc"
  unit_of_measurement: "%"
  icon: mdi:battery-charging-100

- name: tesla_charger_actual_current
  state_topic: "teslamate/cars/1/charger_actual_current"
  device_class: current
  unit_of_measurement: A
  icon: mdi:lightning-bolt

- name: tesla_charger_phases
  state_topic: "teslamate/cars/1/charger_phases"
  icon: mdi:sine-wave

- name: tesla_charger_power
  state_topic: "teslamate/cars/1/charger_power"
  device_class: power
  unit_of_measurement: kW
  icon: mdi:lightning-bolt

- name: tesla_charger_voltage
  state_topic: "teslamate/cars/1/charger_voltage"
  device_class: voltage
  unit_of_measurement: V
  icon: mdi:lightning-bolt

- name: tesla_scheduled_charging_start_time
  state_topic: "teslamate/cars/1/scheduled_charging_start_time"
  device_class: timestamp
  icon: mdi:clock-outline

- name: tesla_time_to_full_charge
  state_topic: "teslamate/cars/1/time_to_full_charge"
  unit_of_measurement: h
  icon: mdi:clock-outline
```

### mqtt_binary_sensor.yaml (mqtt: binary_sensor: section of configuration.yaml)

```yml title="mqtt_binary_sensor.yaml"
- name: tesla_healthy
  state_topic: "teslamate/cars/1/healthy"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:heart-pulse

- name: tesla_update_available
  state_topic: "teslamate/cars/1/update_available"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:alarm

- name: tesla_locked
  device_class: lock
  state_topic: "teslamate/cars/1/locked"
  payload_on: "false"
  payload_off: "true"

- name: tesla_sentry_mode
  state_topic: "teslamate/cars/1/sentry_mode"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:cctv

- name: tesla_windows_open
  device_class: window
  state_topic: "teslamate/cars/1/windows_open"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:car-door

- name: tesla_doors_open
  device_class: door
  state_topic: "teslamate/cars/1/doors_open"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:car-door

- name: tesla_trunk_open
  device_class: opening
  state_topic: "teslamate/cars/1/trunk_open"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:car-side

- name: tesla_frunk_open
  device_class: opening
  state_topic: "teslamate/cars/1/frunk_open"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:car-side

- name: tesla_is_user_present
  device_class: presence
  state_topic: "teslamate/cars/1/is_user_present"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:human-greeting

- name: tesla_is_climate_on
  state_topic: "teslamate/cars/1/is_climate_on"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:fan

- name: tesla_is_preconditioning
  state_topic: "teslamate/cars/1/is_preconditioning"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:fan

- name: tesla_plugged_in
  device_class: plug
  state_topic: "teslamate/cars/1/plugged_in"
  payload_on: "true"
  payload_off: "false"
  icon: mdi:ev-station

- name: tesla_charge_port_door_open
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

以下是用于制作上述截图示例的 Lovelace 用户界面配置。显然，你会想根据自己的喜好进行配置，但是这个例子包含了所有的传感器和通过 MQTT 呈现的值，可以作为用户界面配置的基础。

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
```

## 实用的自动化

下面的自动程序利用 TeslaMate MQTT 主题来提供一些有用的自动程序

### 基于特斯拉位置的车库门自动化

当特斯拉从 "not_home" 过渡到 "home" 时，这种自动化就会触发。这意味着车辆之前必须是在家庭区域之外，然后回到家里。你可能想在这里添加条件以提高准确性，如一天中的时间。

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

### 门窗未关的通知

以下一组自动程序和脚本将检测特斯拉的车门、行李箱、后备箱或窗户何时被打开。脚本将在定义的时间段（默认为 5 分钟）后通知你。如果你想自定义通知的执行方式，你可以编辑 `notify_tesla_open` 脚本，它被所有四个通知所调用。

默认情况下，该脚本将每 5 分钟重复通知一次。如果你只想被通知一次，请删除 `notify_tesla_open` 脚本中的递归 `script.turn_on` 序列。

我们在每个通知后添加了随机的 30 秒间隔，以避免当我们同时打开多个东西时，通知脚本被打乱。例如，打开门将打开门和窗户。如果我们不延迟调用，我们将只得到关于窗户的信息（因为它是对脚本的最后一次调用），如果我们随后关闭窗户，我们将不会得到关于其他未关闭事物的通知。这就导致了更多的通知，但也减少了遗漏知道某些东西被打开的机会。

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
