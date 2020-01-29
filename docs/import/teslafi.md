# Import from TeslaFi (BETA)

## Requirements

- **CREATE A [BACKUP](../maintenance/backup_restore.html) OF YOUR DATA!**

- If you have been using TeslaMate prior to the release of version 1.16, the [docker-compose.yml](../installation/docker.html) needs to be updated. Add the following volume mapping to the `teslamate` service:

  ```YAML
  services:
    teslamate:
      # ...
      volumes:
        - ./import:/opt/app/import
  ```

- Export your TeslaFi data as CSV by month: `Settings -> Account -> "Download TeslaFi Data"`

## Instructions

1. Copy the exported CSV files into a **directory named `import`\*** next to the _docker-compose.yml_
2. **Restart** the teslamate service and open the TeslaMate admin interface. Now the import form should be displayed instead of the vehicle summary.
3. Since the raw data is in the local timezone (assigned by the home address in the TeslaFi settings page) you need to **select your local timezone**. Then start the import.
4. On low-end hardware like the Raspberry Pi the import may take multiple hours, depending on the amount of data. If there is an overlap between the already existing TeslaMate and TeslaFi data, only the data prior to the first TeslaMate data will be imported. After the import is complete, remove or **empty the `import` directory** and **restart** the `teslamate` service.

Since the exported CSV files do not contain addresses, they are added automatically afterwards. So please note that not all addresses are visible immediately after the import/restarting. Depending on the amount of data imported, it may take a while before they appear. The same applies to elevation data.

_\* The path of the import directory can be customized via the [`IMPORT_DIR` environment variable](../configuration/environment_variables.html)._
