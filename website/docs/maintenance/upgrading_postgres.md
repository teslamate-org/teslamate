---
title: Upgrading PostgreSQL to a new major version
sidebar_label: Upgrading PostgreSQL
---

1. Create a [backup](backup_restore.mdx)
2. Stop all TeslaMate containers

   ```bash
   docker compose down
   ```

3. Delete the database volume. **Be careful**, this will delete all your previously recorded data! Make sure that your backup can be restored before you start.

   ```bash
   docker volume rm "$(basename "$PWD")_teslamate-db"
   ```

4. Change the postgres version and ensure your volume mount is [configured correctly](https://hub.docker.com/_/postgres#pgdata) in docker-compose.yml and start the container

   ```yml {2}
   database:
     image: postgres:18-trixie
     ...
     volumes:
       - teslamate-db:/var/lib/postgresql
   ```

   ```bash
   docker compose up -d database
   ```

5. [Restore](backup_restore.mdx) the backup
