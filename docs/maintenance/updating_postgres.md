# Updating Postgres

1. Create a [backup](backup_restore.html)
2. Stop all TeslaMate containers

   ```bash
   docker-compose down
   ```

3. Delete the database volume. **Be careful**, this will delete all your previously recorded data! Make sure that your backup can be restored before you start.

   ```bash
   docker volume rm teslamate_teslamate-db
   ```

4. Change the postgres version in docker-compose.yml and start the container

   ```bash
   docker-compose up -d
   ```

5. [Restore](backup_restore.html) the backup
