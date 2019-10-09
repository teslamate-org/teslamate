# iOS Shortcuts Setup

*Note: This guide is currently a work in progress. Check back soon for a complete walkthrough!*

## Introduction

Shortcuts is an iOS application ("internal" since 13.1) with similar features to Tasker or MacroDroid on Android. It's meant to create shortcuts (sequence of actions triggered by click) or automations (sequence of actions triggered by event - i.e. Bluetooth device connected). 

Unfortunately, only couple of the useful events (like NFC on NFC enabled phones) can be really automated (no user interaction), most of them require unlocking the phone and confirming the action. See [Shortcuts documentation](https://support.apple.com/guide/shortcuts/enable-or-disable-a-personal-automation-apd602971e63/ios) (section: Enable an automation to run without asking) for more details.

## Assumptions

These values are used on the screenshots. Whenever you see them, replace them with actual values used on your system.
 * You have wake up endpoint exposed as **https://mytm.myweb.com/wake** and proxied to sth like http://teslamate:4000/api/car/car_id/logging/resume where **car_id** is 1 if you have only one car.
 * Endpoint is protected by **Basic Authentication** with login **mylogin** and password **mysecretpassword**. Note this **IS NOT** your Tesla password.

## Setup the automation

**NOTE:** The UI looks (different button labels) and behaves (different page flow) slightly different way depending whether you are creating new automation or editing the existing one. Don't get scared.

### Creating a "Bluetooth device connected" Automation

 * Launch Shortcuts. 
 * Switch to Automation screen (center icon on bottom of the screen).
 * To create automation, click small blue **+** icon in upper right corner.
 * Select **Create Personal Automation** (upper blue option).
 * Scroll down to **Settings** block and select **Bluetooth**.
 * Click **Device**, select your Tesla (you need to have it paired already) and click **Done** (upper right corner).
 * Click **Next** (upper right corner). This brings you to the list of actions (empty for now).

### Building an action

 * Click **Add Action** button. This brings you to the list of available actions.
 * Select **Documents** (yellow icon), go to **Text** block and select **Text**.
 * It brings you to text editor. Type in your login and password separated by colon. For the assumption above, it will be "**mylogin:mysecretpassword**" (without the quotes).
 * Click **+** icon below the actions. This brings you to the list of available actions.
 
 You will be back in Documents. Do not press Back, you'd lose the previously entered actions in this case.
 Instead, scroll up and pres the gray X next to Documents. This will bring you to the categories of action.
 
 
 * Select **Scripting** (gray icon), go to **Files** block and select **Base64 Encode**.
 * Click  **Edit Automation** (upper left corner), it brings you back to the list of actions.
 * Click **+** icon below the actions. This brings you to the list of available actions.
 
 close Scripting
 
 * Select **Web** (cyan icon), go to **URLs** block and select **URL**.
 * It brings you to text editor. Type in your endpoint public URL. For the assumption above, it will be "**https://mytm.myweb.com/wake**" (without the quotes).
 * Click  **Edit Automation** (upper left corner), it brings you back to the list of actions.
 * Click **+** icon below the actions. This brings you to the list of available actions.
 * Select **Web** (cyan icon) again, go to **Web Requests** block and select **Get Contents of URL**.
 * In the newly added action, click **Show more**
 * Change **Method** to **PUT**.
 Click headers
 * In **Headers** section, click on **Add new header** (green + icon).
 * Type **Authorization** in **Key** box and **"Basic "** (without the quotes, note the **space** after **Basic**) into the **Value** box.
 * While still in **Value** box, click **Base64 Encoded** on **Variables** panel (bottom of the screen). It will be added to **Value**.

### Saving an Automation

 * Click *Next* (upper right corner), it will bring you to the summary page.
 * Click **Done** (upper right corner), it will bring you to the main screen (list of automations).

## Enabling / Disabling the Automation
 * Click the automation
 * Turn on/off the **Enable this automation**.
 * Save by clicking **Done**.
 
## Executing the Automation

 * Get into the car and wake it up by pressing the brake pedal (if needed).
 * Once the Bluetooth connects, you will see notification on your lock screen.
   <img src="../images/shortcuts/run_00_notification.png" />
 * Click **Run** button.
   <img src="../images/shortcuts/run_01_run.png" />
 * Done. 
