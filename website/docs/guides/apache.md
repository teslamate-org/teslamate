---
title: Advanced install with Apache2, TLS, HTTP Basic Auth
---

In case you wish to make TeslaMate publicly available on the Internet, it is strongly recommended to secure the web interface and allow access to Grafana only with a password. This guide provides **an example** _[docker-compose.yml](#docker-composeyml)_ which differs from the simple installation in the following aspects:

- Both publicly accessible services, TeslaMate and Grafana, sit behind a reverse proxy (Apache2) which terminates HTTPS traffic
- Ports 3000 (Grafana) and 4000 (TeslaMate) are only exposed locally
- The TeslaMate service is protected by HTTP Basic Authentication
- Custom configuration was moved into a separate `.env` file
- Grafana is configured to require a login

## Requirements

- An already installed Apache2 with the following modules:
  - `mod_proxy`
  - `mod_proxy_http`
  - `mod_proxy_wstunnel`
  - `mod_rewrite`
  - `mod_ssl`
- Two FQDN, for example `teslamate.example.com` and `grafana.example.com`
- An existing SSL certificate including the two above in `/etc/letsencrypt/live/teslamate.<your domain>`

## Instructions

Create the following files:

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
    image: postgres:15
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

This file should reside in the same folder as the docker-compose.yml file.

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

This file contains the definition of the virtual hosts `teslamate.example.com` and `grafana.example.com`. It has to be enabled via `a2ensite teslamate`.

This assumes, that you have the SSL certificate files residing in `/etc/letsencrypt/live/teslamate.example.com`. If it is somewhere else, you need to adapt the file accordingly.

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

This file contains a user and password for accessing TeslaMate (Basic-auth), note this is NOT your tesla.com password. You can generate it on the web if you don't have the [Apache tools](https://www.cyberciti.biz/faq/create-update-user-authentication-files/) installed (e.g. http://www.htaccesstools.com/htpasswd-generator/). Use BCrypt encryption mode.

**Example:**

```apacheconf title="/etc/apache2/.htpasswd"
teslamate:$2y$10$f7PB3UF3PNzqMIXZmf1dIefOkrv/15Xt6Xw3pzc6mkS/B5qoWBdAG
```

## Usage

Start the stack with `docker compose up` run in the same directory, where the docker-compose.yml resides.

1. Open the web interface [teslamate.example.com](https://teslamate.example.com)
2. Sign in with your Tesla account
3. The Grafana dashboards are available at [grafana.example.com](https://grafana.example.com).
