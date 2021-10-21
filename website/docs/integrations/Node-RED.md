---
title: Node-RED Integration
sidebar_label: Node-RED
---
# Overview
From the Node-RED website:
> Node-RED is a programming tool for wiring together hardware devices, APIs and online services in new and interesting ways.

> It provides a browser-based editor that makes it easy to wire together flows using the wide range of nodes in the palette that can be deployed to its runtime in a single-click.

The high-level logic "flow" is coded by wiring "nodes" in the user interface. Low-level logic can be coded in JavaScript. Visit the [Node-RED website](https://nodered.org) for a good introduction on its homepage.

This integration guide assumes that Teslamate is deployed on docker and that Node-RED is not exposed to the internet. Configuration of the Telegram bot is not covered in this guide; there is plenty of documetnation on the net explaining how to do this. However, the configuration of the Telgram node in Node-RED is described below.

Included are Node-RED flows with two examples:
- A simple dashboard with Car Status and Charge Status panels
- Notification logic for state changes, entering/exiting geofences and time remaining to charge. The example sends notifications to Telegram, but this can easily be replaced with a node sending the text elsewhere.

|<b>Node-RED Dashboard</b>|
|:--:|
|![Node-RED Dashboard example](./Node-RED-dashboard.PNG)|


|<b>Example Telegram Notifications</b>|
|:--:|
|![Node-RED Dashboard example](./Node-RED-Telegram.PNG)|
# Requirements

- Teslmate, preferably installed in Docker (if you are new to Docker, see Installing Docker and Docker Compose)
- External internet access, to send Telegram messages
- A mobile with [Telegram](https://telegram.org/) client installed or you can use Telegram's browser interface
- your own Telegram Bot, see [Creating a new telegram bot](https://core.telegram.org/bots#6-botfather)
- your own Telegram chat id, see get your telegram chat id

# Docker Entries
Add the following parameters to your `docker-compose.yml` file. It's assumed that your timezone in set in the .env file's TM_TZ environment variable.
```
services:
  node-red:
    image: nodered/node-red:latest
    restart: always
    environment:
      - TZ=${TM_TZ}
    volumes:
      - node-red-data:/data
    ports:
      - "1880:1880"
      
volumes:
  node-red-data:
```
# Node-RED Configuration
There are two flows in the example exports provided. The first flow creates a simple dashboard with some of the MQTT values. The second flow sends notifications to Telegram. 
The flow names are "Car Dashboard" and "Notifications".
## Required Modules
After bringing up the Node-RED container the first time, run the following shell script to add modules required for the example flows:
```
:
MODULES="node-red-contrib-calc
node-red-contrib-simpletime
node-red-dashboard
node-red-node-email
node-red-contrib-telegrambot
node-red-node-ui-table"
for MODULE in $MODULES
do
echo docker-compose exec -T node-red npm install --no-audit --no-update-notifier --no-fund --save --save-prefix=~ --production $MODULE
docker-compose exec -T node-red npm install --no-audit --no-update-notifier --no-fund --save --save-prefix=~ --production $MODULE
done
docker-compose stop node-red
docker-compose start node-red
```
## MQTT
If you are using the standard MQTT docker configuration, then after you import the flows Node-RED should automatically connect. Otherwise, open the ????node, select the ???? icon in the panel, edit the MQTT server's parameters, save and Deploy. 
## Telegram
TBC

Download the Node-RED flows export here to import into your instance: 

