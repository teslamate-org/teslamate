# TeslaMate

[![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](https://github.com/teslamate-org/teslamate/blob/main/LICENSE)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/10859/badge)](https://www.bestpractices.dev/projects/10859)
[![CI](https://github.com/teslamate-org/teslamate/actions/workflows/devops.yml/badge.svg)](https://github.com/teslamate-org/teslamate/actions/workflows/devops.yml)
[![Publish Docker images](https://github.com/teslamate-org/teslamate/actions/workflows/buildx.yml/badge.svg)](https://github.com/teslamate-org/teslamate/actions/workflows/buildx.yml)
[![Coverage](https://coveralls.io/repos/github/teslamate-org/teslamate/badge.svg?branch=main)](https://coveralls.io/github/teslamate-org/teslamate?branch=main)
[![current version](https://img.shields.io/docker/v/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![docker image size](https://img.shields.io/docker/image-size/teslamate/teslamate/latest)](https://hub.docker.com/r/teslamate/teslamate)
[![docker pulls](https://img.shields.io/docker/pulls/teslamate/teslamate?color=%23099cec)](https://hub.docker.com/r/teslamate/teslamate)

A powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir](https://elixir-lang.org/)**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **[MQTT](https://en.wikipedia.org/wiki/MQTT)** Broker

## ⚠️ Security Warning

[!CAUTION]
**Use Official Versions Only**

To protect yourself from malicious forks, malware, and data theft, please ensure you only obtain TeslaMate from the official source:

- Official Repository: [https://github.com/teslamate-org/teslamate](https://github.com/teslamate-org/teslamate)
- Official Documentation: [https://docs.teslamate.org](https://docs.teslamate.org/)

We have received reports of deceptive websites and unofficial mobile apps (e.g. on the App Store) using the TeslaMate name to distribute modified or harmful versions. If you are using a version from another source, your Tesla account credentials and vehicle data may be at risk.

## Documentation

The documentation is available at [https://docs.teslamate.org](https://docs.teslamate.org/)

## Features

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
- Customizable theme mode (light, dark, or system default)

### Dashboards

Sample screenshots of bundled dashboards can be seen by clicking the links below.

- [Battery Health](https://docs.teslamate.org/docs/screenshots/#battery-health)
- [Charge Level](https://docs.teslamate.org/docs/screenshots/#charge-level)
- [Charges (Energy added / used)](https://docs.teslamate.org/docs/screenshots#charges)
- [Charge Details](https://docs.teslamate.org/docs/screenshots#charge-details)
- [Charging Stats](https://docs.teslamate.org/docs/screenshots#charging-stats)
- [Database Information](https://docs.teslamate.org/docs/screenshots/#database-information)
- [Drive Stats](https://docs.teslamate.org/docs/screenshots#drive-stats)
- [Drives (Distance / Energy consumed (net))](https://docs.teslamate.org/docs/screenshots/#drives)
- [Drive Details](https://docs.teslamate.org/docs/screenshots/#drive-details)
- [Efficiency (Consumption (net / gross))](https://docs.teslamate.org/docs/screenshots#efficiency)
- [Locations (addresses)](https://docs.teslamate.org/docs/screenshots/#location-addresses)
- [Mileage](https://docs.teslamate.org/docs/screenshots/#mileage)
- [Overview](https://docs.teslamate.org/docs/screenshots/#overview)
- [Projected Range (battery degradation)](https://docs.teslamate.org/docs/screenshots#projected-range)
- [States (see when your car was online or asleep)](https://docs.teslamate.org/docs/screenshots#states)
- [Statistics](https://docs.teslamate.org/docs/screenshots/#statistics)
- [Timeline](https://docs.teslamate.org/docs/screenshots/#timeline)
- [Trip](https://docs.teslamate.org/docs/screenshots/#trip)
- [Updates (History of installed updates)](https://docs.teslamate.org/docs/screenshots#updates)
- [Vampire Drain](https://docs.teslamate.org/docs/screenshots#vampire-drain)
- [Visited (Lifetime driving map)](https://docs.teslamate.org/docs/screenshots/#visited-lifetime-driving-map)

## Screenshots

Sneak peak into TeslaMate interface and bundled dashboards. See [the docs](https://docs.teslamate.org/docs/screenshots) for additional screenshots.

![Web Interface](/website/static/screenshots/web_interface.png)

![Drive Details](/website/static/screenshots/drive.png)

![Battery Health](/website/static/screenshots/battery-health.png)

## License

TeslaMate is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**.

This license is designed to ensure that TeslaMate remains free and open for everyone. By using, modifying, or building upon this project, you agree to the following:

- Reciprocal Sharing (Copyleft): If you modify TeslaMate or incorporate it into another project, you must release the entire source code of your version under the same AGPLv3 license.
- Universal Access to Source: This requirement applies regardless of how you provide the software to others—whether you distribute it as a downloadable application (e.g., in an App Store), as a pre-packaged image, or provide access to its functionality via a network service (SaaS).
- No Closed-Source Derivatives: We do not permit the use of TeslaMate or its components in closed-source commercial products. If your software interacts with or relies on TeslaMate, it must be open-source. If you build upon this project, you are expected to contribute back to the community.

For the full legal terms, please refer to the [LICENSE](https://github.com/teslamate-org/teslamate/blob/main/LICENSE) file.

Key Requirements:

- Copyleft: If you modify TeslaMate and distribute it (e.g., as an app, binary, or package) or offer it as a service over a network (SaaS), you must make your modified source code available to all users under the same AGPLv3 license.
- No "Closed" Forks: This license ensures that improvements made by commercial entities or third parties remain open to the entire community.
- Attribution: You must keep all original copyright notices and license information intact.

**Trademark Policy**: The use of the TeslaMate name and logo is governed by our [Trademark Policy](https://github.com/teslamate-org/teslamate/blob/main/TRADEMARK.md).

**Contributions:** All contributors must sign our [Contributor License Agreement](https://github.com/teslamate-org/legal/blob/main/CLA.md). This is handled via cla-assistant.io automatically on first PR and does not take long. **Why do we need this?** It guarantees that TeslaMate will **always remain Free Software** (AGPL-3.0) and allows the [teslamate-org](https://github.com/teslamate-org) to legally defend the project against license violations.

## Star History

<!-- markdownlint-disable MD033 -->
<a href="https://www.star-history.com/#teslamate-org/teslamate&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=teslamate-org/teslamate&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=teslamate-org/teslamate&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=teslamate-org/teslamate&type=date&legend=top-left" />
 </picture>
</a>
<!-- markdownlint-enable MD033 -->

## Credits

- Initial Author: Adrian Kumpf
- List of Contributors:
- [![TeslaMate Contributors](https://contrib.rocks/image?repo=teslamate-org/teslamate)](https://github.com/teslamate-org/teslamate/graphs/contributors)
