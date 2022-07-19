---
title: Manual install (FreeBSD)
sidebar_label: Manual (FreeBSD)
---

This document provides the necessary steps for installation of TeslaMate in a FreeBSD jail. The **recommended and most straightforward installation approach is through the use of [Docker](docker.md)**, however this walkthrough provides the necessary steps for manual installation in a FreeBSD 13.0 environment.
It assumes that pre-requisites are met and only basic instructions are provided and should also work in FreeBSD before 13.0.

## Requirements

Click on the following items to view detailed installation steps.

<details>
  <summary>bash & jq</summary>

```bash
pkg install bash jq
bash
```

For simplicity reasons, follow the rest of the tutorial in bash rather the csh.

</details>

<details>
  <summary>git</summary>

```bash
pkg install git
```

</details>

<details>
  <summary>Erlang (v21+)</summary>

```bash
pkg install erlang
```

</details>

<details>
  <summary>Elixir (v1.12+)</summary>

Unfortunately the Elixir part is not well updated in FreeBSD ports.
Hence the latest supported version for Erlang 21 (latest in FreeBSD ports)
is Elixir 1.11.

We will need to compile it from source, which is pretty easy though.

```bash
pkg install gmake

mkdir /usr/local/src
cd /usr/local/src
git clone https://github.com/elixir-lang/elixir.git
cd elixir
git checkout v1.11.4
gmake clean test
gmake install
elixir --version
```

</details>

<details>
  <summary>Postgres (v12+)</summary>

```bash
pkg install postgresql(12|13)-server
pkg install postgresql(12|13)-contrib
echo postgres_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>Grafana (v8.3.4+) & Plugins</summary>

```bash
pkg install grafana7
echo grafana_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>An MQTT Broker (e.g. Mosquitto)</summary>

```bash
pkg install mosquitto
echo mosquitto_enable="yes" >> /etc/rc.conf
```

</details>

<details>
  <summary>Node.js (v14+)</summary>

```bash
pkg install node14
pkg install npm-node14
```

</details>

## Clone TeslaMate git repository

The following command will clone the source files for the TeslaMate project. This should be run in an appropriate directory within which you would like to install TeslaMate. You should also record this path and provide them to the startup scripts proposed at the end of this guide.

```bash
cd /usr/local/src

git clone https://github.com/adriankumpf/teslamate.git
cd teslamate

git checkout $(git describe --tags `git rev-list --tags --max-count=1`) # Checkout the latest stable version
```

## Create PostgreSQL database

The following commands will create a database called `teslamate` on the PostgreSQL database server, and a user called `teslamate`. When creating the `teslamate` user, you will be prompted to enter a password for the user interactively. This password should be recorded and provided as an environment variable in the startup script at the end of this guide. Use 'su - postgres' if unable to enter psql console from current user.

```console
psql
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

export MIX_ENV=prod
mix do phx.digest, release --overwrite
```

## Starting TeslaMate at boot time

### Create FreeBSD service definition _/usr/local/etc/rc.d/teslamate_

```console
# PROVIDE: teslamate
# REQUIRE: DAEMON
# KEYWORD: teslamate,tesla

. /etc/rc.subr

name=teslamate
rcvar=teslamate_enable

load_rc_config $name

user=teslamate
group=teslamate

#
# DO NOT CHANGE THESE DEFAULT VALUES HERE
# SET THEM IN THE /etc/rc.conf FILE
#
teslamate_enable=${teslamate_enable-"NO"}
pidfile=${teslamate_pidfile-"/var/run/${name}.pid"}

teslamate_enable_mqtt=${teslamate_enable_mqtt-"FALSE"}
teslamate_db_port=${teslamate_db_port-"5432"}

HTTP_BINDING_ADDRESS="0.0.0.0"; export HTTP_BINDING_ADDRESS
HOME="/usr/local/src/teslamate"; export HOME
PORT=${teslamate_port-"4000"}; export PORT
TZ=${teslamate_timezone-"Europe/Berlin"}; export TZ
LANG=${teslamate_locale-"en_US.UTF-8"}; export LANG
LC_CTYPE=${teslamate_locale-"en_US.UTF-8"}; export LC_TYPE
DATABASE_NAME=${teslamate_db-"teslamate"}; export DATABASE_NAME
DATABASE_HOST=${teslamate_db_host-"localhost"}; export DATABASE_HOST
DATABASE_USER=${teslamate_db_user-"teslamate"}; export DATABASE_USER
DATABASE_PASS=${teslamate_db_pass}; export DATABASE_PASS
ENCRYPTION_KEY=${teslamate_encryption_key}; export ENCRYPTION_KEY
DISABLE_MQTT=${teslamate_mqtt_enable-"FALSE"}; export DISABLE_MQTT
MQTT_HOST=${teslamate_mqtt_host-"localhost"}; export MQTT_HOST
VIRTUAL_HOST=${teslamate_virtual_host-"teslamate.example.com"}; export VIRTUAL_HOST

COMMAND=${teslamate_command-"${HOME}/_build/prod/rel/teslamate/bin/teslamate"}

teslamate_start()
{
  ${COMMAND} eval "TeslaMate.Release.migrate"
  ${COMMAND} daemon
}

start_cmd="${name}_start"
stop_cmd="${COMMAND} stop"
status_cmd="${COMMAND} pid"


run_rc_command "$1"

```

### Update _/etc/rc.conf_

```bash
echo teslamate_enable="YES" >> /etc/rc.conf
echo teslamate_db_host="localhost"  >> /etc/rc.conf
echo teslamate_port="5432"  >> /etc/rc.conf
echo teslamate_db_pass="<super secret>" >> /etc/rc.conf
echo teslamate_encryption_key="<super secret encryption key>" >> /etc/rc.conf
echo teslamate_disable_mqtt="true" >> /etc/rc.conf
echo teslamate_timezone="<TZ Database>" >> /etc/rc.conf #i.e. Europe/Berlin
```

### Start service

```bash
chmod +x /usr/local/etc/rc.d/teslamate
service teslamate start
```

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
