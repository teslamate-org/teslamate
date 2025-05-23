---
title: Unraid install
sidebar_label: Unraid
---

This document provides the necessary steps for installation of TeslaMate on Unraid. 
## Requirements

- Existing Unraid install on v6 or higher with Docker service enabled
- Community Apps store installed
- appdata share configured
- External internet access, to talk to tesla.com

## Instructions

Unlike the Compose installation which sets up the following containers in one go, on Unraid you will need to install and configure each container individually from Community Apps.

**Postgres Docker**
1. Go to the Apps tab for the Community Apps and search for postgresql17 (current version supported) and click install.
2. Verify that no other applications are running on port `5432`
3. Pick a password of your choosing for the database
4. Set `POSTGRES_USER` to `teslamate`
5. Set `POSTGRES_DB` to `teslamate`
6. Click apply and set the container to autostart.

**Mosquito Docker**
1. Go to the Apps tab for the Community Apps and search for mosquitto (cmccambridge repository works well) and click install.
2. Verify that no other applications are running on port `1883`
3. Default template options are fine.
4. Click apply and set the container to autostart.

**TeslaMate Docker**
1. Go to the Apps tab for the Community Apps and search for TeslaMate and click install.
2. Verify that no other applications are running on port `4000`
3. **Choose a secure encryption key** that will be used to encrypt your Tesla API tokens (insert as `ENCRYPTION_KEY`).
4. Set the postgres user to `teslamate` and the postgres password to your password from the postgres setup
5. Set the database `teslamate` to match the previous config
6. Set the mqtt host to the ip address of your Unraid server
7. Create an mqtt user and password (required since the default setup is secure)
8. Click apply and optionally set the container to autostart

**TeslaMate-Grafana Docker**
1. Go to the Apps tab for the Community Apps and search for TeslaMate and click install.
2. Verify that no other applications are running on port `3000` (such as another Grafana instance). If so, specify a different port like 3333
3. Specify the teslamate database name, username, and password
4. Set the ip of your Unraid server for the host.
5. 8. Click apply and optionally set the container to autostart

## Usage

1. Open the web interface [http://your-ip-address:4000](http://localhost:4000) or click on the TeslaMate icon and select WebUI.
2. Sign in with your Tesla Account
3. The Grafana dashboards are available at [http://your-ip-address:3000](http://localhost:3000). Log in with the default user `admin` (initial password `admin`) and enter a secure password.

## Update

To update the running TeslaMate configuration to the latest version, go back to the Apps tab and wait for the Action Center to notify of new updates. You can also use the Auto Update Applications plugin if you like to live dangerously.
