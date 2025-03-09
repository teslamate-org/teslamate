---
title: Import from TeslaFi (BETA)
sidebar_label: TeslaFi
---

## Requirements

- **CREATE A [BACKUP](../maintenance/backup_restore.md) OF YOUR DATA‼️**

- If you have been using TeslaMate since before the 1.16 release, the [docker-compose.yml](../installation/docker.md) needs to be updated. Add the following volume mapping to the `teslamate` service:

  ```yml {4-5}
  services:
    teslamate:
      # ...
      volumes:
        - ./import:/opt/app/import
  ```

- Export your TeslaFi data (for one car) as CSV by month: `Settings -> Advanced -> Download TeslaFi Data`.

<details>
  <summary>If you have a ton of TeslaFi data and don't want to deal with the UI, you can run this python script to export all data</summary>

```python
# https://gist.github.com/TheLinuxGuy/e8c85e59226014087159c5d36c0a1272
import requests
import csv
from io import StringIO
from lxml.html import fromstring

username = 'username'
password = 'password'
years = [2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025] # array of years you want to export
months = [1,2,3,4,5,6,7,8,9,10,11,12] # I assume all the months, up to you
cookie = ''

# Set the proper delimiter
CSV_DELIMITER = ','

def login():
    url = "https://teslafi.com/userlogin.php"
    response = requests.request("GET", url, headers={}, data={})

    cookies = ""
    for key in response.cookies.keys():
        this_cookie = key + "=" + response.cookies.get(key)
        if cookies == "":
            cookies = this_cookie
        else:
            cookies += "; " + this_cookie

    token = fromstring(response.text).forms[0].fields['token']
    global cookie
    cookie = cookies
    payload = {'username': username,'password': password,'remember': '1','submit': 'Login','token': token}
    headers = {"Cookie": cookies}
    l = requests.request("POST", url, headers=headers, data=payload)
    return True

def getdata(m,y):
    url = "https://teslafi.com/exportMonth.php"
    headers = {'Content-Type': 'application/x-www-form-urlencoded','Cookie': cookie}
    response = requests.request("POST", url, headers=headers, data=pl(m,y))
    return response

def detect_delimiter(text):
    """Detects the most likely delimiter in the CSV data"""
    if not text or '\n' not in text:
        return ','

    # Sample the first line to detect delimiter
    first_line = text.split('\n', 1)[0]
    delimiters = [(',', first_line.count(',')),
                 (';', first_line.count(';')),
                 ('\t', first_line.count('\t'))]

    # Sort by frequency, highest first
    delimiters.sort(key=lambda x: x[1], reverse=True)

    # Return the most common delimiter, or comma if none found
    return delimiters[0][0] if delimiters[0][1] > 0 else ','

def normalize_battery_level(rows, header):
    """
    Normalize battery_level values to integers without decimal points:
    - Always convert to integer representation
    - If decimal part < 0.50, round down
    - If decimal part >= 0.50, round up

    Args:
        rows: List of CSV rows (lists)
        header: List of column names

    Returns:
        Tuple of (modified_rows, normalization_count)
    """
    # Find the index of the battery_level column
    try:
        battery_level_index = header.index('battery_level')
    except ValueError:
        # If battery_level column doesn't exist, return original rows
        return rows, 0

    normalization_count = 0

    # Iterate through all rows
    for i, row in enumerate(rows):
        # Skip if row is too short or battery_level is empty
        if len(row) <= battery_level_index or not row[battery_level_index].strip():
            continue

        try:
            # Try to convert the battery_level to a float
            value = float(row[battery_level_index])

            # Get the integer value (either rounded up or down based on decimal part)
            if value - int(value) < 0.5:
                new_value = int(value)  # Round down
            else:
                new_value = int(value) + 1  # Round up

            # Convert to string representation of integer
            new_value_str = str(new_value)

            # Only count as normalization if we actually changed the value
            if row[battery_level_index] != new_value_str:
                row[battery_level_index] = new_value_str
                normalization_count += 1

        except (ValueError, TypeError):
            # Skip if conversion fails
            continue

    return rows, normalization_count

def savefile(response, m, y):
    try:
        # Detect what delimiter the API is using
        input_delimiter = detect_delimiter(response.text)

        # Read the CSV data with the detected delimiter
        csv_data = StringIO(response.text)
        reader = csv.reader(csv_data, delimiter=input_delimiter)
        rows = list(reader)

        # Extract the header and data rows
        if not rows:
            print(f"Skipped creating {fname(m,y)} for year {y} and month number {m} due to lack of data from TeslaFi.")
            return

        header = rows[0]
        data_rows = rows[1:]

        # Check if there are any data rows
        if not data_rows:
            print(f"Skipped creating {fname(m,y)} for year {y} and month number {m} due to lack of data from TeslaFi.")
            return

        # Normalize battery_level values
        normalized_rows, normalization_count = normalize_battery_level(data_rows, header)

        # If normalizations occurred, show only the summary
        if normalization_count > 0:
            print(f"Detected `battery_level` column malformed, {normalization_count} rows of data have been autocorrected")

        # Write the standardized CSV with the correct delimiter
        with open(fname(m,y), "w", newline='', encoding='utf-8') as file:
            writer = csv.writer(file, delimiter=CSV_DELIMITER, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(header)
            writer.writerows(normalized_rows)

        print(f"Saved: {fname(m,y)}")

    except Exception as e:
        print(f"Error processing CSV: {str(e)}")
    return

def fname(m,y):
    return("TeslaFi" + str(m) + str(y) + ".csv")

def pl(m,y):
    url = 'https://teslafi.com/export2.php'
    response = requests.request("GET", url, headers={"Cookie": cookie})
    magic = fromstring(response.text).forms[0].fields['__csrf_magic']
    return('__csrf_magic=' + magic + '&Month=' + str(m) + '&Year=' + str(y))

def go():
    login()
    for year in years:
        for month in months:
            print(f"Processing: {month}/{year}")
            d = getdata(month, year)
            savefile(d, month, year)

go()
```

</details>

## Instructions

1. Copy the exported CSV files (in the format "TeslaFixxxxxx.csv") into a **directory named `import`** next to the _docker-compose.yml_:

   ```console
   .
   ├── docker-compose.yml
   └── import
       ├── TeslaFi82019.csv
       ├── TeslaFi92019.csv
       ├── TeslaFi102019.csv
       ├── TeslaFi112019.csv
       └── TeslaFi122019.csv
   ```

   :::tip
   The path of the import directory can be customized with the **IMPORT_DIR** [environment variable](../configuration/environment_variables.md).
   :::

2. **Restart** the teslamate service and open the TeslaMate admin interface. Now the import form should be displayed instead of the vehicle summary.
3. Since the raw data is in the local timezone (assigned by the home address in the TeslaFi settings page) you need to **select your local timezone**. Then start the import. On low-end hardware like the Raspberry Pi, importing a large data set spanning several years will take a couple of hours.
4. After the import is complete, **empty the `import` directory** (or remove but ensure docker doesn't have a volume mapping) and **restart** the `teslamate` service.

:::note
If there is an overlap between the already existing TeslaMate and TeslaFi data, only the data prior to the first TeslaMate data will be imported.
:::

:::note
If the CSV files are missing the vehicle ID, the imported will default to `1`. You can alter this behavior by setting the environment variable `TESLAFI_IMPORT_VEHICLE_ID`.
:::

:::note
Since the exported CSV files do not contain addresses, they are added automatically during and after the import. So please note that not all addresses are visible immediately after the import/restarting. Depending on the amount of data imported, it may take a while before they appear. The same applies to elevation data.
:::
