# Manually fixing data

## Docker: Connect to the database container

When using TeslaMate with Docker, you must first connect to the **running** database container before queries can be executed.

```bash
docker-compose exec database psql teslamate teslamate
```

## Delete a specific drive

If for some reason a drive was recorded incorrectly, you can delete it manually.

First you need to find out the ID of the drive you want to delete:

- Open the `Drives` dashboard and click on the start date of the drive.
- The URL will contain the drive id, for example `&var-drive_id=9999`.

Afterwards run the following query:

```sql
BEGIN;
UPDATE drives SET start_position_id = NULL, end_position_id = NULL WHERE id = 9999;
DELETE FROM positions WHERE drive_id = 9999;
DELETE FROM drives WHERE id = 9999;
COMMIT;
```
