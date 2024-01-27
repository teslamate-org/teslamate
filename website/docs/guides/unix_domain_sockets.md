---
title: Using Unix Domain Sockets with a reverse-proxy
---

It is possible to configure Teslamate to communicate over unix-domain sockets (UDS) instea of a typical network socket.  This can be useful to improve security by restricting which applications can communicate to the application.  A typical configuration would be to use a UDS between a reverse-proxy (like Nginx) and Teslamate.  When paired with something like rootless-podman and [socket-activation](https://github.com/containers/podman/blob/main/docs/tutorials/socket_activation.md), Nginx can be configured with `--network=none` providing external access to Teslmate without the Nginx container having any networking at all. While setting up socket-activation and Podman is beyond the scope of this document, it will explain how to configure UDS between Teslamate and an Nginx reverse-proxy.


## Requirements

- Linux system configured with Teslamate installed and working
  - These instructions will document the procedure for using a UDS with docker-compose, but it is not difficult to adapt them to a system running Teslamate natively via systemd.
- Nginx configured as a reverse proxy


## Instructions

Nginx requires that the UDS exist when it is started, but Teslamate will (re)create the UDS on startup.  This means that Teslamate must be configured to start before Nginx, or Nginx must be configured to detect a socket change and reload (for example the [socket-gen](https://github.com/PhracturedBlue/socket-gen) utility designed for this purpose). Additionally, because docker-compose does not provide a method to run host-commands prior to starting a container, the directory containing the UDS must be manually created before Teslamate starts.  It is easiest to manually create this directory on a persistent volume.
  - Create a directory for the UDS:
    `mkdir -p /opt/nginx_uds/teslamate`
  - Allow Nginx to access the directory:
    `chown <nginx user> /opt/nginx_uds/teslamate`
  - Allow Teslamate to create the UDS:
     `chgrp 10001 /opt/nginx_uds/teslamate`
     `chmod 770 /opt/nginx_uds/teslamate`
An alternative to using owner/group access would be to use [ACLs](https://wiki.debian.org/Permissions#Access_Control_Lists_in_Linux) to control access to the UDS directory.

Next configure Teslamate to use the UDS.  Modify the teslamate service in docker-compose.yml to include:
```
    volumes:
      ...
      - /opt/nginx_uds/teslamate:/uds
    environment:
      ...
      - HTTP_BINDING_ADDRESS=/uds/teslamate.sock
      - SOCKET_PERM=666
    # ports:
    # - 4000:4000
```

Lastly, configure the Nginx reverse-proxy to forward connections to the UDS.  The relevant configuration would look something like:
```
upstream teslamate.uds {
    server unix:/opt/nginx_uds/teslamate/teslamate.sock;
}

server {
    server_name teslamate;
    http2 on;
    listen 80 ;
    location / {
        proxy_pass http://teslamate.uds;
        set $upstream_keepalive false;
    }
}
```
