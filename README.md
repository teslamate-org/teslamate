# TeslaMate

[![Build Status](https://travis-ci.org/adriankumpf/teslamate.svg?branch=master)](https://travis-ci.org/adriankumpf/teslamate)
[![](https://images.microbadger.com/badges/version/teslamate/teslamate.svg)](https://microbadger.com/images/teslamate/teslamate 'Get your own version badge on microbadger.com')
[![](https://images.microbadger.com/badges/image/teslamate/teslamate.svg)](https://microbadger.com/images/teslamate/teslamate 'Get your own image badge on microbadger.com')

A data logger for your Tesla.

- Written in [Elixir](https://elixir-lang.org/)
- Data is stored in PostgreSQL
- Visualization and data analysis with Grafana
- Current vehicle data is published to a local MQTT Broker _(optional)_

## Features

**Dashboards**

- Lifetime driving map
- Trip and charging reports
- Driving efficiency report
- Consumption (net / gross)
- Vampire drain
- Projected 100% range (battery degradation)
- SOC charging stats
- Visited addresses
- History of installed updates

**General**

- Little to no additional vampire drain: the car will fall asleep after a
  certain idle time
- Built-in API to manually suspend / resume sending requests to the Tesla API
- Automatic address lookup
- Supports multiple vehicles per Tesla Account

## Screenshots

![Trip](screenshots/trip.png)
![Trips](screenshots/trips.png)
![States](screenshots/states.png)
![Charging](screenshots/charging.png)
![Charging History](screenshots/charging_history.png)
![Vampire Drain](screenshots/vampire_drain.png)

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Upgrading](#upgrading)
4. [Web Interface](#web-interface)
5. [MQTT](#mqtt)
6. [FAQ](#faq)

## Installation

### Docker Installation (recommended)

If you already have PostgreSQL and Grafana running elsewhere just pull the image
and run the container:

```bash
# Run the container
docker run -d --env-file .env -p 4000:4000 teslamate/teslamate:latest
```

You still need to set a few environment variables. See
[Configuration](#configuration).

Alternatively use a `docker-compose.yml` file:

```YAML
version: '3'
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: unless-stopped
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
      - TESLA_USERNAME=username@example.com
      - TESLA_PASSWORD=secret
      - MQTT_HOST=mosquitto
    ports:
      - 4000:4000
    cap_drop:
      - all

  db:
    image: postgres:11
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: grafana/grafana:6.3.0-beta2
    environment:
      - GF_ANALYTICS_REPORTING_ENABLED=FALSE
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ALLOW_EMBEDDING=true
      - GF_SECURITY_DISABLE_GRAVATAR=true
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=pr0ps-trackmap-panel,natel-discrete-panel
    ports:
      - 3000:3000
    volumes:
      - grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:1.6
    ports:
      - 1883:1883
      - 9001:9001
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
    teslamate-db:
    grafana-data:
    mosquitto-conf:
    mosquitto-data:
```

Start everything with `docker-compose up`.

Finally, [import](#dashboards) the Grafana dashboards.

### Manual Installation

1. Install PostgreSQL and create a database (e.g. `teslamate`)
2. Install Grafana with the following plugins: `pr0ps-trackmap-panel` and
   `natel-discrete-panel`. Then [import](#dashboards) the dashboard JSON files.
3. _Optional:_ Install [mosquitto](https://mosquitto.org/) or another MQTT broker
4. Compile and build TeslaMate:

   **Requirements**

   - Elixir ([Installing Elixir](https://elixir-lang.org/install.html))
   - Node.js with npm or yarn

   Clone the repository and then build the release:

   ```bash
   mix deps.get --only prod
   MIX_ENV=prod mix compile

    # a) with yarn
    (cd assets && yarn install && yarn deploy)

    # b) with npm
    npm install --prefix ./assets && npm run deploy --prefix ./assets

    mix phx.digest
    MIX_ENV=prod mix release
   ```

   Before the first application startup run the database migrations:

   ```bash
    _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
   ```

   Afterwards start the application regularly:

   ```bash
    _build/prod/rel/teslamate/bin/teslamate start
   ```

Finally, [import](#dashboards) the Grafana dashboards.

### Dashboards

1.  Visit [localhost:3000](http://localhost:3000) and log in.

2.  Create a data source

    With a `docker-compose.yml` like above the data source configuration would
    look like this:

    ```
    Type: PostgreSQL
    Name: TeslaMate
    Host: db
    Database: teslamate
    User: teslamate  Password: secret
    SSL-Mode: disable
    Version: 10
    ```

3.  Import the Dashboard [JSON Files](dashboards) included in this repository
    manually or setup `wizzy`:

    Download and install wizzy

    ```bash
    npm install -g wizzy
    ```

    Configure grafana properties

    ```bash
    wizzy init
    wizzy set grafana url http://localhost:3000
    wizzy set grafana username admin
    wizzy set grafana password admin
    ```

    Export the dashboards to Grafana

    ```bash
    # English Translations
    for d in dashboards/en_*; do wizzy export dashboard $(basename $d .json); done

    # German Translations
    for d in dashboards/de_*; do wizzy export dashboard $(basename $d .json); done
    ```

4.  _Optional:_ To permanently switch a dashboard to **Miles and Fahrenheit** change the
    variables via the respective dropdown menus, hit the save button and enable
    the `Save current variables` switch.

## Configuration

TeslaMate uses environment variables for runtime configuration.

### Environment Variables

| Variable Name          | Description                                                                                                                                                                                                      | Default Value                 |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| DATABASE_USER          | Username (**required**)                                                                                                                                                                                          | /                             |
| DATABASE_PASS          | User password (**required**)                                                                                                                                                                                     | /                             |
| DATABASE_NAME          | The database to connect to (**required**)                                                                                                                                                                        | /                             |
| DATABASE_HOST          | Hostname of the database server (**required**)                                                                                                                                                                   | /                             |
| DATABASE_PORT          | Port of the database server                                                                                                                                                                                      | 5432                          |
| DATABASE_POOL_SIZE     | Size of the database connection pool                                                                                                                                                                             | 5                             |
| TESLA_USERNAME         | Username / email of your Tesla account (**required**)                                                                                                                                                            | /                             |
| TESLA_PASSWORD         | Password of your Tesla account (**required**)                                                                                                                                                                    | /                             |
| VIRTUAL_HOST           | Host part used for generating URLs throughout the app                                                                                                                                                            | localhost                     |
| PORT                   | Port where the web interface is exposed                                                                                                                                                                          | 4000                          |
| DISABLE_MQTT           | Disables the MQTT feature if `true`                                                                                                                                                                              | false                         |
| MQTT_HOST              | Hostname of the broker (**required** unless DISABLE_MQTT is `true`)                                                                                                                                              | /                             |
| MQTT_USERNAME          | Username _(optional)_                                                                                                                                                                                            | /                             |
| MQTT_PASSWORD          | Password _(optional)_                                                                                                                                                                                            | /                             |
| ENABLE_LOGGER_TELEGRAM | Enables a [logger backend](https://github.com/adriankumpf/logger-telegram-backend) for telegram. If `true` error and crash reports are forwarded to the configured chat. Usually not needed for stable releases. | false                         |
| CHAT_ID                | Telegram chat id (only **required** if `ENABLE_LOGGER_TELEGRAM` is `true`). See [here](https://github.com/adriankumpf/logger-telegram-backend#configuration) for instructions.                                   | /                             |
| TOKEN                  | Telegram bot token (only **required** if `ENABLE_LOGGER_TELEGRAM` is `true`). See [here](https://github.com/adriankumpf/logger-telegram-backend#configuration) for instructions.                                 | /                             |
| LOCALE                 | The default locale for the web interface. Currently available: `en` (default) and `de`                                                                                                                           | en                            |
| SECRET_KEY_BASE        | Secret key used as a base to generate secrets for encrypting and signing data                                                                                                                                    | randomly generated at startup |
| SIGNING_SALT           | A salt used with secret_key_base to generate a key for signing/verifying a cookie (required by LiveView; Sessions are not used otherwise)                                                                        | randomly generated at startup |

## Upgrading

> Before updating please check the [Changelog](CHANGELOG.md) to find out
> whether the dashboards need to be updated / imported again.

### Docker

Pull the image with the new tag: `docker pull teslamate/teslamate:1.x.x`. Stop
and remove the old container: `docker stop <container_name> && docker rm <container_name>`.
Start a new container with the latest tag: `docker run -d -p 4000:4000 teslamate/teslamate:1.x.x`.

Alternatively, with Docker Compose, define the new tag in the
`docker-compose.yml` file and restart the container.

### Manually

Pull the new changes from the git repository then build the new release as
described [here](#manual-installation).

If an upgrade requires to run new database migrations continue with the
following command:

```bash
 _build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
```

## Web Interface

There is a basic real-time web interface. Once the application is running locally, you
can access it at [localhost:4000](http://localhost:4000).

![Web Interface](screenshots/web_interface.png)

## MQTT

Unless the MQTT feature is disabled data is published to the following topics
(`$car_id` usually starts at 1):

```
teslamate/cars/$car_id/display_name
teslamate/cars/$car_id/state
teslamate/cars/$car_id/battery_level
teslamate/cars/$car_id/ideal_battery_range_km
teslamate/cars/$car_id/charge_energy_added
teslamate/cars/$car_id/speed
teslamate/cars/$car_id/outside_temp
teslamate/cars/$car_id/inside_temp
teslamate/cars/$car_id/locked
teslamate/cars/$car_id/sentry_mode
```

## FAQ

**Sometimes the first few minutes of a trip are not recorded even though the
car was online. Why?**

Ideally, TeslaMate would frequently scrape the Tesla API – 24/7. However, the
vehicle cannot fall asleep as long as data is requested. Therefore TeslaMate
suspends scraping for 21 minutes if the vehicle idles for 15 minutes, so that
it can go into sleep mode. Consequently, if you start driving again during
those 21 minutes nothing is logged.

**Solution:** To get around this you can use your smartphone to tell TeslaMate
to start scraping again. In short, create a workflow with
[Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=en)
(Android) or [Shortcuts](https://support.apple.com/guide/shortcuts/welcome/ios)
(iOS) that listens for connected Bluetooth devices. If a connection to your
Tesla is established send an HTTP PUT request to your publicly exposed
TeslaMate instance.

_(With iOS 12 and below workflows are quite limited but can be triggered
manually. iOS 13 will probably fix that.)_

```
PUT https://teslamate.your-domain.com/api/car/$car_id/logging/resume
PUT https://teslamate.your-domain.com/api/car/$car_id/logging/suspend
```

I strongly recommend to use a reverse-proxy with HTTPS and basic access
authentication when exposing TeslaMate to the public internet. Additionally
only permit access to `/api/car/$car_id/logging/resume` and/or
`/api/car/$car_id/logging/suspend`.

**Why is the "Consumption" / "Charging" dashboard not showing any data?**

Both dashboards don't show any data by default. Instead, you need to choose a
particular trip or charging process in the `Trips` / `Charging History`
dashboard by clicking on its start date.

## Disclaimer

Please note that the use of the Tesla API in general and this software in
particular is not endorsed by Tesla. Use at your own risk.

## Credits

- [TeslaLogger](https://github.com/bassmaster187/TeslaLogger) was a big
  inspiration especially during early development. Thanks!
