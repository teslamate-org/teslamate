# TeslaMate

[![](https://travis-ci.org/adriankumpf/teslamate.svg?branch=master)](https://travis-ci.org/adriankumpf/teslamate)
[![](https://coveralls.io/repos/github/adriankumpf/teslamate/badge.svg?branch=master)](https://coveralls.io/github/adriankumpf/teslamate?branch=master)
[![](https://images.microbadger.com/badges/version/teslamate/teslamate.svg)](https://hub.docker.com/r/teslamate/teslamate)
[![](https://images.microbadger.com/badges/image/teslamate/teslamate.svg)](https://microbadger.com/images/teslamate/teslamate)
[![](https://img.shields.io/docker/pulls/teslamate/teslamate?color=%23099cec)](https://hub.docker.com/r/teslamate/teslamate)
[![](https://img.shields.io/badge/Donate-PayPal-ff69b4.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YE4CPXRAV9CVL&source=url)

A powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir](https://elixir-lang.org/)**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

## Features

**Dashboards**

- Lifetime driving map
- Drive and charging reports
- Driving efficiency report
- Consumption (net / gross)
- Charge energy added vs energy used
- Vampire drain
- Projected 100% range (battery degradation)
- SOC charging stats
- Visited addresses
- History of installed updates

**General**

- Little to no additional vampire drain: the car will fall asleep after a certain idle time
- Automatic address lookup
- Locally enriches positions with elevation data
- Geo-fencing feature to create custom locations
- Supports multiple vehicles per Tesla Account

## Screenshots

![Drive Details](/docs/screenshots/drive.png)
![Web Interface](/docs/screenshots/web_interface.png)

<p align="center">
  <strong><a href="/docs/screenshots.md">MORE SCREENSHOTS</a></strong>
</p>

## Quick Start

The recommended way to install and run TeslaMate is to use Docker. Create a file called `docker-compose.yml` with the following content:

**docker-compose.yml**

```YAML
version: '3'

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
      - MQTT_HOST=mosquitto
    ports:
      - 4000:4000
    cap_drop:
      - all

  db:
    image: postgres:11
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:1.6
    restart: always
    ports:
      - 1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
    teslamate-db:
    teslamate-grafana-data:
    mosquitto-conf:
    mosquitto-data:
```

Afterwards start the stack with `docker-compose up`.

To sign in with your Tesla Account open the web interface at [http://your-ip-address:4000](http://localhost:4000).

The Grafana dashboards are available at [http://your-ip-address:3000](http://localhost:3000).

## Documentation

The TeslaMate documentation is available [here](docs/README.md).

- [Installation](docs/README.md#installation)
  - [Docker (recommended)](docs/installation/docker.md)
  - [Docker (advanced)](docs/installation/docker_advanced.md)
  - [Manual Installation on Debian/Ubuntu](docs/installation/debian.md)
- [Upgrading to a new version](docs/upgrading.md)
- [Configuration](docs/README.md#configuration)
  - [Environment Variables](docs/configuration/environment_variables.md)
  - [Sleep Configuration](docs/configuration/sleep.md)
- [Integrations](docs/README.md#integrations)
  - [HomeAssistant](docs/integrations/home_assistant.md)
  - [MQTT](docs/integrations/mqtt.md)
- [Frequently Asked Questions](docs/faq.md)
- [Development](docs/development.md)

## Donations

TeslaMate is open source and completely free for everyone to use.

Maintaining this project isn't effortless, or free. If you would like to
support further development, that would be awesome. If you don't, no problem;
just share your love and show your support.

<p align="center">
  <a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YE4CPXRAV9CVL&source=url">
    <img src="docs/images/paypal-donate-button.png" alt="Donate with PayPal" />
  </a>
</p>

## Credits

- Authors: Adrian Kumpf - [List of contributors](https://github.com/adriankumpf/teslamate/graphs/contributors)
- Distributed under MIT License
