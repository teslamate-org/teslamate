# Installation on Debian/Ubuntu

This document provides the necessary steps for installation of TeslaMate on a vanilla Debian or Ubuntu system. The recommended and most straightforward installation approach is through the use of [Docker](docker.md), however this walkthrough provides the necessary steps for manual installation in an aptitude (Debian/Ubuntu) environment.

## Install Required Packages

```bash
sudo apt-get install -y git postgresql-11 screen wget
```

### Add Erlang repository and install

```bash
wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && sudo dpkg -i erlang-solutions_1.0_all.deb
sudo apt-get install -y elixir esl-erlang
```

### Add Grafana repository and install Grafana

```bash
sudo apt-get install -y apt-transport-https software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y grafana
```

_TBA_: how to install the following plugins: `pr0ps-trackmap-panel` and `natel-discrete-panel`

### Install mosquitto MQTT Broker

_TBA_

### Add nodesource (Node.js) repository and install node

```bash
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Clone TeslaMate git repository

The following command will clone the source files for the TeslaMate project. This should be run in an appropriate directory within which you would like to install TeslaMate. You should also record this path and provide them to the startup scripts proposed at the end of this guide.

```bash
cd /usr/src

git clone https://github.com/adriankumpf/teslamate.git

# Checkout the latest stable version
git checkout $(git describe --tags)
```

### Create PostgreSQL database

The following commands will create a database called `teslamate` on the PostgreSQL database server, and a user called `teslamate`. When creating the `teslamate` user, you will be prompted to enter a password for the user interactively. This password should be recorded and provided as an environment variable in the startup script at the end of this guide.

```bash
su -c "createdb teslamate" postgres
su -c "createuser teslamate -W" postgres
```

### Compile Elixir Project

```bash
# download dependencies
mix deps.get --only prod

npm install --prefix ./assets && npm run deploy --prefix ./assets

mix phx.digest
MIX_ENV=prod mix release
```

### Create the database schema after the first-time installation

The following command needs to be run once during the installation process in order to create the database schema for the TeslaMate installation:

```bash
_build/prod/rel/teslamate/bin/teslamate eval "TeslaMate.Release.migrate"
```

### Set your system locale

You may need to set your system locale. If you get an error when running the TeslaMate service which indicates that you don't have a UTF-8 capable system locale set, run the following commands to set the locale on your system:

```bash
sudo locale-gen en_US.UTF-8
sudo localectl set-locale LANG=en_AU.UTF-8
```

### Starting TeslaMate at boot time

There are a number of approaches to start TeslaMate at boot time:

#### Using systemd

_TBA_

#### Using screen

Create the following file: `/usr/local/bin/teslamate-start.sh`

You should at least substitute the following details:

- `MQTT_HOST` should be the IP address of your MQTT broker. If you do not have one installed, the MQTT functionality can be disabled with 'DISABLE_MQTT=true'.
- `TZ` should be your local timezone. Work out your timezone name using the [TZ database name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) in the linked wikipedia page.
- `TESLAMATEPATH` should be the path that you ran the `git clone` within.

```
export DATABASE_USER="teslamate"
export DATABASE_PASS="teslamate"
export DATABASE_HOST="127.0.0.1"
export DATABASE_NAME="teslamate"
export MQTT_HOST="192.168.1.1"
export MQTT_USERNAME="teslamate"
export MQTT_PASSWORD="teslamate"
export MQTT_TLS="false"
export TZ="Australia/Melbourne"
export TESLAMATEPATH=/usr/src/teslamate

$TESLAMATEPATH/_build/prod/rel/teslamate/bin/teslamate start
```

Add the following to /etc/rc.local, to start a screen session at boot time and run the TeslaMate server within a screen session. This lets you interactively connect to the session if needed.

```bash
# Start TeslaMate
cd /usr/src/teslamate
screen -S teslamate -L -dm bash -c "cd /usr/src/teslamate; ./start.sh; exec sh"
```

## Import Grafana Dashboards

1.  Visit [localhost:3000](http://localhost:3000) and log in.

2.  Create a data source with the name "TeslaMate":

    ```
    Type: PostgreSQL
    Default: YES
    Name: TeslaMate
    Host: localhost
    Database: teslamate
    User: teslamate  Password: secret
    SSL-Mode: disable
    Version: 10
    ```

3.  [Manually import](https://grafana.com/docs/reference/export_import/#importing-a-dashboard) the dashboard [files](https://github.com/adriankumpf/teslamate/tree/master/grafana/dashboards) or use `wizzy`:

    Download and install wizzy

    ```bash
    npm install -g wizzy
    ```

    Change directory:

    ```bash
    cd grafana
    ```

    Configure grafana properties

    ```bash
    wizzy init
    wizzy set grafana url http://localhost:3000
    wizzy set grafana username admin
    wizzy set grafana password admin
    ```

    Export the dashboards to Grafana

    ```bash
    wizzy export dashboards
    ```
