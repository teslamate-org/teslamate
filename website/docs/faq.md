---
title: Frequently Asked Questions
sidebar_label: FAQ
---

## How to generate your own tokens

There are multiple apps available to securely generate access tokens yourself, for example:

- [Tesla Auth (macOS, Linux, Windows)](https://github.com/adriankumpf/tesla_auth)
- [Auth app for Tesla (iOS, macOS)](https://apps.apple.com/us/app/auth-app-for-tesla/id1552058613)

## Why are no consumption values displayed in Grafana?

Unfortunately the Tesla API does not return consumption values for a trip. In order to still be able to display values TeslaMate estimates the consumption on the basis of the recorded (charging) data.
It takes **at least two** charging sessions before the first estimate can be displayed. Charging sessions have to be longer than 10 minutes and less than 95% state-of-charge (SoC). Each future charging session will slightly improve the accuracy of the estimate, which is applied retroactively to all data.

## Why "null" is displayed above the panels in Grafana?

If you have not customized the name of your Tesla, Teslamate saves an empty value in the PostgreSQL database. When Grafana is reading from the database, the value `null` is the value for the variable car_id in Grafana.

Give your Tesla a name via car touchscreen and wait for Teslamate to synchronize it.

## What is the geo-fence feature for?

At the moment geo-fences are a way to create custom locations like `🏡 Home` or `🛠️ Work` That may be particularly useful if the addresses (which are provided by [OpenStreetMap](https://www.openstreetmap.org)) in your region are inaccurate or if you street-park at locations where the exact address may vary.

## Help, my car does not fall asleep

The accessory power functionality prevents your car from going to sleep even if no accessory is connected. You can disable it by setting Controls > Charging > Keep Accessory Power Off.

Cars with Media Control Unit version 1 (MCU1) require certain settings to be able to fall asleep. Model S and Model X cars built before 3/2018 have the MCU1 unit, this can also be checked from the Software -> Additional vehicle information. If the 'Infotainment processor' is 'NVIDIA Tegra', the car is equipped with MCU1.

The settings needed to enable the sleep mode with MCU1 are:

- 'Display' -> 'Energy saving' -> ON
- 'Display' -> 'Always connected' -> unchecked
- 'Safety & security' -> 'Cabin overheat protection' -> OFF

With these settings the MCU1 cars should fall asleep within some 15 minutes of inactivity. This is what you should see in the log when streaming mode is enabled in TeslaMate

- `[info] Suspending logging` after 3 minutes of inactivity (doors locked)
- `[info] Fetching vehicle state ...` about 21 minutes later. The car should have fallen asleep during this period

In this example the driver's door was opened and closed:

```bash
teslamate_1     | 2021-03-16 11:41:19.336 car_id=1 [info] Start / :online
teslamate_1     | 2021-03-16 11:41:19.603 car_id=1 [info] Connecting ...
teslamate_1     | 2021-03-16 11:44:41.380 car_id=1 [info] Suspending logging
teslamate_1     | 2021-03-16 12:03:27.356 car_id=1 [info] Fetching vehicle state ...
teslamate_1     | 2021-03-16 12:03:28.123 car_id=1 [info] Start / :asleep
teslamate_1     | 2021-03-16 12:03:28.139 car_id=1 [info] Disconnecting ...
```

![image](https://user-images.githubusercontent.com/2128464/111361149-38238380-8696-11eb-950d-aba298206d2d.png)

**Note!** If you are using some other data logger like TeslaFi at the same time, the sleep attempts probably fail as the other data logger is keeping the car awake. Especially calling the [Vehicle Data API](https://www.teslaapi.io/vehicles/state-and-settings#vehicle-data) will reset the car's inactivity timer.

## Why am I missing data when not using the Streaming API?

The problem with the polling mode is that the car does not fall asleep before it have been inactive for some 15 minutes. TeslaMate will suspend all polling after the car has been idle for 3 minutes (the 'Idle Time Before Trying to Sleep' setting), and will resume polling 15 minutes later (the 'Time to Try Sleeping' setting).
Any activity during this 15 minutes can't be detected, as calling the [Vehicle Data API](https://www.teslaapi.io/vehicles/state-and-settings#vehicle-data) would reset the car's inactivity timer, preventing the car from falling asleep.

Calling the [Vehicle API](https://www.teslaapi.io/vehicles/list#vehicle) does not reset the inactivity timer, but it only tells if the car is either online (driving, charging, idle, about to fall asleep) or asleep. It can't tell if an idle car started driving during the 'Time to Try Sleeping' period.

## Why are my Docker timestamp logs different than my machine?

Docker container timezones default to UTC. To set the timezone for your container, use the `TZ` Environment Variable in your YML file. More information found at [Environment Variables](https://docs.teslamate.org/docs/configuration/environment_variables)

## Which network flows must be authorized?

⚠️ This is for advanced users!

You might want to prohibit all network flows except those necessary for teslamate.
This is a common practice to harden an installation (e.g., to reduce the risk of data leakage).

The following flows must be authorized (egress traffic and DNS resolution):

HTTPS (TCP/443)  
auth.tesla.com  
owner-api.teslamotors.com  
streaming.vn.teslamotors.com  
nominatim.openstreetmap.org

HTTP (TCP/80)  
step.esa.int

Note: This may change when Teslamate is updated!
