---
title: 使用 Docker 安装
sidebar_label: Docker
---

本文档提供了在任何运行 Docker 的系统上安装 TeslaMate 的必要步骤。关于手动安装的必要步骤，请参见[手动安装](debian.md)。

只有当你**在家庭网络上**运行 TeslaMate 时，才建议使用这种安装方式，否则你的 Tesla API 令牌可能会有风险。如果你打算将 TeslaMate 直接暴露在互联网上，请查看[高级指南](../guides/traefik.md)。

## 要求

- Docker _(如果你从未接触过 Docker，请先浏览[安装 Docker 和 Docker Compose](https://dev.to/rohansawant/installing-docker-and-docker-compose-on-the-raspberry-pi-in-5-simple-steps-3mgl))_
- 一台永远开着的机器，因此 TeslaMate 可以不断地获取车辆数据。
- 机器上至少要有 1GB 的内存才能安装成功。
- 已经接入互联网，并可以连接到 tesla.com

## 步骤

1. 创建一个名为 `docker-compose.yml` 的文件，内容如下：

   ```yml title="docker-compose.yml"
   version: "3"

   services:
     teslamate:
       image: teslamate/teslamate:latest
       restart: always
       environment:
         - ENCRYPTION_KEY= #insert a secure key to encrypt your Tesla API tokens
         - DATABASE_USER=teslamate
         - DATABASE_PASS= #insert your secure database password!
         - DATABASE_NAME=teslamate
         - DATABASE_HOST=database
         - MQTT_HOST=mosquitto
       ports:
         - 4000:4000
       volumes:
         - ./import:/opt/app/import
       cap_drop:
         - all

     database:
       image: postgres:14
       restart: always
       environment:
         - POSTGRES_USER=teslamate
         - POSTGRES_PASSWORD= #insert your secure database password!
         - POSTGRES_DB=teslamate
       volumes:
         - teslamate-db:/var/lib/postgresql/data

     grafana:
       image: teslamate/grafana:latest
       restart: always
       environment:
         - DATABASE_USER=teslamate
         - DATABASE_PASS= #insert your secure database password!
         - DATABASE_NAME=teslamate
         - DATABASE_HOST=database
       ports:
         - 3000:3000
       volumes:
         - teslamate-grafana-data:/var/lib/grafana

     mosquitto:
       image: eclipse-mosquitto:2
       restart: always
       command: mosquitto -c /mosquitto-no-auth.conf
       # ports:
       #   - 1883:1883
       volumes:
         - mosquitto-conf:/mosquitto/config
         - mosquitto-data:/mosquitto/data

   volumes:
     teslamate-db:
     teslamate-grafana-data:
     mosquitto-conf:
     mosquitto-data:
   ```

2. **选择一个安全的加密密钥**，以用于加密你的 Tesla API 令牌（作为 `ENCRYPTION_KEY`）。
3. **选择你的安全数据库密码**，并在每次出现 `DATABASE_PASS` 和 `POSTGRES_PASSWORD` 时引入它。
4. 用 `docker-compose up` 启动 docker 容器。要在后台运行容器，请添加 `-d` 命令。

   ```bash
   docker-compose up -d
   ```

## 使用

1. 打开网页界面 [http://your-ip-address:4000](http://localhost:4000)
2. 用你的特斯拉账户登录
3. Grafana 仪表盘可在 [http://your-ip-address:3000](http://localhost:3000)。用默认用户 `admin` 登录（初始密码为 `admin`）并输入一个安全的密码。

## [更新](../upgrading.mdx)

要将正在运行的 TeslaMate 配置更新为最新版本，请运行以下命令：

```bash
docker-compose pull
docker-compose up -d
```
