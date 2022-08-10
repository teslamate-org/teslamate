---
title: 使用 Apache2、TLS、HTTP Basic Auth 的高级安装
---

如果你想让 TeslaMate 在互联网上公开使用，强烈建议保护 Web 界面，只允许用密码来访问 Grafana。本指南提供了**一个例子** _[docker-compose.yml](#docker-composeyml)_，它在以下方面与简单安装不同：

- TeslaMate 和 Grafana 这两个可公开访问的服务都位于反向代理（Apache2）之后，该代理终止了 HTTPS 流量。
- 端口 3000（Grafana）和 4000（TeslaMate）只在本地暴露。
- TeslaMate 服务受到 HTTP 基本认证的保护
- 自定义配置被移到一个单独的 `.env` 文件中
- Grafana 被配置为需要登录

## 要求

- 一个已经安装好的 Apache2 和以下模块：
  - `mod_proxy`
  - `mod_proxy_http`
  - `mod_proxy_wstunnel`
  - `mod_rewrite`
  - `mod_ssl`
- 两个 FQDN，例如 `teslamate.example.com` 和 `grafana.example.com`。
- 在 `/etc/letsencrypt/live/teslamate.<your domain>` 中包括上述两个的现有 SSL 证书。

## 步骤

创建以下文件：

### docker-compose.yml

```yml title="docker-compose.yml"
version: "3"

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
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
    ports:
      - 127.0.0.1:4000:4000
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
      - GF_AUTH_BASIC_ENABLED=true
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_SERVER_ROOT_URL=https://${FQDN_GRAFANA}
    ports:
      - 127.0.0.1:3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:2
    restart: always
    command: mosquitto -c /mosquitto-no-auth.conf
    ports:
      - 127.0.0.1:1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
```

### .env

这个文件应该和 docker-compose.yml 文件放在同一个文件夹中。

```plaintext title=".env"
TM_ENCRYPTION_KEY= #your secure key to encrypt your Tesla API tokens
TM_DB_USER=teslamate
TM_DB_PASS= #your secure password!
TM_DB_NAME=teslamate

GRAFANA_USER=admin
GRAFANA_PW=admin

FQDN_GRAFANA=grafana.example.com
FQDN_TM=teslamate.example.com

TM_TZ=Europe/Berlin

LETSENCRYPT_EMAIL=yourperson@example.com
```

### teslamate.conf

这个文件包含虚拟主机 `teslamate.example.com` 和 `grafana.example.com` 的定义。它必须通过 `a2ensite teslamate` 启用。

这假定你有 SSL 证书文件驻留在 `/etc/letsencrypt/live/teslamate.example.com`。如果它在其他地方，你需要相应地调整文件。

```apacheconf title="/etc/apache2/sites-available/teslamate.conf"
Define MYDOMAIN example.com
Define LOG access.teslamate.log

<VirtualHost *:80>
    ProxyPreserveHost On
    ServerName teslamate.${MYDOMAIN}
    CustomLog /var/log/apache2/${LOG} combined
    RewriteEngine on
    RewriteCond %{SERVER_NAME} =teslamate.${MYDOMAIN}
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost *:80>
    ProxyPreserveHost On
    ServerName grafana.${MYDOMAIN}
    CustomLog /var/log/apache2/${LOG} combined
    RewriteEngine on
    RewriteCond %{SERVER_NAME} =grafana.${MYDOMAIN}
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ProxyPreserveHost On
        ServerName teslamate.${MYDOMAIN}
        ProxyPass /live/websocket ws://127.0.0.1:4000/live/websocket
        ProxyPassReverse /live/websocket ws://127.0.0.1:4000/live/websocket
        ProxyPass / http://127.0.0.1:4000/
        ProxyPassReverse / http://127.0.0.1:4000/
        CustomLog /var/log/apache2/${LOG} combined
        <Proxy *>
            Authtype Basic
            Authname "Password Required"
            AuthUserFile /etc/apache2/.htpasswd
            <RequireAny>
                <RequireAll>
                    Require expr %{REQUEST_URI} =~ m#^/live/websocket.*#
                </RequireAll>
                Require valid-user
            </RequireAny>
        </Proxy>
        SSLCertificateFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
    </VirtualHost>
</IfModule>

<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ProxyPreserveHost On
        ServerName grafana.${MYDOMAIN}
        ProxyPass / http://127.0.0.1:3000/
        ProxyPassReverse / http://127.0.0.1:3000/
        CustomLog /var/log/apache2/${LOG} combined
        SSLCertificateFile /etc/letsencrypt/live/grafana.${MYDOMAIN}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/grafana.${MYDOMAIN}/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
    </VirtualHost>
</IfModule>
```

### .htpasswd

该文件包含访问 TeslaMate 的用户和密码（Basic-auth），注意这不是你的 tesla.com 密码。如果你没有安装 [Apache tools](https://www.cyberciti.biz/faq/create-update-user-authentication-files/)，你可以在网上生成它（例如：<http://www.htaccesstools.com/htpasswd-generator/>）。使用 BCrypt 加密模式。

**例子：**

```apacheconf title="/etc/apache2/.htpasswd"
teslamate:$2y$10$f7PB3UF3PNzqMIXZmf1dIefOkrv/15Xt6Xw3pzc6mkS/B5qoWBdAG
```

## 使用

用 `docker-compose up` 运行在同一目录下启动堆栈，docker-compose.yml 驻留在此。

1. 打开 Web 界面 [teslamate.example.com](https://teslamate.example.com)
2. 用你的 Tesla 账户登录
3. Grafana 仪表板可在 [grafana.example.com](https://grafana.example.com) 上找到。
