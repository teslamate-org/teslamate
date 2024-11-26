---
title: Backup and Restore
---

:::note
If you are using `docker-compose`, you are using Docker Compose v1, which has been deprecated. Docker Compose commands refer to Docker Compose v2. Consider upgrading your docker setup, see [Migrate to Compose V2](https://docs.docker.com/compose/migrate/)
:::

import Tabs from "@theme/Tabs";
import TabItem from "@theme/TabItem";

<Tabs
defaultValue="docker"
values={[
{ label: 'Docker', value: 'docker', },
{ label: 'Manual install (FreeBSD)', value: 'manual_freebsd', },
]}>
<TabItem value="docker">

## Backup

Create backup file `teslamate.bck`:

```bash
docker compose exec -T database pg_dump -U teslamate teslamate > ./teslamate.bck
```

:::note
`-T` is important if you add this line a crontab or the backup will not work because docker will generate this error `the input device is not a TTY`
:::

:::note
Be absolutely certain to move the `teslamate.bck` file to another safe location, as you may lose that backup file if you use a docker-compose GUI to upgrade your teslamate configuration. Some GUIs delete the folder that holds the `docker-compose.yml` when updating.
:::

:::note
If you get the error `No such service: database`, update your _docker-compose.yml_ or use `db` instead of `database` in the above command.
:::

:::note
If you changed `TM_DB_USER` in the .env file from one of the advanced guides, make sure to replace the first instance of `teslamate` to the value of `TM_DB_USER` in the above command.
:::

## Restore

:::note
Replace the default `teslamate` value below with the value defined in the .env file if you have one (TM_DB_USER and TM_DB_NAME)
:::

```bash
# Stop the teslamate container to avoid write conflicts
docker compose stop teslamate

# Drop existing data and reinitialize (Don't forget to replace first teslamate if using different TM_DB_USER)
docker compose exec -T database psql -U teslamate teslamate << .
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION cube WITH SCHEMA public;
CREATE EXTENSION earthdistance WITH SCHEMA public;
.

# Restore
docker compose exec -T database psql -U teslamate -d teslamate < teslamate.bck

# Restart the teslamate container
docker compose start teslamate
```
</TabItem>
<TabItem value="manual_debian">

## Backup

1. Open a terminal

2. Switch to the PostgreSQL user:
```bash
su - postgres
```
4. Run the pg_dump command to create a dump of your database. Replace `your_database_name` with the name of your database (e.g. teslamate) and `your_dump_file.sql` with the desired output file name (e.g. teslamate20241126.bck):
```bash
pg_dump your_database_name > your_dump_file.sql
```
6. Exit the PostgreSQL user:
```bash
exit
```

## Restore
</TabItem>
