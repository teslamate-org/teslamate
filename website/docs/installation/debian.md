---
title: Manual install (Debian)
sidebar_label: Manual (Debian)
---

This document provides the necessary steps for installation of TeslaMate on a vanilla Debian or Ubuntu system. The **recommended and most straightforward installation approach is through the use of [Docker](docker.md)**, however this walkthrough provides the necessary steps for manual installation in an aptitude (Debian/Ubuntu) environment.

## Requirements

Click on the following items to view detailed installation steps.

<details>
  <summary>Postgres (v12+)</summary>

```bash
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" | sudo tee  /etc/apt/sources.list.d/pgdg.list
sudo apt-get update
sudo apt-get install -y postgresql-12 postgresql-client-12
```

Source: [postgresql.org/download](https://www.postgresql.org/download/)

</details>

<details>
  <summary>Elixir (v1.11+)</summary>

```bash
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install -y elixir esl-erlang
```

Source: [elixir-lang.org/install](https://elixir-lang.org/install)

</details>

<details>
  <summary>Grafana (v8.3.4+) & Plugins</summary>

```bash
sudo apt-get install -y apt-transport-https software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server.service # to start Grafana at boot time
```

Source: [grafana.com/docs/installation](https://grafana.com/docs/grafana/latest/installation/)

Install the required Grafana plugins as well:

```bash
sudo grafana-cli plugins install pr0ps-trackmap-panel 2.1.2
sudo grafana-cli --pluginUrl https://github.com/panodata/panodata-map-panel/releases/download/0.16.0/panodata-map-panel-0.16.0.zip plugins install grafana-worldmap-panel-ng
sudo systemctl restart grafana-server
```

[Import the Grafana dashboards](#import-grafana-dashboards) after [cloning the TeslaMate git repository](#clone-teslamate-git-repository).

</details>

<details>
  <summary>An MQTT Broker (e.g. Mosquitto)</summary>

```bash
sudo apt-get install -y mosquitto
```

Source: [mosquitto.org/download](https://mosquitto.org/download/)

</details>

<details>
  <summary>Node.js (v14+)</summary>

```bash
curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Source: [nodejs.org/en/download/package-manager](https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions-enterprise-linux-fedora-and-snap-packages)

</details>

## Clone TeslaMate git repository

The following command will clone the source files for the TeslaMate project. This should be run in an appropriate directory within which you would like to install TeslaMate. You should also record this path and provide them to the startup scripts proposed at the end of this guide.

```bash
cd /usr/src

git clone https://github.com/adriankumpf/teslamate.git
cd teslamate

git checkout $(git describe --tags `git rev-list --tags --max-count=1`) # Checkout the latest stable version
```

## Create PostgreSQL database

The following commands will create a database called `teslamate` on the PostgreSQL database server, and a user called `teslamate`. When creating the `teslamate` user, you will be prompted to enter a password for the user interactively. This password should be recorded and provided as an environment variable in the startup script at the end of this guide.

```console
sudo -u postgres psql
postgres=# create database teslamate;
postgres=# create user teslamate with encrypted password 'your_secure_password_here';
postgres=# grant all privileges on database teslamate to teslamate;
postgres=# ALTER USER teslamate WITH SUPERUSER;
postgres=# \q
```

_Note: The superuser privileges can be revoked after running the initial database migrations._

## Compile Elixir Project

```bash
mix local.hex --force; mix local.rebar --force

mix deps.get --only prod
npm install --prefix ./assets && npm run deploy --prefix ./assets

MIX_ENV=prod mix do phx.digest, release --overwrite
```

### Set your system locale

You may need to set your system locale. If you get an error when running the TeslaMate service which indicates that you don't have a UTF-8 capable system locale set, run the following commands to set the locale on your system:

```bash
sudo locale-gen en_US.UTF-8
sudo localectl set-locale LANG=en_US.UTF-8
```

## Starting TeslaMate at boot time

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

<Tabs
defaultValue="systemd"
values={[
{ label: 'systemd', value: 'systemd', },
{ label: 'screen', value: 'screen', },
]}>
<TabItem value="systemd">

Create a systemd service at `/etc/systemd/system/teslamate.service`:

```
[Unit]
Description=TeslaMate
After=network.target
After=postgresql.service

[Service]
Type=simple
# User=username
# Group=groupname

Restart=on-failure
RestartSec=5

Environment="HOME=/usr/src/teslamate"
Environment="LANG=en_US.UTF-8"
Environment="LC_CTYPE=en_US.UTF-8"
Environment="TZ=Europe/Berlin"
Environment="PORT=4000"
Environment="DATABASE_USER=teslamate"
Environment="DATABASE_PASS=#your secure password!
Environment="DATABASE_NAME=teslamate"
Environment="DATABASE_HOST=127.0.0.1"
Environment="MQTT_HOST=127.0.0.1"

WorkingDirectory=/usr/src/teslamate

ExecStartPre=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
ExecStart=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate start
ExecStop=/usr/src/teslamate/_build/prod/rel/teslamate/bin/teslamate stop

[Install]
WantedBy=multi-user.target
```

- `MQTT_HOST` should be the IP address of your MQTT broker. If you do not have one installed, the MQTT functionality can be disabled with `DISABLE_MQTT=true`.
- `TZ` should be your local timezone. Work out your timezone name using the [TZ database name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the linked Wikipedia page.

Start the service:

```bash
sudo systemctl start teslamate
```

And automatically get it to start on boot:

```bash
sudo systemctl enable teslamate
```

</TabItem>
<TabItem value="screen">

Create the following file: `/usr/local/bin/teslamate-start.sh`

You should at least substitute the following details:

- `MQTT_HOST` should be the IP address of your MQTT broker. If you do not have one installed, the MQTT functionality can be disabled with 'DISABLE_MQTT=true'.
- `TZ` should be your local timezone. Work out your timezone name using the [TZ database name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the linked Wikipedia page.
- `TESLAMATEPATH` should be the path that you ran the `git clone` within.

```
export DATABASE_USER="teslamate"
export DATABASE_PASS="your_secure_password_here"
export DATABASE_HOST="127.0.0.1"
export DATABASE_NAME="teslamate"
export MQTT_HOST="127.0.0.1"
export MQTT_USERNAME="teslamate"
export MQTT_PASSWORD="teslamate"
export MQTT_TLS="false"
export TZ="Europe/Berlin"
export TESLAMATEPATH=/usr/src/teslamate

$TESLAMATEPATH/_build/prod/rel/teslamate/bin/teslamate start
```

The following command needs to be run once during the installation process in order to create the database schema for the TeslaMate installation:

```bash
export DATABASE_USER="teslamate"
export DATABASE_PASS="your_secure_password_here"
export DATABASE_HOST="127.0.0.1"
export DATABASE_NAME="teslamate"
_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
```

Add the following to /etc/rc.local, to start a screen session at boot time and run the TeslaMate server within a screen session. This lets you interactively connect to the session if needed.

```bash
# Start TeslaMate
cd /usr/src/teslamate
screen -S teslamate -L -dm bash -c "cd /usr/src/teslamate; ./start.sh; exec sh"
```

</TabItem>
</Tabs>

## Import Grafana Dashboards

1.  Visit [localhost:3000](http://localhost:3000) and log in. The default credentials are: `admin:admin`.

2.  Create a data source with the name "TeslaMate":

    ```
    Type: PostgreSQL
    Default: YES
    Name: TeslaMate
    Host: localhost
    Database: teslamate
    User: teslamate  Password: your_secure_password_here
    SSL-Mode: disable
    Version: 10
    ```

3.  [Manually import](https://grafana.com/docs/reference/export_import/#importing-a-dashboard) the dashboard [files](https://github.com/adriankumpf/teslamate/tree/master/grafana/dashboards) or use the `dashboards.sh` script:

    ```bash
    $ ./grafana/dashboards.sh restore

    URL:                  http://localhost:3000
    LOGIN:                admin:admin
    DASHBOARDS_DIRECTORY: ./grafana/dashboards

    RESTORED locations.json
    RESTORED drive-stats.json
    RESTORED updates.json
    RESTORED drive-details.json
    RESTORED charge-details.json
    RESTORED states.json
    RESTORED overview.json
    RESTORED vampire-drain.json
    RESTORED visited.json
    RESTORED drives.json
    RESTORED projected-range.json
    RESTORED charge-level.json
    RESTORED charging-stats.json
    RESTORED mileage.json
    RESTORED charges.json
    RESTORED efficiency.json
    ```

    :::tip
    To use credentials other than the default, set the `LOGIN` variable:

    ```bash
    LOGIN=user:password ./grafana/dashboards.sh restore
    ```

    :::
