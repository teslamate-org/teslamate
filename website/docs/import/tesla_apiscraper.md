---
title: Import from tesla-apiscraper (BETA)
sidebar_label: tesla-apiscraper
---

This is a multi-step process to export your data from a [tesla-apiscraper](https://github.com/lephisto/tesla-apiscraper) InfluxDB backend, convert it to a format that can be imported into TeslaMate (specifically TeslaFi CSV) while fixing up some typical data glitches the scraper produces, and then import it.

## Requirements

- A copy of the data stored by `tesla-apiscraper` - specifically the `/opt/apiscraper/influxdb` folder mounted in the standard apiscraper Docker configuration. **Create a backup of this** before attempting the export and conversion, just in case.

- A system running Docker with sufficient RAM for InfluxDB to perform the CSV export. This does **not** need to be the same machine where API Scraper and/or TeslaMate was/is running - you can do the export and conversion on your PC/Mac. The important thing is to give the Docker machine more than 2GB of RAM, otherwise the InfluxDB export may fail.

- **CREATE A [BACKUP](../maintenance/backup_restore.md) OF YOUR DATA** before attempting to import anything into TeslaMate. This is all highly experimental and has only been successfully done once :)

## Instructions

:::note Troubleshooting
All of this is experimental and has not been extensively tested. If you encounter an error during Part 1 or Part 2, please create an issue in the [tesla-apiscraper-to-teslafi-export](https://github.com/olexs/tesla-apiscraper-to-teslafi-export) project on GitHub, since it's not directly related to TeslaMate.
:::

### Part 1: Exporting the API Scraper InfluxDB data into CSV

1. Download or clone the [tesla-apiscraper-to-teslafi-export](https://github.com/olexs/tesla-apiscraper-to-teslafi-export) repository into a folder on your machine.

2. Place the `tesla-apiscraper` data folder _contents_ (_data_, _meta_ and _wal_ folders) into the `influxdb-data` folder, next to the `influxdb-export.sh` file. The folder structure must look like this:

   ```console
   .
   ├── influxdb-export.sh
   ├── influxdb-export.bat
   ├── (other stuff)
   └── influxdb-data
       ├── README.md
       ├── data
       ├── meta
       └── wal
   ```

3. Run the `influxdb-export.sh` script (or `influxdb-export.bat` if you're on Windows). You may need to `sudo` it / run it in an Administrator command line prompt if your Docker install needs root. It will do the following:

   - Create the `influxdb-csv` output folder, if it doesn't exist yet
   - Start an InfluxDB Docker container with the `influxdb-data` and `influxdb-csv` folders mounted (on Windows, you may need to allow your Docker to access the drive you are working on for the mounts to work)
   - Wait for the container to report as _healthy_
   - Execute the export commands for all data stored by apiscraper, putting the CSV files inside the `influxdb-csv` folder
   - Stop and delete the InfluxDB container

   This may take a little while. After the process has finished, if there are no errors reported, continue with the next part of the instructions.

### Part 2: Converting exported InfluxDB CSV files to TeslaFi CSV

1. Obtain your Tesla's **vehicle ID** number. It's a 10- or 11-digit number that uniquely identifies your car, and is part of the TeslaFi data format, but it's not included in tesla-apiscraper data - so you need to source it separately. There are several ways you can get it:

   - Manually using the Tesla API. The number is listed under `vehicle_id` in the `vehicles` response, as documented here: [https://tesla-api.timdorr.com/api-basics/vehicles](https://tesla-api.timdorr.com/api-basics/vehicles).
   - From the database of another Tesla API tracker you're already using, such as TeslaMate (**docker compose exec database psql teslamate teslamate -c 'select vid from cars;'**).

2. Run the `teslafi-convert.sh` script (or `teslafi-convert.bat` if you're on Windows). You may need to `sudo` it / run it in an Administrator command line prompt if your Docker install needs root. It will do the following:

   - Create the `teslafi-csv` output folder, if it doesn't exist yet
   - Build and start a Docker container with the `converter` app and its few dependencies, with the `influxdb-csv` and `teslafi-csv` folders mounted (on Windows, you may need to allow your Docker to access the drive you are working on for the mounts to work)
   - Ask you for the vehicle ID mentioned above
   - Process the CSV files in the `influxdb-csv` folder. This may take a couple minutes. Progress is displayed as the converter works its way through the files
   - Stop and delete the Docker container

   The finished TeslaFi-compatible CSV files are now located in the `teslafi-csv` folder.

### Part 3: Importing the processed CSV data into TeslaMate

- Proceed with the [TeslaFi import](teslafi.md) steps using the CSV files you just created.

