---
title: Advanced installation with Tailscale
---

You can make a Docker installation of TeslaMate privately available from the Internet by using a personal VPN such as [TailScale](https://tailscale.com/). TailScale is free for personal use and provides a secure point-to-point and end-to-end encrypted network between any of your devices. In this case, we will set up TeslaMate in Docker and connect it to your personal TailScale network. Then you can install TailScale on any device (e.g., your phone, tablet, computer) to be able to securely access TeslaMate from anywhere.

Compared to the basic installation:

- TeslaMate and Grafana are only accessible via a secure private virtual network.
- All authentication is handled at the network level by TailScale; no passwords are needed for TeslaMate or Grafana.

The Docker configuration creates a TailScale container to use as a network sidecar for TeslaMate. The other services are then configured to share the same network as the sidecar container, which makes TeslaMate available on your TailScale network.


> Please note that this is only **an example** of how TeslaMate can be used in a more advanced scenario. Depending on your use case, you may need to make some adjustments.

## Requirements

- A TailScale account (free for personal use)
- A place to host your TeslaMate install. This can be on a computer at home, a NAS (e.g., Synology), or a cloud-hosted VM (e.g., free-tier AWS, GCP hosts), so long as it has the ability to run Docker.
- Optional: an external DNS name such as teslamate.yourdomain.com

## Instructions

Create the following file:

### docker-compose.yml

```yml title="docker-compose.yml"
version: "3"

services:
  tailscale:
    hostname: teslamate                       # This will become the tailscale device name
    image: jauderho/tailscale:latest          # An unofficial tailscale/tailscale image
    volumes:
      - "./tailscale_var_lib:/var/lib"        # State data will be stored in this directory
      - "/dev/net/tun:/dev/net/tun"           # Required for tailscale to work
    cap_add:                                  # Required for tailscale to work
      - net_admin
      - sys_module
    command: tailscaled

  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=localhost               # network_mode service means everything is on the same "host"
      - MQTT_HOST=mosquitto
    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all
    network_mode: service:tailscale
    depends_on:
      - tailscale

  database:
    image: postgres:13
    restart: always
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret
      - POSTGRES_DB=teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data
    network_mode: service:tailscale
    depends_on:
      - tailscale

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=localhost                 # network_mode service means everything is on the same "host"
    volumes:
      - teslamate-grafana-data:/var/lib/grafana
    network_mode: service:tailscale
    depends_on:
      - tailscale

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data
    network_mode: service:tailscale
    depends_on:
      - tailscale

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
```


## Usage

If you have not already, sign up for TailScale and [install it](https://tailscale.com/download) on your computer (or phone).
Visit https://hello.ipn.dev/ to verify that you have signed in correctly.

Start the stack with:

    docker-compose up -d

Authenticate your sidecar to TailScale with:

    docker-compose exec tailscale tailscale up

(You may need to add `-t` to get a TTY.) This will prompt you to visit a URL of the form `https://login.tailscale.com/a/SOME_HEX_CODE`. Do so from a computer to authorize your stack to connect to your TailScale network.

TailScale assigns a unique IP address of the form 100.x.y.z to each machine. Visit https://login.tailscale.com/admin/machines (or open the app on your computer or phone. Find the address associated with your new stack. Let's say it is 100.2.3.4.

If you wish to use a DNS name instead of an IP address, here are two options:
1. You can enable TailScale [Magic DNS](https://login.tailscale.com/admin/dns) to be able to use the name `teslamate` directly in your browser.
2. You can create an `A` record at `yourdomain.com` to map `teslamate.yourdomain.com` to the address you found (100.2.3.4). Although this record will be globally accessible, it will be for an IP address that no one else will be able to access without being authenticated to your personal TailScale network.

If you have done the above, you should be able to open the web interface of TeslaMate at `http://teslamate:4000/`. Otherwise use `http://100.2.3.4:4000/`.

From the TeslaMate UI, sign in with your Tesla account.

In the _Settings_ page, update the _URLs_, set the _Web App_ to `http://teslamate:4000/` and _Dashboards_ to `http://teslamate:3000/` (if using Magic DNS; otherwise use your FQDN).

For easy access from your phone, visit http://teslamate:4000/ from your phone's browser and then [add it to your home screen](http://google.com/search?q=add+url+to+home+screen).

## References

* https://tailscale.com/kb for more documentation about TailScale
* https://rnorth.org/tailscale-docker/ describes the sidecar pattern in more detail.
* If using GCP, you can use Container Optimized OS by following [this guide](https://cloud.google.com/community/tutorials/docker-compose-on-container-optimized-os).
