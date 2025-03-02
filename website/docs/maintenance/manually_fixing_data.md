---
title: Manually fixing data
---

:::note
If you are using `docker-compose`, you are using Docker Compose v1, which has been deprecated. Docker Compose commands refer to Docker Compose v2. Consider upgrading your docker setup, see [Migrate to Compose V2](https://docs.docker.com/compose/migrate/)
:::

## Get the ID

First you need to find out the ID of the drive or charge:

import Tabs from "@theme/Tabs";
import TabItem from "@theme/TabItem";

<Tabs
defaultValue="drive"
groupId="type"
values={[
    { label: 'Drive', value: 'drive', },
    { label: 'Charge', value: 'charge', },
]}>
<TabItem value="drive">

- Open the `Drives` dashboard and click on the start date of the drive.
- The URL will contain the drive ID, for example `&var-drive_id=9999`.

</TabItem>
<TabItem value="charge">

- Open the `Charges` dashboard and click on the start date of the charge.
- The URL will contain the charge id, for example `&var-charging_process_id=9999`.

</TabItem>
</Tabs>

## Terminate a drive or charge

If for some reason a drive or charge hasn't been fully recorded, for example due to a bug or an unexpected restart, you can terminate it manually. Among other things, this assigns an end date to the drive/charge.

Replace `9999` with the actual ID then run the command while the TeslaMate container is running:

<Tabs
defaultValue="drive"
groupId="type"
values={[
    { label: 'Drive', value: 'drive', },
    { label: 'Charge', value: 'charge', },
]}>
<TabItem value="drive">

```bash
docker compose exec teslamate bin/teslamate rpc \
    "TeslaMate.Repo.get!(TeslaMate.Log.Drive, 9999) |> TeslaMate.Log.close_drive()"
```

</TabItem>
<TabItem value="charge">

```bash
docker compose exec teslamate bin/teslamate rpc \
    "TeslaMate.Repo.get!(TeslaMate.Log.ChargingProcess, 9999) |> TeslaMate.Log.complete_charging_process()"
```

</TabItem>
</Tabs>

## Delete a drive or charge

If for some reason a drive or charge was recorded incorrectly, you can delete it.

1.  Attach to the **running** database container:

    ```bash
    docker compose exec database psql teslamate teslamate
    ```

    :::note
    If you get the error `No such service: database`, update your _docker-compose.yml_ or use `db` instead of `database` in the above command.
    :::

2.  Afterwards replace `9999` with the actual ID then run the query:

        <Tabs

    defaultValue="drive"
    groupId="type"
    values={[
    { label: 'Drive', value: 'drive', },
    { label: 'Charge', value: 'charge', },
    ]}>

    <TabItem value="drive">

        ```sql
        DELETE FROM drives WHERE id = 9999;
        ```

        </TabItem>

    <TabItem value="charge">

        ```sql
        DELETE FROM charging_processes WHERE id = 9999;
        ```

        </TabItem>

    </Tabs>

## Remove a vehicle from the database

**NOTE:** Always [backup](https://docs.teslamate.org/docs/maintenance/backup_restore "backup") your data before performing any database changes.

1. Connect to your running TeslaMate database

   ```bash
   docker compose exec database psql teslamate teslamate
   ```

   :::note
   If you get the error `No such service: database`, update your _docker-compose.yml_ or use `db` instead of `database` in the above command.
   :::

2. Identify the right car ID in the database to remove

```sql
SELECT id, vin FROM cars;
```

3. Based upon the output, run the following command replacing `num` with the ID from the previous command.

```sql
DELETE FROM cars WHERE id = num;
DELETE FROM car_settings WHERE id = num;
DELETE FROM charging_processes WHERE car_id = num;
DELETE from charges WHERE charging_process_id in (select id from charging_processes where car_id = num);
DELETE FROM drives WHERE car_id = num;
DELETE FROM positions WHERE car_id = num;
DELETE FROM states WHERE car_id = num;
DELETE FROM updates WHERE car_id = num;
```

## Reindex Database

**NOTE:** If your database experiences a lot of updates or deletions, like importing data from other sources or deleting a loaner car or some other similar situation, you might encounter index bloat, which can degrade performance. In such cases, reindexing could be beneficial.

In summary, you don't necessarily need to run REINDEX periodically unless your database workload involves significant amounts of updates and deletions, if so, you may you may proceed as indicated in the following steps:

1. Connect to your running TeslaMate database

   ```bash
   docker compose exec -T database psql teslamate teslamate
   ```

   :::note
   If you get the error `No such service: database`, update your _docker-compose.yml_ or use `db` instead of `database` in the above command.
   :::

2. Run the following script (copy and paste)

   ```sql
   DO $$
   DECLARE
       t text;
   BEGIN
       FOR t IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND    table_name IS NOT NULL)
       LOOP
           EXECUTE 'REINDEX TABLE public.' || t;
       END LOOP;
   END $$;
   ```

3. Exit the prompt by typing:

   ```bash
   \q  (or press CTRL + C)
   ```
