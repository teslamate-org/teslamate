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

See [Docker (local install)](docs/installation/docker.md)

## Documentation

The TeslaMate documentation is available [here](docs/README.md).

- [Installation](docs/README.md#installation)
  - [Docker](docs/installation/docker.md) (simplified, recommended)
  - [Docker (advanced)](docs/installation/docker_advanced.md) (Reverse Proxy, Let's Encrypt Certificate, HTTP Basic Auth)
  - [Debian/Ubuntu](docs/installation/debian.md) (without Docker)
- [Upgrading to a new version](docs/upgrading.md)
- [Configuration](docs/README.md#configuration)
  - [Environment Variables](docs/configuration/environment_variables.md)
  - [Sleep Mode Configuration](docs/configuration/sleep.md)
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

- Authors: Adrian Kumpf
- [List of contributors](https://github.com/adriankumpf/teslamate/graphs/contributors)
- Distributed under MIT License
