# TeslaMate

[![CI](https://github.com/adriankumpf/teslamate/workflows/CI/badge.svg?branch=master)](https://github.com/adriankumpf/teslamate/actions?query=workflow%3ACI)
[![](https://coveralls.io/repos/github/adriankumpf/teslamate/badge.svg?branch=master)](https://coveralls.io/github/adriankumpf/teslamate?branch=master)
[![](https://img.shields.io/docker/v/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![](https://img.shields.io/docker/image-size/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![](https://img.shields.io/docker/pulls/teslamate/teslamate?color=%23099cec)](https://hub.docker.com/r/teslamate/teslamate)
[![](https://img.shields.io/badge/Donate-PayPal-ff69b4.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=YE4CPXRAV9CVL&source=url)

A powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir](https://elixir-lang.org/)**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

## Documentation

The documentation is available at [docs.teslamate.org](https://docs.teslamate.org/).

## Features

**Dashboards**

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
- Lifetime driving map
- Visited addresses

**General**

- High precision drive data recording
- No additional vampire drain: the car will fall asleep as soon as possible
- Automatic address lookup
- Easy integration into Home Assistant (via MQTT)
- Geo-fencing feature to create custom locations
- Supports multiple vehicles per Tesla Account
- Charge cost tracking
- Import from TeslaFi and tesla-apiscraper

## Screenshots

![Drive Details](/website/static/screenshots/drive.png)
![Web Interface](/website/static/screenshots/web_interface.png)

<p align="center">
  <strong><a href="https://docs.teslamate.org/docs/screenshots">MORE SCREENSHOTS</a></strong>
</p>

## Credits

- Authors: Adrian Kumpf – [List of contributors](https://github.com/adriankumpf/teslamate/graphs/contributors)
- Distributed under MIT License
