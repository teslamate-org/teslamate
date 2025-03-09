# TeslaMate

[![CI](https://github.com/teslamate-org/teslamate/actions/workflows/devops.yml/badge.svg)](https://github.com/teslamate-org/teslamate/actions/workflows/devops.yml)
[![Publish Docker images](https://github.com/teslamate-org/teslamate/actions/workflows/buildx.yml/badge.svg)](https://github.com/teslamate-org/teslamate/actions/workflows/buildx.yml)
[![Coverage](https://coveralls.io/repos/github/teslamate-org/teslamate/badge.svg?branch=master)](https://coveralls.io/github/teslamate-org/teslamate?branch=master)
[![current version](https://img.shields.io/docker/v/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![docker image size](https://img.shields.io/docker/image-size/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![docker pulls](https://img.shields.io/docker/pulls/teslamate/teslamate?color=%23099cec)](https://hub.docker.com/r/teslamate/teslamate)

A powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir](https://elixir-lang.org/)**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

## Documentation

The documentation is available at [https://docs.teslamate.org](https://docs.teslamate.org/)

## Features

### Dashboards

- [Drive and charging reports](https://docs.teslamate.org/docs/screenshots#charging-details)
- [Driving efficiency report](https://docs.teslamate.org/docs/screenshots#efficiency)
- [Consumption (net / gross)](https://docs.teslamate.org/docs/screenshots#efficiency)
- [Charge energy added vs energy used](https://docs.teslamate.org/docs/screenshots#charges)
- [Vampire drain](https://docs.teslamate.org/docs/screenshots#vampire-drain)
- [Projected 100% range (battery degradation)](https://docs.teslamate.org/docs/screenshots#projected-range)
- [Charging Stats](https://docs.teslamate.org/docs/screenshots#charging-stats)
- [Drive Stats](https://docs.teslamate.org/docs/screenshots#drive-stats)
- [History of installed updates](https://docs.teslamate.org/docs/screenshots#updates)
- [See when your car was online or asleep](https://docs.teslamate.org/docs/screenshots#states)
- [Lifetime driving map](https://docs.teslamate.org/docs/screenshots/#lifetime-driving-map)
- [Visited addresses](https://docs.teslamate.org/docs/screenshots/#visited-addresses)
- [Battery Health](https://docs.teslamate.org/docs/screenshots/#battery-health)
- [Database Information](https://docs.teslamate.org/docs/screenshots/#database-information)

### General

- High precision drive data recording
- No additional vampire drain: the car will fall asleep as soon as possible
- Automatic address lookup
- Easy integration into Home Assistant (via MQTT)
- Easy integration into Node-Red & Telegram (via MQTT)
- Geo-fencing feature to create custom locations
- Supports multiple vehicles per Tesla Account
- Charge cost tracking
- Import from TeslaFi and tesla-apiscraper

## Screenshots

![Web Interface](/website/static/screenshots/web_interface.png)

![Drive Details](/website/static/screenshots/drive.png)

![Battery Health](/website/static/screenshots/battery-health.png)

### [More Screenshots](https://docs.teslamate.org/docs/screenshots)

## Credits

- Initial Author: Adrian Kumpf
- List of Contributors:
- [![TeslaMate Contributors](https://contrib.rocks/image?repo=teslamate-org/teslamate)](https://github.com/teslamate-org/teslamate/graphs/contributors)
- Distributed under MIT License
