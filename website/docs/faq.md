---
title: Frequently Asked Questions
sidebar_label: FAQ
---

## Why are no consumption values displayed in Grafana?

Unfortunately the Tesla API does not return consumption values for a trip. In order to still be able to display values TeslaMate estimates the consumption on the basis of the recorded (charging) data. It takes **at least two** charging sessions before the first estimate can be displayed. Each charging session will slightly improve the accuracy of the estimate, which is applied retroactively to all data.

## What is the geo-fence feature for?

At the moment geo-fences are a way to create custom locations like `🏡 Home` or `🛠️ Work` That may be particularly useful if the addresses (which are provided by [OpenStreetMap](https://www.openstreetmap.org)) in your region are inaccurate or if you street-park at locations where the exact address may vary.
