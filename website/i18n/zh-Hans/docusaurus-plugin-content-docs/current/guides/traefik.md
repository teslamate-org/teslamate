---
title: 用 Traefik、Let's Encrypt 和 HTTP Basic Auth 进行高级安装
---

如果你想让 TeslaMate 在互联网上公开使用，强烈建议保护 Web 界面，只允许用密码访问 Grafana。本指南提供了一个 **[docker-compose.yml](#docker-composeyml)**，在以下方面与基本安装不同。

- TeslaMate 和 Grafana 这两个可公开访问的服务都位于一个反向代理（Traefik）的后面，该代理终止了 HTTPS 流量。
- TeslaMate 服务受到 HTTP 基本认证的保护
- 自定义配置被保存在一个单独的 `.env` 文件中
- Traefik 会自动获取 Let's Encrypt 证书
- Grafana 被配置为需要登录

> 请注意，这只是个**例子**，说明 TeslaMate 可以在更高级的情况下使用。根据你的使用情况，你可能需要做一些调整，主要是对 traefik 的配置。想要了解更多信息，请参阅 [traefik docs](https://docs.traefik.io/)。

## 要求

- 一个公共的 FQDN，例如 `teslamate.example.com`（在下面的例子中用你的域名代替）。

## 步骤

创建以下三个文件：

### docker-compose.yml

```yml title="docker-compose.yml"
version: "3"

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    depends_on:
      - database
    environment:
      - ENCRYPTION_KEY=${TM_ENCRYPTION_KEY}
      - DATABASE_USER=${TM_DB_USER}
      - DATABASE_PASS=${TM_DB_PASS}
      - DATABASE_NAME=${TM_DB_NAME}
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - VIRTUAL_HOST=${FQDN_TM}
      - CHECK_ORIGIN=true
      - TZ=${TM_TZ}
    volumes:
      - ./import:/opt/app/import
    labels:
      - "traefik.enable=true"
      - "traefik.port=4000"
      - "traefik.http.middlewares.redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.teslamate-auth.basicauth.realm=teslamate"
      - "traefik.http.middlewares.teslamate-auth.basicauth.usersfile=/auth/.htpasswd"
      - "traefik.http.routers.teslamate-insecure.rule=Host(`${FQDN_TM}`)"
      - "traefik.http.routers.teslamate-insecure.middlewares=redirect"
      - "traefik.http.routers.teslamate-ws.rule=Host(`${FQDN_TM}`) && Path(`/live/websocket`)"
      - "traefik.http.routers.teslamate-ws.entrypoints=websecure"
      - "traefik.http.routers.teslamate-ws.tls"
      - "traefik.http.routers.teslamate.rule=Host(`${FQDN_TM}`)"
      - "traefik.http.routers.teslamate.middlewares=teslamate-auth"
      - "traefik.http.routers.teslamate.entrypoints=websecure"
      - "traefik.http.routers.teslamate.tls.certresolver=tmhttpchallenge"
    cap_drop:
      - all

  database:
    image: postgres:14
    restart: always
    environment:
      - POSTGRES_USER=${TM_DB_USER}
      - POSTGRES_PASSWORD=${TM_DB_PASS}
      - POSTGRES_DB=${TM_DB_NAME}
    volumes:
      - teslamate-db:/var/lib/postgresql/data

  grafana:
    image: teslamate/grafana:latest
    restart: always
    environment:
      - DATABASE_USER=${TM_DB_USER}
      - DATABASE_PASS=${TM_DB_PASS}
      - DATABASE_NAME=${TM_DB_NAME}
      - DATABASE_HOST=database
      - GRAFANA_PASSWD=${GRAFANA_PW}
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PW}
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_SERVER_DOMAIN=${FQDN_TM}
      - GF_SERVER_ROOT_URL=%(protocol)s://%(domain)s/grafana
      - GF_SERVER_SERVE_FROM_SUB_PATH=true

    volumes:
      - teslamate-grafana-data:/var/lib/grafana
    labels:
      - "traefik.enable=true"
      - "traefik.port=3000"
      - "traefik.http.middlewares.redirect.redirectscheme.scheme=https"
      - "traefik.http.routers.grafana-insecure.rule=Host(`${FQDN_TM}`)"
      - "traefik.http.routers.grafana-insecure.middlewares=redirect"
      - "traefik.http.routers.grafana.rule=Host(`${FQDN_TM}`) && (Path(`/grafana`) || PathPrefix(`/grafana/`))"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=tmhttpchallenge"

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    ports:
      - 127.0.0.1:1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

  proxy:
    image: traefik:v2.7
    restart: always
    command:
      - "--global.sendAnonymous使用=false"
      - "--providers.docker"
      - "--providers.docker.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.tmhttpchallenge.acme.httpchallenge=true"
      - "--certificatesresolvers.tmhttpchallenge.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.tmhttpchallenge.acme.email=${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.tmhttpchallenge.acme.storage=/etc/acme/acme.json"
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./.htpasswd:/auth/.htpasswd
      - ./acme/:/etc/acme/
      - /var/run/docker.sock:/var/run/docker.sock:ro

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
```

> 如果你是从 [simple Docker setup](../installation/docker.md) 升级的，请确保你使用的 Postgres 版本与之前一样。要升级到新的版本，请看 [Upgrading PostgreSQL](../maintenance/upgrading_postgres.md)。

### .env

```plaintext title=".env"
TM_ENCRYPTION_KEY= #your secure key to encrypt your Tesla API tokens
TM_DB_USER=teslamate
TM_DB_PASS= #your secure password!
TM_DB_NAME=teslamate

GRAFANA_USER=admin
GRAFANA_PW=admin

FQDN_TM=teslamate.example.com

TM_TZ=Europe/Berlin

LETSENCRYPT_EMAIL=yourperson@example.com
```

> 如果你是从[简单的 Docker 设置](../installation/docker.md)升级的，请确保使用与之前相同的数据库和 Grafana 凭证。

### .htpasswd

该文件包含访问 TeslaMate 的用户和密码（Basic-auth）；注意，这**不是**你的 tesla.com 密码。如果你没有安装 [Apache 工具](https://www.cyberciti.biz/faq/create-update-user-authentication-files/)，你可以在网上生成它（例如：<http://www.htaccesstools.com/htpasswd-generator/>）。使用 BCrypt 加密模式。

**例子：**

```apacheconf title=".htpasswd"
teslamate:$2y$10$f7PB3UF3PNzqMIXZmf1dIefOkrv/15Xt6Xw3pzc6mkS/B5qoWBdAG
```

## 使用

用 `docker-compose up -d` 启动容器。

1. 打开网页界面 https://teslamate.example.com
2. 用你的特斯拉账户登录
3. 在 _Settings_ 页面中，更新 _URLs_ 字段。将 _Web App_ 设为 https://teslamate.example.com ，将 _Dashboards_ 设为 https://teslamate.example.com/grafana

> 如果你在登录 Grafana 时遇到困难，例如，你不能用简单设置中的凭证或存储在 .env 文件中的值登录，请用以下命令重置管理员密码。

```
docker-compose exec grafana grafana-cli admin reset-admin-password
```
