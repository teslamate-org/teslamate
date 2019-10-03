# Installation on Docker

The recommended way to install and run TeslaMate is to use Docker. Create a
`docker-compose.yml` file and replace the necessary `environment` variables:

```YAML
version: '3'
services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: unless-stopped
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=db
      - MQTT_HOST=mosquitto
      - VIRTUAL_HOST=localhost # if you're going to access the UI from another  machine replace
                               # "localhost" with the hostname / IP address of the docker host.
      - TZ=Europe/Berlin       # (optional) replace to use local time in debug logs. See "Configuration".
    ports:
      - 4000:4000
    cap_drop:
      - all

  db:
    image: postgres:11
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
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

Afterwards start everything with `docker-compose up`.

Open the web interface at http://ip-of-your-machine:4000 and sign in with your
Tesla Account.

To access Grafana go to http://ip-of-your-machine:3000.

**Optional:** To switch to **imperial measurements** open the web interface and
navigate to `Settings`.

_For a more advanced setup check out the wiki: [Advanved Setup (SSL, FQDN, pw
protected)](<https://github.com/adriankumpf/teslamate/wiki/Advanved-Setup-(SSL,-FQDN,-pw-protected)>)_
