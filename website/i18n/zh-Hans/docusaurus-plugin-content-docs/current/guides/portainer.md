---
title: 基于网络的 docker 安装管理
---

为了管理你的 TeslaMate 的 docker 安装，你可以使用开源的管理用户界面 [portainer](https://portainer.io)。

## 安装

在你的 `docker-compose.yml` 中添加一个新的 `portainer` 服务和一个 `portainer-data` 卷。

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

之后，访问 docker 管理控制台：http://yourhost:9000。

:::caution
暴露 docker 套接字（`docker.sock`）是一种安全风险。给予一个应用程序访问它的权限，相当于给予一个不受限制的 root 访问你的主机。更多信息见 [OWASP: 不要暴露 Docker 守护套接字](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html#rule-1---do-not-expose-the-docker-daemon-socket-even-to-the-containers)。
:::
