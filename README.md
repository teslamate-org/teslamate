# TeslaMate

[![License](https://img.shields.io/badge/license-AGPL--3.0--or--later-green.svg)](https://github.com/teslamate-org/teslamate/blob/main/NOTICE)
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

> [!CAUTION]
> **Use Official Versions Only**

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
- Web interface in 19 languages (Catalan, Danish, Dutch, English, Finnish, French, German, Hungarian, Italian, Japanese, Korean, Norwegian Bokmål, Simplified Chinese, Spanish, Swedish, Thai, Traditional Chinese, Turkish, Ukrainian); untranslated text falls back to English

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

![Statistics](/website/static/screenshots/statistics.png)

![Battery Health](/website/static/screenshots/battery-health.png)

## License

TeslaMate is licensed under the **GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**. See [NOTICE](https://github.com/teslamate-org/teslamate/blob/main/NOTICE) for the copyright notice, the additional terms under section 7 of the AGPL, and the trademark notice. For the full legal terms, please refer to the [LICENSE](https://github.com/teslamate-org/teslamate/blob/main/LICENSE) file.

This license is designed to ensure that TeslaMate remains free and open for everyone and that improvements made by commercial entities or third parties remain open to the entire community. By using, modifying, or building upon this project, you agree to the following:

- Copyleft: If you modify TeslaMate or incorporate it into another project, you must release the entire source code of your version under the same license (AGPL-3.0-or-later). This applies regardless of how you provide the software to others, in any form, including, without limitation, as a downloadable application, a binary, a package, a pre-packaged image, or a network service (SaaS).
- No Closed-Source Derivatives: We do not permit the use of TeslaMate or its components in closed-source products. Any software made to work with TeslaMate, including, without limitation, apps, dashboards, integrations, and services, must be open-source under an AGPL-compatible license. Software that integrates with TeslaMate may do so only via the supported integration surface (MQTT). If you build upon this project, you are expected to contribute back to the community.
- Attribution: You must keep all original copyright notices, the NOTICE file, and license information intact, and clearly mark modified versions as modified.

**Trademark Policy**: The use of all trademarks of the TeslaMate project is governed by our [Trademark Policy](https://github.com/teslamate-org/teslamate/blob/main/TRADEMARK.md).

**Disclaimer:** TeslaMate is an independent project and is not affiliated with, endorsed by, or sponsored by Tesla, Inc. "Tesla" and related marks are trademarks of Tesla, Inc.

**Contributions:** All contributors must sign our [Fiduciary License Agreement (FLA 2.0)](https://github.com/teslamate-org/legal/blob/main/CLA.md). This is handled via cla-assistant.io automatically on first PR and does not take long. **Why do we need this?** It guarantees that TeslaMate will **always remain Free Software** and allows the [teslamate-org](https://github.com/teslamate-org) to legally defend the project against license violations.

## Popularity

[![teslamate-org/teslamate on Trendshift](https://trendshift.io/api/badge/repositories/24134)](https://trendshift.io/repositories/24134?utm_source=repository-badge&utm_medium=badge&utm_campaign=badge-repository-24134)

<!-- markdownlint-disable MD033 -->
<a href="https://www.star-history.com/?repos=teslamate-org%2Fteslamate&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=teslamate-org/teslamate&type=date&theme=dark&legend=top-left&sealed_token=fwiuAlNEUj8eYQn1rfDBWuO1X-8D__oKgCwEMpguLFI2sKX84ySGDr-ZyaTvrmyCVFq6FMq3S9tbx08hNAB0n7zSsvxhhy12ywx2HW3RImbgY6xKsBIcDS0TeHVg9eReGL2CPHWQkQ8DWva51A5f-SCzPaoknJ3R82Vvm813x8wPAQIeuTurVEG5VnSw" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=teslamate-org/teslamate&type=date&legend=top-left&sealed_token=fwiuAlNEUj8eYQn1rfDBWuO1X-8D__oKgCwEMpguLFI2sKX84ySGDr-ZyaTvrmyCVFq6FMq3S9tbx08hNAB0n7zSsvxhhy12ywx2HW3RImbgY6xKsBIcDS0TeHVg9eReGL2CPHWQkQ8DWva51A5f-SCzPaoknJ3R82Vvm813x8wPAQIeuTurVEG5VnSw" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=teslamate-org/teslamate&type=date&legend=top-left&sealed_token=fwiuAlNEUj8eYQn1rfDBWuO1X-8D__oKgCwEMpguLFI2sKX84ySGDr-ZyaTvrmyCVFq6FMq3S9tbx08hNAB0n7zSsvxhhy12ywx2HW3RImbgY6xKsBIcDS0TeHVg9eReGL2CPHWQkQ8DWva51A5f-SCzPaoknJ3R82Vvm813x8wPAQIeuTurVEG5VnSw" />
 </picture>
</a>
<!-- markdownlint-enable MD033 -->

## Credits

- Initial Author: Adrian Kumpf
- List of Contributors:
- [![TeslaMate Contributors](https://contrib.rocks/image?repo=teslamate-org/teslamate)](https://github.com/teslamate-org/teslamate/graphs/contributors)
