# MacroDroid Setup (Android)

MacroDroid is an Android application with similar features to Tasker, but with a free version that provides:

- Up to 5 macros in total (_we will use up to 2 for TeslaMate_).
- Ads within the User Interface.

## Creating a Macro

Launch MacroDroid. The first screen that you will see has a number of tiles. In order to set up a macro to send resume hints to TeslaMate, click on the **Add Macro** button to the right of the screen.

You will be prompted for a Macro Name and Category. Provide the following Details:

- **Category**: Uncategorized
- **Name**: TeslaMateResume

![](../../images/macrodroid-connect-select.png)
![](../../images/macrodroid-device-connected.png)

### Defining a Trigger

In MacroDroid, a trigger is the event that causes a task to execute. We will define a trigger that is activated each time a Bluetooth connection is established between a smartphone and a Tesla vehicle device over Bluetooth.

- A list of trigger options will appear. Click on the **Connectivity** section to expand this section.
- From the list of options provided, select **Bluetooth Event**.
- A number of Bluetooth Connection Events will appear. Select **Device Connected**.
- You should see the **Device Connected** screen appear, with a list of your paired Bluetooth devices. Select your Tesla vehicle from the list.

### Constraints

We will not configure any constraints for the Macro we have created. When the Constraints screen appears, with **(No Constraints)** being the default setting, simply click the checkmark in the bottom-right hand corner of the screen to finish setting up your macro.

### Defining the Action

In case you have made your installation reachable publicly (which makes sense) and have secured it using e.g. a proxy with http basic auth (which you absolutely should, e.g. Docker Traefik works well for that) you need a REST API tool to send the required PUT request to teslamate. RESTask works well for that. Grab it from the Play Store, install it and then head back to Macrodroid. When selecting an Action, choose Locale/Tasker plugin and select RESTask. Here you simply provide the URL to your API installation: `https://yourinstallation.bla.blubb.com/api/car/1/logging/resume` Replace the number if you have multiple cars and you wish to select the right one. Request type is PUT, enter Basic Auth credentials and you are done. Maybe consider raising the timeout a bit if you start your drives in an underground parking garage or areas with poorer cell coverage.

With all that done you can push the play button at the top to test. In the log of Teslamate you should see a 'increasing log frequency' message and RESTask should show a 204 return code. If so, everything is well. If not, check your settings and the logs of your proxy.

Macrodoid can have multiple triggers for the same action. In addition to Bluetooth you may also select 'opening the Tesla app' as another trigger. So when you pre-heat or pre-cool the logging will start as well so you can collect consumption for that as well.
