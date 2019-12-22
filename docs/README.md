# TeslaMate Documentation

## Installation

- [Docker](installation/docker.md) (simplified, recommended)
- [Docker (advanced)](installation/docker_advanced.md) (Reverse Proxy, Let's Encrypt Certificate, HTTP Basic Auth)
- [Debian/Ubuntu](installation/debian.md) (without Docker)
- [Kubernetes](https://hub.helm.sh/charts/billimek/teslamate) (opinionated helm chart installed with a standalone postgresql database)

## Upgrading to a new version

- [Docker Setup](upgrading.md#docker)

## Configuration

- [Environment Variables](configuration/environment_variables.md) – Documents the available runtime configuration parameters.
- [Sleep Mode Configuration](configuration/sleep.md) – Documents the sleep behaviour for Tesla vehicles and the related TeslaMate configuration
  - [Shortcuts Setup](configuration/guides/shortcuts.md)
  - [Tasker Setup](configuration/guides/tasker.md)
  - [MacroDroid Setup](configuration/guides/macro_droid.md)

## Integrations

- [HomeAssistant](integrations/home_assistant.md)
- [MQTT](integrations/mqtt.md)

## [Frequently Asked Questions](faq.md)

- [Why are no consumption values displayed in Grafana?](faq.md#why-are-no-consumption-values-displayed-in-grafana)
- [What is the geo-fence feature for?](faq.md#what-is-the-geo-fence-feature-for)

## [Development](development.md)

- [Requirements](development.md#requirements)
- [Testing](development.md#testing)
