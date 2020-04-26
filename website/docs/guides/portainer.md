---
title: Web based management of your docker installation
---

To manage your docker installation of TeslaMate you could use the open-source management UI [portainer](https://portainer.io).

## Installation

Add a new `portainer` service and a `portainer-data` volume to your `docker-compose.yml`:

```yml docker-compose.yml {4-12,15}
version: "3"

services:
  portainer:
    image: portainer/portainer
    restart: always
    ports:
      - 9000:9000
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data

volumes:
  portainer-data:
```

Afterwards, access the docker management console at http://yourhost:9000.

:::caution
Exposing the docker socket (`docker.sock`) is a security risk. Giving an application access to it is equivalent to giving a unrestricted root access to your host. For more information see [OWASP: Do not expose the Docker daemon socket](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html#rule-1---do-not-expose-the-docker-daemon-socket-even-to-the-containers).
:::
