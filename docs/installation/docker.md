# Simple Docker Setup

This setup is recommended only if you are running TeslaMate on your home network, as otherwise your Tesla credentials might be at risk. If you intend to expose TeslaMate directly to the internet consider using the [advanced Docker setup](docker_advanced.html).

## Requirements

- Docker
- A Machine that's always on, so TeslaMate can continually fetch data
- External internet access, to talk to tesla.com

If you are new to Docker, see [Docker on Raspberry Pi](https://dev.to/rohansawant/installing-docker-and-docker-compose-on-the-raspberry-pi-in-5-simple-steps-3mgl)

## Setup

Create a file called `docker-compose.yml` with the following content:

**docker-compose.yml**

```YAML
version: '3'

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
      - MQTT_HOST=mosquitto
    ports:
      - 4000:4000
    cap_drop:
      - all

  db:
    image: postgres:11
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:1.6
    restart: always
    ports:
      - 1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
    teslamate-db:
    teslamate-grafana-data:
    mosquitto-conf:
    mosquitto-data:
```

## Start Docker

Afterwards start the stack with `docker-compose up`. To run the containers in the background add the `-d` flag: `docker-compose up -d`.

## Usage

1. Open the web interface [http://your-ip-address:4000](http://localhost:4000)
2. Sign in with your Tesla Account open the web interface
3. The Grafana dashboards are available at [http://your-ip-address:3000](http://localhost:3000).
