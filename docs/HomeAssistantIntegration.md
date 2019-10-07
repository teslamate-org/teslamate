# HomeAssistant Integration


### sensor.yaml (sensor: section of configuration.yaml)
```
- platform: mqtt
  name: tesla_battery_level
  state_topic: "teslamate/cars/1/battery_level"
  unit_of_measurement: '%'
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_energy_added
  state_topic: "teslamate/cars/1/charge_energy_added"
  unit_of_measurement: 'kW'
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_limit
  state_topic: "teslamate/cars/1/charge_limit_soc"
  unit_of_measurement: '%'
  icon: mdi:battery-80

- platform: mqtt
  name: tesla_charge_port_door_open
  state_topic: "teslamate/cars/1/charge_port_door_open"
  icon: mdi:car-door
  
- platform: mqtt
  name: tesla_charger_actual_current
  state_topic: "teslamate/cars/1/charger_actual_current"
  unit_of_measurement: 'A'
  icon: mdi:battery-80
  
- platform: mqtt
  name: tesla_charger_phases
  state_topic: "teslamate/cars/1/charger_phases"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_charger_power
  state_topic: "teslamate/cars/1/charger_power"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_charger_voltage
  state_topic: "teslamate/cars/1/charger_voltage"
  icon: mdi:gauge

- platform: mqtt
  name: tesla_display_name
  state_topic: "teslamate/cars/1/display_name"
  icon: mdi:car

- platform: mqtt
  name: tesla_estimated_range
  state_topic: "teslamate/cars/1/est_battery_range_km"
  unit_of_measurement: 'km'
  icon: mdi:map-marker-path

- platform: mqtt
  name: tesla_healthy
  state_topic: "teslamate/cars/1/healthy"
  icon: mdi:car-connected

- platform: mqtt
  name: tesla_ideal_range
  state_topic: "teslamate/cars/1/ideal_battery_range_km"
  unit_of_measurement: 'km'
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
  icon: mdi:gauge

- platform: mqtt
  name: tesla_outside_temp
  state_topic: "teslamate/cars/1/outside_temp"
  unit_of_measurement: °C
  icon: mdi:thermometer-lines

- platform: mqtt
  name: tesla_plugged_in
  state_topic: "teslamate/cars/1/plugged_in"
  icon: mdi:power-plug

- platform: mqtt
  name: tesla_rated_range
  state_topic: "teslamate/cars/1/rated_battery_range_km"
  unit_of_measurement: 'km'
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
```
