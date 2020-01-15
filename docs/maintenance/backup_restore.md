# Backup and Restore


## Backup

```bash
docker ps
```
CONTAINER ID        IMAGE                        COMMAND                  CREATED             STATUS              PORTS                                            NAMES
de6522bcd313        eclipse-mosquitto:1.6        "/docker-entrypoint.…"   7 days ago          Up 44 hours         0.0.0.0:1883->1883/tcp, 0.0.0.0:9001->9001/tcp   teslamate_mosquitto_1
0f280bef0e95        postgres:11                  "docker-entrypoint.s…"   7 days ago          Up 44 hours         5432/tcp                                         teslamate_db_1
b2d8431caa36        teslamate/grafana:latest     "/run.sh"                7 days ago          Up 44 hours         127.0.0.1:3000->3000/tcp                         teslamate_grafana_1
71d823ad5782        teslamate/teslamate:latest   "/bin/sh /entrypoint…"   7 days ago          Up 44 hours         127.0.0.1:4000->4000/tcp                         teslamate_teslamate_1

```bash
docker exec -it 0f280bef0e95 pg_dump -U teslamate > teslamate.bck
```
Now we have all data in teslamate.bck.

## Restore

```bash
docker ps
```
CONTAINER ID        IMAGE                        COMMAND                  CREATED             STATUS              PORTS                                            NAMES
7cf373f3a414        teslamate/grafana:latest     "/run.sh"                9 minutes ago       Up 9 minutes        127.0.0.1:3000->3000/tcp                           teslamate_grafana_1
0b0466c4cc0d        teslamate/teslamate:latest   "/bin/sh /entrypoint…"   9 minutes ago       Up 9 minutes        127.0.0.1:4000->4000/tcp                         teslamate_teslamate_1
7ef0b20c0880        postgres:11                  "docker-entrypoint.s…"   9 minutes ago       Up 9 minutes        5432/tcp                                         teslamate_db_1
bbf7310b968f        eclipse-mosquitto:1.6        "/docker-entrypoint.…"   9 minutes ago       Up 9 minutes        0.0.0.0:1883->1883/tcp, 0.0.0.0:9001->9001/tcp   teslamate_mosquitto_1

```bash
docker stop 0b0466c4cc0d # better stop teslamate to avoid write conflicts
docker exec -i 7ef0b20c0880 psql -U teslamate << .
drop schema public cascade;
create schema public;
.
docker start 0b0466c4cc0d
```

```bash
docker exec -i 7ef0b20c0880 psql -U teslamate -d teslamate < teslamate.bck
```
	< lot of output >
	