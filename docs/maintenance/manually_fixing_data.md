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
DELETE FROM drives WHERE id = 9999;
```

## Delete a specific charge

If for some reason a charge was recorded incorrectly, you can delete it manually.

First you need to find out the ID of the charge you want to delete:

- Open the `Charges` dashboard and click on the start date of the charge.
- The URL will contain the drive id, for example `&var-charging_process_id=9999`.

Afterwards run the following query:

```sql
DELETE FROM charging_processes WHERE id = 9999;
```
