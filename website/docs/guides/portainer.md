---
title: Web based management of your docker installation
---

To graphically manage your docker installation of TeslaMate you could use [portainer](https://www.portainer.io).

## Installation

Just include the following into the respective parts (`services` and `volumes`) of your `docker-compose.yml`:

```yml docker-compose.yml
services:
  portainer:
    image: portainer/portainer
    restart: always
    ports:
      - "9000:9000"
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  portainer_data:
```

Then you can access the docker management console on http://yourhost:9000.

:::note
It should be warned, that exposing the docker socket `docker.sock` always implies a security risk. For more information see [Do not expose the Docker daemon socket](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html#rule-1---do-not-expose-the-docker-daemon-socket-even-to-the-containers).
:::
