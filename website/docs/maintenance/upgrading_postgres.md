---
title: Upgrading PostgreSQL to a new major version
sidebar_label: Upgrading PostgreSQL
---

In these instructions it is assumed you are upgrading from postgresql 16 to postgresql 17. Please update
references to 16 to your start version and 17 to your desired version.

These instructions also assume you have the standard `docker-compose.yml` file. If this is not the case
you might need to make adjustments. For example, older installed might call the container "db" not "database".

:::note
If you are using `docker-compose`, you are using Docker Compose v1, which has been deprecated. Docker Compose commands refer to Docker Compose v2. Consider upgrading your docker setup, see [Migrate to Compose V2](https://docs.docker.com/compose/migrate/)
:::

## Upgrade

1. Create a backup:

   ```bash
   docker compose exec -T database pg_dump -U teslamate teslamate > teslamate_database_$(date +%F_%H-%M-%S).sql
   ```

2. _Check to make sure there are no obvious errors in this backup file._ There should not be any errors appearing
   on screen. The file should be more than 0 bytes long. Do not proceed if there is any doubt.

3. Stop all TeslaMate containers

   ```bash
   docker compose down
   ```

4. Make a copy of your current `docker-compose.yml`

   ```bash
   cp docker-compose.yml docker-compose-16.yml
   ```

5. Update the source to point to a new location that doesn't exist already and update the postgres version.

   ```yaml
   services:
      [...]
      database:
        image: postgres:17
        [...]
        volumes:
          - teslamate-db-17:/var/lib/postgresql/data
   [...]
   volumes:
     teslamate-db-17:
   ```

   Here we updated the image to `postgres:17` and the volume to `teslamate-db-17`.

   :::note
   There are THREE changes. All are very important.
   :::

   :::note
   Do not delete the old volume until you are sure that the database restore is
   working correctly and has all your data.
   :::

6. Start the container.

   ```bash
   docker compose up -d database
   ```

7. Restore the backup.

   :::note
   database should be empty. If database contains data, then check you updated the volume correctly in step 5.
   :::

   Replace `teslamate_database_2025-05-07_07-33-48.sql` with the actual filename generated during the backup step.

   ```bash
   docker compose exec -T database psql -U teslamate teslamate << .
   CREATE SCHEMA public;
   CREATE EXTENSION cube WITH SCHEMA public;
   CREATE EXTENSION earthdistance WITH SCHEMA public;
   .
   DATABASE="teslamate_database_2025-05-07_07-33-48.sql"
   docker compose exec -T database psql -U teslamate -d teslamate < "$DATABASE"
   ```

   There should not be any errors.

8. Start the container.

   ```bash
   docker compose up -d teslamate
   ```

9. Make sure everything is working, and all the data is intact.

## Roll back on error

If you cannot restore the backup for any reason, you might have to roll back to your previous version.

1. Stop everything

   ```bash
   docker compose stop
   ```

2. Restore the values in `docker-compose.yml` that you changed in step 5 and step 6.

   ```bash
   cp docker-compose-16.yml docker-compose.yml
   ```

3. Start everything

   ```bash
   docker compose up -d
   ```
