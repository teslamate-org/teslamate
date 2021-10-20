# Overview
From the Node-RED website:
> Node-RED is a programming tool for wiring together hardware devices, APIs and online services in new and interesting ways.

> It provides a browser-based editor that makes it easy to wire together flows using the wide range of nodes in the palette that can be deployed to its runtime in a single-click.


# Docker Entries
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
