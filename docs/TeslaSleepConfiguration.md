# Tesla Sleep Configuration

## Introduction

Tesla vehicles have a sleep mode which allows the vehicle to conserve battery power when not actively operating. After a period of inactivity, the vehicle will power down systems which are not necessary during times of inactivity. During these periods, your vehicle will only awaken if:

  * You approach the vehicle within range using the Android or iPhone application over bluetooth.

One challenge of Tesla API-based Data Loggers is that the continual polling of vehicles via the API results in the vehicle waking up or failing to go into sleep mode. To avoid these scenarios, TeslaMate uses two configuration parameters to define when a vehicle will start to sleep due to inactivity.

## Time to Try Sleeping

Following activity such as driving or charging, TeslaMate will continue to actively poll a vehicle for a configurable amount of time (by default **15 Minutes**) in order to detect whether the vehicle will continue to be in active use (for example, whether the vehicle has stopped temporarily to pick up a passenger or to visit a shop) or whether it will return to idle state.

  * If this value is set too low, the car may attempt to sleep prior to actually being idle. In this case, you may miss subsequent parts of a trip, for example if you had stopped for 20 minutes to pick up some items but the idle time was set to 15 minutes, the car would attempt to sleep.
  * If this value is set too high, the time after a drive during which the car is continually actively polled and is unable to go to sleep will be longer than necessary, consuming a greater amount of battery power.

## Attempt to Sleep

Once the Time to Try Sleeping idle timer is reached, TeslaMate will try to allow the car to go to sleep. It does this by halting all polling for the configured time period, which is **21 Minutes** by default. 

  * You will know that the vehicle is in this state when the status in TeslaMate is *falling asleep for x minutes*.
  * At the end of this polling window, TeslaMate will poll the vehicle status. If the vehicle status is offline, this indicates that the sleep process succeeded and the car is no longer directly queryable.
  * Polling will continue once per configured interval (*by default, 21 minutes*), meaning TeslaMate's resolution of polling interval for vehicles which have gone into sleep mode is 21 minutes - unless otherwise notified, TeslaMate will not know that the vehicle is awake for a total of 21 minutes (*by default*).
     * If you were to drive a vehicle that has just woken from Sleep Mode immediately after the last poll of the Attempt to Sleep interval timer, TeslaMate would miss 21 minutes (*by default*) of the drive session.
     
## Providing wake-up hints to TeslaMate

To address this delay, interfaces are available to TeslaMate to instruct it to expect:

  * The vehicle to go to sleep, *or*
  * The vehicle to wake up

### Bluetooth Hints

The concept behind providing bluetooth hints to TeslaMate is that when the Bluetooth key component of the Tesla app on Android or iPhone connects to the Tesla vehicle, it causes the vehicle to wake up. We have no way of detecting that this has happened from the TeslaMate side, and will continue to wait until the next polling interval (*21 Minutes by default*) in order to learn that the vehicle has awoken.

Using Bluetooth hints, a tool like tasker on the phone can then detect the Bluetooth connection between the app and the vehicle, and send a hint to TeslaMate to anticipate that the vehicle will wake up, and to resume high-frequency polling. The following sections of the document deal with different phone platforms and how to set up bluetooth hints for those platforms.

#### Notes

  * If you are specifying the local (LAN) IP address/port of your TeslaMate instance when performing the wake up, this may fail for a number of reasons:
     * It will not provide hints to TeslaMate when you are outside of your home network (ie if you have been driving).
     * It will not provide hints to TeslaMate if the mobile phone becomes disconnected from the wifi network.
  * For these reasons, it is necessary to use a method that allows external communication between your smartphone and your TeslaMate instance(s). This is described in each of the guides below with some options that can be used to achieve this.

#### Android

There are a number of applicatons that provide this functionality on Android:

| Application | Price           | Guide(s) |
| ----------- | --------------- |----------|
| [Automagic](https://play.google.com/store/apps/details?id=ch.gridvision.ppam.androidautomagic)   | US$3.50 | N/A |
| [MacroDroid](https://play.google.com/store/apps/details?id=com.arlosoft.macrodroid)  | Free (Limited)  | [MacroDroidSetup](MacroDroidSetup.md) |
| [Tasker](https://play.google.com/store/apps/details?id=net.dinglisch.android.taskerm) | US$3.00         | [TaskerSetup](TaskerSetup.md) |

#### iPhone

On the iOS platform, Apple provides the Shortcuts workflow tool:

| Application                                                        | Price   | Guide(s) |
| ------------------------------------------------------------------ | ------- | -------- |
| [Shortcuts](https://apps.apple.com/us/app/shortcuts/id915249334)   | Free    | Coming Soon |

### Event-Based Hints

In addition to Bluetooth hints, which would address most use cases, it is also possible to institute event-based hints. An example of an event-based hint is to trigger a callback to TeslaMate when my Garage Door is opened via HomeAssistant. The relevant configuration for this is:

  * automations.yaml
```
- alias: Wake Teslamate on Garage Open
  initial_state: on
  trigger:
    - platform: state
      entity_id: switch.garage_door_switch
      to: 'off'
  action:
    - service: script.turn_on
      entity_id: script.wake_teslamate
```

  * script.yaml
```
wake_teslamate:
  sequence:
    - service: shell_command.wake_teslamate

sleep_teslamate:
  sequence:
    - service: shell_command.sleep_teslamate
```

  * shell_command.yaml

_Note: Substitute your IP address for the commands_
```
  sleep_teslamate: curl -X PUT http://192.168.1.1:4000/api/car/1/logging/suspend
  wake_teslamate: curl -X PUT http://192.168.1.1:4000/api/car/1/logging/resume
```

### Time of Day Hints

_Are these available? I think this would be a good addition to TeslaMate, if not_

## Vehicle-Side Configuration

There are some parameters which are tunable on some Tesla vehicles. Keep in mind that as these differ between models and MCU versions, they may not be available on your vehicle. These are:

### Always Connected

   * Always Connected is a setting available only on Model S and Model X vehicles with the MCU1 hardware.
   * It is available under Settings > Controls > Displays > Power Management
   
## Tested Configurations

| *Tested By* | *Vehicle Model + Year* | *Software Version* | *Attempt to Sleep value* | *Outcome*                    |
| ----------- | ---------------------- | ------------------ | ------------------------ | ---------------------------- |
| @ngardiner  | Model 3 MY 2019 (MCU2) | 2019.32.11.1       | 15 Minutes               | Vehicle sleeps without issue |
| @ngardiner  | Model 3 MY 2019 (MCU2) | 2019.32.11.1       | 12 Minutes               | Currently testing this setting |
