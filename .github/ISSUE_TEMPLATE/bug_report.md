---
name: Bug report
about: Create a report to improve this project
title: ""
labels: bug
assignees: ""
---

**Describe the bug**

A clear and concise description of what the bug is.

**To Reproduce**

Steps to reproduce the behavior:

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected behavior**

A clear and concise description of what you expected to happen.

**Relevant entries from the logs**

You must provide the logs of the teslamate container/application unless the bug can be narrowed down to Grafana.
To get the teslamate Docker container logs, for example, use the following command: `docker-compose logs teslamate`.

```
paste logs here
```

**Screenshots**

If applicable, add screenshots to help explain the problem.

**Data**

If applicable, add an export of the data for the given period.

For example, to export charge data after January 1, 2020:

```bash
docker-compose exec database psql teslamate teslamate -c \
   "COPY (select * from charges where date > '2020-01-01') TO STDOUT WITH CSV HEADER" > charges.csv

docker-compose exec database psql teslamate teslamate -c \
   "COPY (select * from charging_processes where start_date > '2020-01-01') TO STDOUT WITH CSV HEADER" > charging_processes.csv
```

To export drive data after January 1, 2020:

```bash
docker-compose exec database psql teslamate teslamate -c \
   "COPY (select id, car_id, drive_id, date, elevation, speed, power, odometer, ideal_battery_range_km, est_battery_range_km, rated_battery_range_km, battery_level, usable_battery_level, battery_heater_no_power, battery_heater_on, battery_heater, inside_temp, outside_temp, fan_status, driver_temp_setting, passenger_temp_setting, is_climate_on, is_rear_defroster_on, is_front_defroster_on from positions where date > '2020-01-20') TO STDOUT WITH CSV HEADER" > positions.csv

docker-compose exec database psql teslamate teslamate -c \
   "COPY (select * from drives where start_date > '2020-01-01') TO STDOUT WITH CSV HEADER" > drives.csv
```

**Operating environment**

- TeslaMate Version: [e.g. v1.14.0]
- Type of installation: [e.g. Docker or Manual]
- OS: [e.g. Ubuntu]
