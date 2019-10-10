# iOS Shortcuts Setup

*Note: This guide is currently a work in progress. Check back soon for a complete walkthrough!*

## Introduction

<img src="../images/shortcuts/icon.png" />

Shortcuts is an iOS application ("internal" since 13.1) with similar features to Tasker or MacroDroid on Android. It's meant to create shortcuts (sequence of actions triggered by click) or automations (sequence of actions triggered by event - i.e. Bluetooth device connected). 

Unfortunately, only couple of the useful events (like NFC on NFC enabled phones) can be really automated (no user interaction), most of them require confirming the action. See [Shortcuts documentation](https://support.apple.com/guide/shortcuts/enable-or-disable-a-personal-automation-apd602971e63/ios) (section: Enable an automation to run without asking) for more details.

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

<img src="../images/shortcuts/create_00_home.png" /> <img src="../images/shortcuts/create_01_aut_home.png" /> <img src="../images/shortcuts/create_02_new_automation_type.png" />
<img src="../images/shortcuts/create_03_triggering_event.png" /> <img src="../images/shortcuts/create_04_bluetooth.png" /> <img src="../images/shortcuts/create_05_bluetooth_device.png" /> 
<img src="../images/shortcuts/create_06_bluetooth_selected.png" />


### Building an action

 * Click **Add Action** button. This brings you to the list of available actions.
 * Select **Documents** (yellow icon), go to **Text** block and select **Text**.
 * It brings you to text editor. Type in your login and password separated by colon. For the assumption above, it will be "**mylogin:mysecretpassword**" (without the quotes).
 
   <img src="../images/shortcuts/create_07_add_action.png" />    <img src="../images/shortcuts/create_08_action_categories.png" />    <img src="../images/shortcuts/create_09_docs_text.png" />
<img src="../images/shortcuts/create_10_text_edit.png" />

 * Click **+** icon below the actions. This brings you to the list of available actions.
 * You will be back in Documents. **DO NOT** (I know, it's tempting) press Back, you'd lose the previously entered actions in such case. Instead, scroll up and click the gray **X** next to Documents. This will bring you to the categories of action.
 * Select **Scripting** (gray icon), go to **Files** block and select **Base64 Encode**.

<img src="../images/shortcuts/create_11_text_edit_filled.png" /> <img src="../images/shortcuts/create_12_documents_close.png" /> <img src="../images/shortcuts/create_13_action_categories.png" />
<img src="../images/shortcuts/create_14_scripting_enc.png" />

 * Click **+** icon below the actions. This brings you to the list of available actions.
 * Click the gray **X** to close Scripting category.
 * Select **Web** (cyan icon), go to **URLs** block and select **URL**.
 * It brings you to text editor. Type in your endpoint public URL. For the assumption above, it will be "**https://mytm.myweb.com/wake**" (without the quotes).
 
<img src="../images/shortcuts/create_15_enc_added.png" /> <img src="../images/shortcuts/create_16_scripting_close.png" /> <img src="../images/shortcuts/create_17_action_categories.png" />
<img src="../images/shortcuts/create_17_url.png" /> 
 
 * Click **+** icon below the actions. This brings you to the list of available actions.
 * Stay in **Web** (cyan icon) again, go to **Web Requests** block and select **Get Contents of URL**.
 * In the newly added action, click **Show more**
 * Change **Method** to **PUT**.
 * Click **Headers**
 
<img src="../images/shortcuts/create_18_url_edit.png" /> <img src="../images/shortcuts/create_19_url_contents.png" /> <img src="../images/shortcuts/create_20_url_contents_added.png" />
<img src="../images/shortcuts/create_21_show_more.png" /> <img src="../images/shortcuts/create_22_method.png" />
 
 * In **Headers** section, click on **Add new header** (green + icon).
 * Type **Authorization** in **Key** box and **"Basic "** (without the quotes, note the **space** after **Basic**) into the **Value** box.
 * While still in **Value** box, click **Base64 Encoded** on **Variables** panel (bottom of the screen). It will be added to **Value**.

<img src="../images/shortcuts/create_23_headers.png" /> <img src="../images/shortcuts/create_24_headers_add.png" /> <img src="../images/shortcuts/create_25_headers_values.png" />
<img src="../images/shortcuts/create_26_headers_values_var.png" />

### Saving an Automation

 * Click **Next** (upper right corner), it will bring you to the summary page.
 * Click **Done** (upper right corner), it will bring you to the main screen (list of automations).
 * You have your new automation ready.

<img src="../images/shortcuts/create_27_contents_filled.png" /> <img src="../images/shortcuts/create_28_automation_detail.png" /> <img src="../images/shortcuts/create_29_automation_list.png" />

## Enabling / Disabling / Editing the Automation
 * Click the automation
 * Turn on/off the **Enable this automation**.
 * If you need to edit something, click thru to the appropriate part of the automation.
 * Save by clicking **Done**.

<img src="../images/shortcuts/edit_01_automation_detail.png" /> <img src="../images/shortcuts/edit_02_edit_actions.png" />

## Running the Automation

 * Get into the car and wake it up by pressing the brake pedal (if needed).
 * Once the Bluetooth connects, you will see notification on your lock screen.   
 * Click **Run** button.
 * Done. 
 
<img src="../images/shortcuts/run_01_run.png" /> <img src="../images/shortcuts/run_00_notification.png" />
   
 
