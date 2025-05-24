---
title: Unraid Backup and Restore
---

## User Scripts Plugin
Go to the Apps tab and search for the User Scripts plugin and install. The plugin can then be accessed from the Settings menu.

## Backup

In the User Scripts plugin, click the Add New Script button. Give the script a name such as `TeslaMate Backup`

Click the gear icon next to the name and Edit Script.

Copy and paste in the following script:

```bash
#!/bin/bash

# Check if array is started
ls /mnt/disk[1-9]* 1>/dev/null 2>/dev/null
if [ $? -ne 0 ]
then
   echo "ERROR:  Array must be started before using this script"
   exit
fi


BACKUP_DIR="/mnt/user/backups/SQL/postgres17"

databases=`docker exec postgresql17 psql -U teslamate teslamate -l -t | cut -d'|' -f1 | sed -e 's/ //g' -e '/^$/d'`

for db in $databases; do  if [ "$db" != "postgres" ] && [ "$db" != "template0" ] && [ "$db" != "template1" ] && [ "$db" != "template_postgis" ]; then    
    FOLDER=$BACKUP_DIR/$db

    echo "Backing up $db"
    mkdir -p "$FOLDER"

    FILENAME=${db}_$(date +%A).sql
    FILEPATH=$FOLDER/$FILENAME
    docker exec postgresql17 pg_dump --clean -h 127.0.0.1 -U teslamate -d $db > $FILEPATH
    tar czf $FILEPATH.tgz -C $FOLDER $FILENAME
    rm $FILEPATH

    fi
done

find $BACKUP_DIR/ -type f -name '*.tgz' -mtime +7 -exec rm {} \;
```

:::note
Change the `BACKUP_DIR` path to a share on your server where you want to save backups. Make sure you have the mover settings configured correctly on your share or also have some other backup process for these files since they are still on your server.
:::

:::note
If you changed `DB_USER` in the template from one of the advanced guides, make sure to replace the first instance of `teslamate` and again after the -U in in the above command.
:::

Click **RUN SCRIPT** to test and verify that it works. If you are satisfied, you can select Scheduled Daily from the drop down to run the cron job every day and create a backup file every day with the day of the week in the file name. Make sure to the click **Run in Background**


## Restore

1. Mannually stop all TeslaMate docker conatiners (TeslaMate-Grafana, TeslaMate).
2. In the User Scripts plugin, click the Add New Script button. Give the script a name such as `TeslaMate Restore`
3. Click the gear icon next to the name and Edit Script.
4. Copy and paste the folliwng script

```bash
#!/bin/bash

# Define backup directory
BACKUP_DIR="/mnt/user/backups/SQL/postgres15"
DB_CONTAINER="postgresql17"
DB_NAME="teslamate"
DB_USER="teslamate"

# Check if array is started
ls /mnt/disk[1-9]* 1>/dev/null 2>/dev/null
if [ $? -ne 0 ]; then
  echo "ERROR: Array must be started before using this script"
  exit 1
fi

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
  echo "ERROR: Backup directory $BACKUP_DIR does not exist"
  exit 1
fi

# Find the most recent backup
echo "Finding the most recent backup..."
SELECTED_BACKUP=$(find "$BACKUP_DIR" -type f -name '*.tgz' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$SELECTED_BACKUP" ]; then
  echo "No backups found."
  exit 1
fi

echo "Selected backup: $SELECTED_BACKUP"

# Create a temporary directory for restore
TMP_DIR=$(mktemp -d)

echo "Extracting backup..."
tar xzf "$SELECTED_BACKUP" -C "$TMP_DIR"
SQL_FILE=$(find "$TMP_DIR" -name '*.sql')

if [ ! -f "$SQL_FILE" ]; then
  echo "ERROR: SQL file not found after extracting backup."
  rm -r "$TMP_DIR"
  exit 1
fi

# Stop the application container to avoid conflicts
echo "Stopping TeslaMate container..."
docker stop teslamate

# Drop and recreate public schema
echo "Resetting database..."
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" "$DB_NAME" <<SQL
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
CREATE EXTENSION cube WITH SCHEMA public;
CREATE EXTENSION earthdistance WITH SCHEMA public;
SQL

if [ $? -ne 0 ]; then
  echo "ERROR: Database reset failed. Aborting restore."
  docker start teslamate
  rm -r "$TMP_DIR"
  exit 1
fi

# Restore the backup
echo "Restoring backup..."
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" "$DB_NAME" < "$SQL_FILE"

# Restart the application container
echo "Starting TeslaMate container..."
docker start teslamate

# Clean up
rm -r "$TMP_DIR"

echo "Restore completed successfully."
```
:::note
Replace the `BACKUP_DIR` value with the value defined in the previous backup file.
:::

:::note
Replace the `DB_CONTAINER` value with the name of the container you want the restore to go **to**.
:::

:::note
Replace the default `teslamate` value below with the value defined in the template if you have one (DB_USER and DB_NAME)
:::

5. Click **RUN SCRIPT**

## Postgres Upgrade
1. Run the Backup script (optional)
2. Go to the Apps tab and search for the latest postgres version and install a new container instance. Then shut it down.
3. Edit the Restore script `DB_CONTAINER` with the name of the new postgres container you just installed and specify the `BACKUP_DIR`
4. Click RUN SCRIPT
5. Select the backup file you want to restore.
6. Start the new postgres, TeslaMate, and TeslaMate-Grafana containers and verify that your data is correct.
7. When you are certain everything is working good you can delete the old postgres container and image (optional)
