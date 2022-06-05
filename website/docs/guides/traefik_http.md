# Using Traefik only with HTTP ( without https)
- Someone needs to use simple setup for teslamate with http, personal use
- below docker-compose and .env file effective for quick setup
# .env file
## .env shoude have HOSTMACH
<pre>
TM_TZ=Asia/Seoul
HOSTMACH=***.***.com
</pre>

## docker-compose.yml 
- with http htpasswd Traefik dashboard
- with http htpasswd Teslamate 

<pre>
version: "3"

services:

  reverse-proxy:
    # The official v2 Traefik docker image
    image: traefik:v2.6
    # Enables the web UI and tells Traefik to listen to docker
    command: #--api.insecure=true --providers.docker
      #- "--api.insecure=true"
      - "--api.dashboard=true"
      - "--providers.docker"
      - "--providers.docker.exposedbydefault=false"
      #- "--entrypoints.http.address=:80"
      - "--entrypoints.tesla_traefik.address=:8080"
      - "--entrypoints.teslaweb.address=:4000"
      - "--log.level=DEBUG"
      - "--log.filePath=/var/log/traefik.log"
      - "--accesslog=true"
      - "--accesslog.filePath=/var/log/access.log"
    
    environment: 
      - TZ=${TM_TZ}
      #- TRAEFIK_ENTRYPOINTS_web_HTTP=:80
    
    ports:
      # The HTTP port
      # - "8880:8880"
      # The Web UI (enabled by --api.insecure=true)
      - "8080:8080"
      - "4000:4000"

    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.t_traefik.rule=Host(`${HOSTMACH}`)"
      - "traefik.http.routers.t_traefik.entrypoints=tesla_traefik"
      - "traefik.http.routers.t_traefik.service=api@internal"
      - "traefik.http.routers.t_traefik.middlewares=tMYAUTH"
      - "traefik.http.middlewares.tMYAUTH.basicauth.users=tinyos:$$apr1$$nqgD3Ut3$$Er9r.bvxgtGxLwTufl63C."
         # should input proper your PASSWD 
         # use this command on Terminal >>> echo $(htpasswd -nb user password) | sed -e s/\\$/\\$\\$/g

    volumes:
      # So that Traefik can listen to the Docker events
      - /var/run/docker.sock:/var/run/docker.sock
      - ./traefik/log/:/var/log/


  teslamate:
    image: teslamate/teslamate:latest
    container_name: teslamate
    restart: always

    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret 
        # should input proper your PASSWD 
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
      - MQTT_HOST=mosquitto
      - TZ=${TM_TZ}

    volumes:
      - ./import:/opt/app/import
    cap_drop:
      - all

    labels:
      - "traefik.enable=true"
      - "traefik.port=4000"
      - "traefik.http.routers.teslamate.rule=Host(`${HOSTMACH}`)"
      - "traefik.http.routers.teslamate.entrypoints=teslaweb"
      - "traefik.http.routers.teslamate.middlewares=MYAUTH"
      - "traefik.http.middlewares.MYAUTH.basicauth.users=tinyos:$$apr1$$nqgD3Ut3$$Er9r.bvxgtGxLwTufl63C."
         # should input proper your PASSWD 
         # use this command on Terminal >>> echo $(htpasswd -nb user password) | sed -e s/\\$/\\$\\$/g


  database:
    image: postgres:12
    restart: always
    #container_name: k_tesla_db
    environment:
      - POSTGRES_USER=teslamate
      - POSTGRES_PASSWORD=secret 
        #should input proper your PASSWD 
      - POSTGRES_DB=teslamate
    volumes:
      - teslamate-db:/var/lib/postgresql/data


  grafana:
    image: teslamate/grafana:latest
    restart: always
    #container_name: k_tesla_grafana
    environment:
      - DATABASE_USER=teslamate
      - DATABASE_PASS=secret 
        #should input proper your PASSWD 
      - DATABASE_NAME=teslamate
      - DATABASE_HOST=database
    ports:
      - 3000:3000
    volumes:
      - teslamate-grafana-data:/var/lib/grafana

  mosquitto:
    image: eclipse-mosquitto:1.6
    restart: always
    #container_name: k_tesla_mqtt
    ports:
      - 1883:1883
    volumes:
      - mosquitto-conf:/mosquitto/config
      - mosquitto-data:/mosquitto/data

volumes:
  teslamate-db:
  teslamate-grafana-data:
  mosquitto-conf:
  mosquitto-data:
</pre>

### written by 
- https://github.com/jeonghoonkang/

