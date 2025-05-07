---
title: Backup and Restore
---

:::note
If you are using `docker-compose`, you are using Docker Compose v1, which has been deprecated. Docker Compose commands refer to Docker Compose v2. Consider upgrading your docker setup, see [Migrate to Compose V2](https://docs.docker.com/compose/migrate/)
:::

## Backup

Create backup file `teslamate.bck`:

```bash
docker compose exec -T database pg_dump -U teslamate teslamate > teslamate_database_$(date +%F_%H-%M-%S).sql
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

1. Stop the teslamate container to avoid write conflicts

```bash
docker compose stop teslamate
```

2. Drop existing data and reinitialize (Don't forget to replace first teslamate if using different TM_DB_USER)

```bash
docker compose exec -T database psql -U teslamate teslamate << .
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION cube WITH SCHEMA public;
CREATE EXTENSION earthdistance WITH SCHEMA public;
.
```

3. Restore

Use the same filename that was used in the backup step.
Replace `<backup_filename>` with the actual filename generated during the backup step (e.g., `teslamate_database_2025-05-07_07-33-48.sql`).

```bash
docker compose exec -T database psql -U teslamate -d teslamate < <backup_filename>
```

4. Restart the teslamate container

```bash
docker compose start teslamate
```
