# Advanced Docker Setup with Apache2

**Differences to the basic setup:**

- Access to services via teslamate.example.com and grafana.example.com
- Web services (`teslamate` and `grafana`) sit behind a reverse proxy (Apache2) which terminates HTTPS traffic
- Custom configuration was moved into a separate `.env` file
- HTTP requests are redirected to HTTPS
- Ports 3000 (grafana) and 4000 (teslamate) are only exposed locally

## Requirements

- Docker running on a machine that's always on
- Two FQDN (`teslamate.example.com` & `grafana.example.com`)
- An existing SSL certificate
- External internet access, to talk to tesla.com

## Setup

Create the following files:

#### docker-compose.yml

```YAML
version: '3'

services:
  teslamate:
    image: teslamate/teslamate:latest
    restart: always
    environment:
      - DATABASE_USER=${TM_DB_USER}
      - DATABASE_PASS=${TM_DB_PASS}
      - DATABASE_NAME=${TM_DB_NAME}
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - VIRTUAL_HOST=${FQDN_TM}
      - CHECK_ORIGIN=true
      - TZ={$TM_TZ}
    volumes:
      - ./import:/opt/app/import
    ports:
      - 127.0.0.1:4000:4000
    cap_drop:
      - all

  database:
    image: postgres:12
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
    image: eclipse-mosquitto:1.6
    restart: always
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

#### .env

```
TM_DB_USER=teslamate
TM_DB_PASS=secret
TM_DB_NAME=teslamate

GRAFANA_USER=admin
GRAFANA_PW=admin

FQDN_GRAFANA=grafana.example.com
FQDN_TM=teslamate.example.com

TM_TZ=Europe/Berlin

LETSENCRYPT_EMAIL=yourperson@example.com
```

#### teslamate.conf (to be placed in /etc/apache2/sites-available)

This file contains the definition of the virtual hosts `teslamate.example.com` and `grafana.example.com`. It has to be enabled via `a2ensite teslamate`.

```apacheconf
Define MYDOMAIN example.com
Define LOG access.teslamate.log

<VirtualHost *:80>
    ProxyPreserveHost On
    ServerName teslamate.${MYDOMAIN}
    CustomLog /var/log/apache2/${LOG} combined
    RewriteCond %{SERVER_NAME} =teslamate.${MYDOMAIN}
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost *:80>
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
            Require valid-user
        </Proxy>
        SSLCertificateFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
    </VirtualHost>
</IfModule>

<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName grafana.${MYDOMAIN}
        ProxyPass / http://127.0.0.1:3000/
        ProxyPassReverse / http://127.0.0.1:3000/
        CustomLog /var/log/apache2/${LOG} combined
        SSLCertificateFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/teslamate.${MYDOMAIN}/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
    </VirtualHost>
</IfModule>
```

This assumes, that you have the SSL certificate files residing in `/etc/letsencrypt/live/teslamate.example.com`.

#### .htpasswd (to be placed in /etc/apache2)

This file contains a user and password for accessing TeslaMate (Basic-auth), note this is NOT your tesla.com password. You can generate it on the web if you don't have the Apache tools installed (e.g. http://www.htaccesstools.com/htpasswd-generator/).

**Example:**

```apacheconf
teslamate:$apr1$0hau3aWq$yzNEh.ABwZBAIEYZ6WfbH/
```

## Usage

Start the stack with `docker-compose up` run in the same directory, where the docker-compose.yml resides.

1. Open the web interface [https://teslamate.example.com](https://teslamate.example.com)
2. Sign in with your Tesla account
3. The Grafana dashboards are available at [https://grafana.example.com](https://grafana.example.com).
