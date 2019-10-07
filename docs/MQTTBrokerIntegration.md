# MQTT Integration

The MQTT function within TeslaMate allows useful values to be published to a MQTT broker. This is useful in allowing other automation platforms to consume data from TeslaMate.

Unless the MQTT feature is disabled data is published to the following topics
(`$car_id` usually starts at 1):

| MQTT Topic                                  | Example | Description                        |
| ------------------------------------------- | ------- | ---------------------------------- |
| teslamate/cars/$car_id/battery_level        | 88      | Battery Level Percentage           |
| teslamate/cars/$car_id/charge_energy_added  | 5.06    | Last added energy in kW            |
| teslamate/cars/$car_id/charge_limit_soc     | 90      | Charge Limit Configured in Percentage |
| teslamate/cars/$car_id/charge_port_door_open | true   | Is the charger door open? Yes/No   |
| teslamate/cars/$car_id/charger_actual_current | 2.05  | Current amperage supplied by charger |
| teslamate/cars/$car_id/charger_phases       | 3       | Number of charger power phases (1-3) |
| teslamate/cars/$car_id/charger_power        | |
| teslamate/cars/$car_id/charger_voltage      | 240     | Charger Voltage                    |
| teslamate/cars/$car_id/display_name         | TBA     | TBA |
| teslamate/cars/$car_id/est_battery_range_km | 372.5   | Estimated Range in km              |
| teslamate/cars/$car_id/healthy              | true    | TBA |
| teslamate/cars/$car_id/ideal_battery_range_km | | |
| teslamate/cars/$car_id/inside_temp          | 20.8    | Inside Temperature in °C           |
| teslamate/cars/$car_id/latitude             | TBA     | |
| teslamate/cars/$car_id/locked               | false   | Is the car locked - true/false     |
| teslamate/cars/$car_id/longitude            | TBA     | |
| teslamate/cars/$car_id/odometer             | 1653    | Car odometer in km                 |
| teslamate/cars/$car_id/outside_temp         | 18.4    | Temperature in °C                  |
| teslamate/cars/$car_id/plugged_in           | true    | Is the car currently plugged into a charger - true/false |
| teslamate/cars/$car_id/rated_battery_range_km | |
| teslamate/cars/$car_id/scheduled_charging_start_time | |
| teslamate/cars/$car_id/sentry_mode          | false   | Is sentry mode active - true/false |
| teslamate/cars/$car_id/shift_state          | TBA     | |
| teslamate/cars/$car_id/speed                | 12      | Current Speed in km/h              |
| teslamate/cars/$car_id/state                | x       | suspended, x |
| teslamate/cars/$car_id/time_to_full_charge  | |
| teslamate/cars/$car_id/windows_open         | false   | Are any of the windows open - true/false |
