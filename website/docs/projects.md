---
title: Projects using TeslaMate
---

Here are some projects that use **TeslaMate** as a data source to enrich its functionality and that can be useful depending on your setup.

## [TeslaMate ABRP](https://fetzu.github.io/teslamate-abrp/)

A python script (also available as a lightweight docker image) that pushes car status data to [ABetterRoutePlanner](https://abetterrouteplanner.com) based on contents of TeslaMate MQTT's topic.

LINK: [github.com/fetzu/teslamate-abrp](https://github.com/fetzu/teslamate-abrp)

## [TeslaMateAgile](https://github.com/MattJeanes/TeslaMateAgile)

A TeslaMate integration for calculating cost of charges. This application will automatically update your cost for charge sessions in TeslaMate within a specified geofence (usually home) using data from your smart electricity tariff.

The supported energy providers / tarriffs are either [Octopus Agile](https://octopus.energy/agile/), [Tibber](https://tibber.com/en/), [aWATTar](https://www.awattar.de/) or fixed pricing (manually specified).

LINK: [github.com/MattJeanes/TeslaMateAgile](https://github.com/MattJeanes/TeslaMateAgile)

## [TeslaMateApi](https://github.com/tobiasehlert/teslamateapi)

TeslaMateApi is a RESTful API to get data collected by self-hosted data logger TeslaMate in JSON.

The application is written in Golang and data is received from both PostgreSQL and Mosquitto and presented in various endpoints.

LINK: [github.com/tobiasehlert/TeslaMateApi](https://github.com/tobiasehlert/teslamateapi)

## [TeslaMate Custom Dashboards](https://github.com/jheredianet/Teslamate-CustomGrafanaDashboards)

Teslamate Custom Grafana Dashboards, including: Amortization Tracker, Battery Health, Browse Charges, Charging Costs Stats, Charging CurveStats, Continuous Trips, Current State, Database Information, DC Charging Curves By Carrier, Incomplete Data, Range Degradation, Mileage Stats, Speed Rates, Speed & Temperature, Tracking Drives and more.
Also, there are two dashboards (Current Charge & Drive View) that could be browsed on the car while driving or charging.

LINK: [github.com/jheredianet/Teslamate-CustomGrafanaDashboards](https://github.com/jheredianet/Teslamate-CustomGrafanaDashboards)

## [TeslaMate Guru on Gurubase](https://gurubase.io/g/teslamate)

TeslaMate Guru is a TeslaMate-focused AI to answer your questions. It primarily uses the TeslaMate documentation and the TeslaMate GitHub repository to generate responses.

LINK: [https://gurubase.io/g/teslamate](https://gurubase.io/g/teslamate)

## [Tesla Home Assistant Integration](https://github.com/alandtse/tesla)

The Tesla Home Assistant integration can use the data from the TeslaMate MQTT integration to update car data in near-real time.

LINK: [github.com/alandtse/tesla](https://github.com/alandtse/tesla)

LINK: [Wiki How-To](https://github.com/alandtse/tesla/wiki/Teslamate-MQTT-Integration)

## [TeslaMate Telegram Bot](https://github.com/JakobLichterfeld/TeslaMate-Telegram-Bot)

This is a telegram bot written in Python to notify by Telegram message when a new SW update for your Tesla is available. It uses the MQTT topic which TeslaMate offers.

LINK: [github.com/JakobLichterfeld/TeslaMate-Telegram-Bot](https://github.com/JakobLichterfeld/TeslaMate-Telegram-Bot)

## [CustomGrafanaDashboards](https://github.com/CarlosCuezva/dashboards-Grafana-Teslamate)

Collection of custom dashboards for Grafana.

LINK: [github.com/CarlosCuezva/dashboards-Grafana-Teslamate](https://github.com/CarlosCuezva/dashboards-Grafana-Teslamate)

## [Gaussmeter](https://github.com/gaussmeter/gaussmeter)

An LED illuminated acrylic Tesla Model 3. Its color and scale of light depend on the cars current state.

LINK: [github.com/gaussmeter/gaussmeter](https://github.com/gaussmeter/gaussmeter)

## [Home Assistant Addon](https://github.com/lildude/ha-addon-teslamate)

An unofficial Home Assistant addon for TeslaMate, with a PostgreSQL addon too. Works with the existing community Grafana and Mosquitto addons to provide a complete solution.

LINK: [github.com/lildude/ha-addon-teslamate](https://github.com/lildude/ha-addon-teslamate)

## [MMM-Teslamate](https://github.com/denverquane/MMM-Teslamate)

A [Magic Mirror](https://magicmirror.builders/) Module for TeslaMate.

LINK: [github.com/denverquane/MMM-Teslamate](https://github.com/denverquane/MMM-Teslamate)

## [MyTeslaMate](https://www.myteslamate.com)

For those who do not wish to install their own instance, MyTeslaMate provides a managed instance of TeslaMate ready to use in one minute, with a security overlay (Authelia), 30-day backups, and the possibility of importing a backup to migrate easily.

For all [TeslaMate](https://www.myteslamate.com) users, MyTeslaMate also provides for free a [Fleet API](https://app.myteslamate.com/fleet) endpoint and a streaming server based on Tesla Telemetry events.

LINK: [MyTeslaMate Website](https://www.myteslamate.com)

LINK: [Follow this guide](/docs/guides/api#myteslamate-fleet-api) to use official Tesla APIs on your Teslamate.

## [Tesla-GeoGDO](https://github.com/brchri/tesla-geogdo) (previously [Tesla-YouQ](https://github.com/brchri/tesla-youq))

A lightweight app that will operate your smart garage door openers based on the location of your Tesla vehicles, automatically closing when you leave, and opening when you return. Supports multiple geofence types including circular, TeslaMate, and polygonal. Supports multiple vehicles and various smart garage door openers.

LINK: [https://github.com/brchri/tesla-geogdo](https://github.com/brchri/tesla-geogdo)
