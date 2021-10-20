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


# Docker Entries
Add the following parameters to your `docker-compose.yml` file. It's assume that your timezone in set in the .env file's TM_TZ environment variable.
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
# Node-RED Flows
There are two flows in the example flow export. The first flow createsa a simple dashboard with some of the MQTT values. The second flow sends notifications to Telegram. 
The flow names are "Car Dashboard" and "Notifications".
## Configuration
### MQTT
If you are using the standard MQTT docker configuration, then after you import the flows Node-RED should automatically connect. Otherwise, open the ????node, select the ???? icon in the panel, edit the MQTT server's parameters, save and Deploy. 
### Telsgram
TBC

Download the Node-RED flows export here to import into your instance: 

