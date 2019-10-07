# TeslaMate Documentation

## Introduction

TeslaMate is a powerful data logger for your Tesla.

## Installation

  * [Installation on DigitalOcean](InstallationOnDigitalOcean.md) droplet
  * [Installation on Docker](InstallationOnDocker.md) (simplified, recommended)
  * Manual/Advanced Installation
     * [Debian/Ubuntu TeslaMate Installation](InstallationOnDebian.md)
     
## Configuration

  * [Multi-Tenancy for TeslaMate](MultiTenancyConfigurations.md)
  * [Tesla Sleep Configuration](TeslaSleepConfiguration.md) - Documents the deep sleep behaviour for Tesla vehicles and the related TeslaMate configuration
     * This topic also contains information on how to set up resume hints on iOS or Android (using [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=en) or [Shortcuts](https://support.apple.com/guide/shortcuts/welcome/ios)).
     
## Integration

  * [HomeAssistant](HomeAssistantIntegration.md) Integration 
  * [MQTT Broker](MQTTBrokerIntegration.md) Integration
  
## Frequently Asked Questions

### Sometimes the first few minutes of a drive are not recorded even though the car was online. Why?

TeslaMate polls the car every few seconds while driving or charging. After
that, it keeps polling for about 15 minutes (to catch the following drive if
you stopped for a drink, for example). After this period, TeslaMate will stop
polling the car for about 21 minutes to let it go to sleep. This is repeated
until the car is asleep or starts to drive/charge again. Once sleeping,
TeslaMate will never wake the wake the car. It is only checked twice a minute to
see if it is still sleeping.

This approach may sometimes lead to _small_ data gaps: if the car starts
driving during the 21 minute period where TeslaMate is not polling, nothing can
be logged.

##### Solution

To get around this you can use your smartphone to inform TeslaMate when to
start polling again. In short, create a workflow with
[Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm&hl=en)
(Android) or [Shortcuts](https://support.apple.com/guide/shortcuts/welcome/ios)
(iOS) that listens for connected Bluetooth devices. If a connection to your
Tesla is established send an HTTP PUT `resume` request to your publicly exposed
TeslaMate instance. See the available commands below.

**Alternatively** / additionally, you can experiment with the sleep settings.
Some cars, especially Model 3, seem to handle a `Time to Try Sleeping` value of
12 min just fine. Doing so reduces the likelihood of potential data gaps. Just
keep an eye on your car afterwards to see if it still goes into sleep mode.

##### Available Commands

```
PUT https://teslamate.your-domain.com/api/car/$car_id/logging/resume
PUT https://teslamate.your-domain.com/api/car/$car_id/logging/suspend
```

⚠️ I strongly recommend to use a reverse-proxy with HTTPS and basic access
authentication when exposing TeslaMate to the public internet. Additionally
only permit access to `/api/car/$car_id/logging/resume` and/or
`/api/car/$car_id/logging/suspend`. See [Advanved Setup (SSL, FQDN, pw
protected)](<https://github.com/adriankumpf/teslamate/wiki/Advanved-Setup-(SSL,-FQDN,-pw-protected)>).

### Why is my car not sleeping?

Please follow the steps applicable to TeslaMate mentioned in [this article](https://support.teslafi.com/knowledge-bases/2/articles/161-my-vehicle-is-not-sleeping).

Most importantly, if you have a Model S or X built prior to March 2018 make sure 'Always Connected' is turned off and 'Energy Savings' is turned on in the vehicle.
