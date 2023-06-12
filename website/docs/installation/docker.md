---
title: Docker install
sidebar_label: Docker
---

This document provides the necessary steps for installation of TeslaMate on a any system that runs Docker. For a walkthrough that provides the necessary steps for manual installation see [Manual Install](debian.md).

This setup is recommended only if you are running TeslaMate **on your home network**, as otherwise your Tesla API tokens might be at risk. If you intend to expose TeslaMate directly to the internet check out the [advanced guides](../guides/traefik.md).

## Requirements

- Docker _(if you are new to Docker, see [Installing Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/linux/))_
- A Machine that's always on, so TeslaMate can continually fetch data
- At least 1 GB of RAM on the machine for the installation to succeed.
- External internet access, to talk to tesla.com

## Instructions

1. Create a file called `docker-compose.yml` with the following content:

   ```yml title="docker-compose.yml"
   version: "3"

   services:
     teslamate:
       image: teslamate/teslamate:latest
       restart: always
       environment:
         - ENCRYPTION_KEY= #insert a secure key to encrypt your Tesla API tokens
         - DATABASE_USER=teslamate
         - DATABASE_PASS= #insert your secure database password!
         - DATABASE_NAME=teslamate
         - DATABASE_HOST=database
         - MQTT_HOST=mosquitto
       ports:
         - 4000:4000
       volumes:
         - ./import:/opt/app/import
       cap_drop:
         - all

     database:
       image: postgres:15
       restart: always
       environment:
         - POSTGRES_USER=teslamate
         - POSTGRES_PASSWORD= #insert your secure database password!
         - POSTGRES_DB=teslamate
       volumes:
         - teslamate-db:/var/lib/postgresql/data

     grafana:
       image: teslamate/grafana:latest
       restart: always
       environment:
         - DATABASE_USER=teslamate
         - DATABASE_PASS= #insert your secure database password!
         - DATABASE_NAME=teslamate
         - DATABASE_HOST=database
       ports:
         - 3000:3000
       volumes:
         - teslamate-grafana-data:/var/lib/grafana

     mosquitto:
       image: eclipse-mosquitto:2
       restart: always
       command: mosquitto -c /mosquitto-no-auth.conf
       # ports:
       #   - 1883:1883
       volumes:
         - mosquitto-conf:/mosquitto/config
         - mosquitto-data:/mosquitto/data

   volumes:
     teslamate-db:
     teslamate-grafana-data:
     mosquitto-conf:
     mosquitto-data:
   ```

2. **Choose a secure encryption key** that will be used to encrypt your Tesla API tokens (insert as `ENCRYPTION_KEY`).
3. **Choose your secure database password** and insert it at every occurrence of `DATABASE_PASS` and `POSTGRES_PASSWORD`
4. Start the docker containers with `docker compose up`. To run the containers in the background add the `-d` flag:

   ```bash
   docker compose up -d
   ```

## Usage

1. Open the web interface [http://your-ip-address:4000](http://localhost:4000)
2. Sign in with your Tesla account
3. The Grafana dashboards are available at [http://your-ip-address:3000](http://localhost:3000). Log in with the default user `admin` (initial password `admin`) and enter a secure password.

## [Update](../upgrading.mdx)

To update the running TeslaMate configuration to the latest version, run the following commands:

```bash
docker compose pull
docker compose up -d
```
