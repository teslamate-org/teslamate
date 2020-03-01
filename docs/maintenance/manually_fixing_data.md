# Manually fixing data

## Get the ID

First you need to find out the ID of the drive or charge:

### Drive

- Open the `Drives` dashboard and click on the start date of the drive.
- The URL will contain the drive id, for example `&var-drive_id=9999`.

### Charge

- Open the `Charges` dashboard and click on the start date of the charge.
- The URL will contain the charge id, for example `&var-charging_process_id=9999`.

## Terminate a drive or charge

If for some reason a drive or charge hasn't been fully recorded, for example due to a bug or an unexpected restart, you can terminate it manually. Among other things, this assigns an end date to the drive/charge.

Replace `9999` with the actual ID then run the command while the TeslaMate container is running:

### Drive

```bash
docker-compose exec teslamate bin/teslamate rpc "TeslaMate.Repo.get!(TeslaMate.Log.Drive, 9999) |> TeslaMate.Log.close_drive()"
```

### Charge

```bash
docker-compose exec teslamate bin/teslamate rpc "TeslaMate.Repo.get!(TeslaMate.Log.ChargingProcess, 9999) |> TeslaMate.Log.complete_charging_process()"
```

## Delete a drive or charge

If for some reason a drive or charge was recorded incorrectly, you can delete it.

When using TeslaMate with Docker, you must first attach to the **running** database container before queries can be executed:

```bash
docker-compose exec database psql teslamate teslamate
```

Afterwards replace `9999` with the actual ID then run the query:

### Drive

```sql
DELETE FROM drives WHERE id = 9999;
```

### Charge

```sql
DELETE FROM charging_processes WHERE id = 9999;
```
