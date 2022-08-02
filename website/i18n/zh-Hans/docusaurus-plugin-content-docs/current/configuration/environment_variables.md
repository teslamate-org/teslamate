---
id: environment_variables
title: 环境变量
sidebar_label: 环境变量
---

TeslaMate 接受以下环境变量用于运行时配置：

| 变量名称                          | 描述                                                                                                                                                                                                                                                                                                             | 默认值                        |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| **ENCRYPTION_KEY**                | A key used to encrypt the Tesla API tokens (**required**)                                                                                                                                                                                                                                                        |                               |
| **DATABASE_USER**                 | Username (**required**)                                                                                                                                                                                                                                                                                          |                               |
| **DATABASE_PASS**                 | User password (**required**)                                                                                                                                                                                                                                                                                     |                               |
| **DATABASE_NAME**                 | The database to connect to (**required**)                                                                                                                                                                                                                                                                        |                               |
| **DATABASE_HOST**                 | Hostname of the database server (**required**)                                                                                                                                                                                                                                                                   |                               |
| **DATABASE_PORT**                 | Port of the database server                                                                                                                                                                                                                                                                                      | 5432                          |
| **DATABASE_POOL_SIZE**            | Size of the database connection pool                                                                                                                                                                                                                                                                             | 10                            |
| **DATABASE_TIMEOUT**              | The time in milliseconds to wait for database query calls to finish                                                                                                                                                                                                                                              | 60000                         |
| **DATABASE_SSL**                  | Set to `true` if SSL should be used                                                                                                                                                                                                                                                                              | false                         |
| **DATABASE_IPV6**                 | Set to `true` if IPv6 should be used                                                                                                                                                                                                                                                                             | false                         |
| **VIRTUAL_HOST**                  | Host part used for generating URLs throughout the app                                                                                                                                                                                                                                                            | localhost                     |
| **CHECK_ORIGIN**                  | Configures whether to check the origin header or not. May be `true` (**recommended**), `false` (_default_) or a comma-separated list of hosts that are allowed (e.g. `https://example.com,//another.com:8080`). Hosts also support wildcards. If `true`, it will check against the host value in `VIRTUAL_HOST`. | false                         |
| **PORT**                          | Port where the web interface is exposed                                                                                                                                                                                                                                                                          | 4000                          |
| **HTTP_BINDING_ADDRESS**          | IP address where the web interface is exposed, or blank (_default_) meaning all addresses.                                                                                                                                                                                                                       |                               |
| **DISABLE_MQTT**                  | Disables the MQTT feature if `true`                                                                                                                                                                                                                                                                              | false                         |
| **MQTT_HOST**                     | Hostname of the broker (**required** unless DISABLE_MQTT is `true`)                                                                                                                                                                                                                                              |                               |
| **MQTT_PORT**                     | Port of the broker                                                                                                                                                                                                                                                                                               | 1883 (8883 for MQTT over TLS) |
| **MQTT_USERNAME**                 | Username                                                                                                                                                                                                                                                                                                         |                               |
| **MQTT_PASSWORD**                 | Password                                                                                                                                                                                                                                                                                                         |                               |
| **MQTT_TLS**                      | Enables TLS if `true`                                                                                                                                                                                                                                                                                            | false                         |
| **MQTT_TLS_ACCEPT_INVALID_CERTS** | Accepts invalid certificates if `true`                                                                                                                                                                                                                                                                           | false                         |
| **MQTT_IPV6**                     | Set to `true` if IPv6 should be used                                                                                                                                                                                                                                                                             | false                         |
| **MQTT_NAMESPACE**                | Inserts a custom namespace into the MQTT topic . For example, with `MQTT_NAMESPACE=account_0`: `teslamate/account_0/cars/$car_id/state`.                                                                                                                                                                         |                               |
| **IMPORT_DIR**                    | The path of the directory for the import of data (e.g. TeslaFi)                                                                                                                                                                                                                                                  | ./import                      |
| **TZ**                            | Used to establish the local time zone, e.g. to use the local time in logs. See [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).                                                                                                                                   |                               |
| **DEFAULT_GEOFENCE**              | The default GEOFENCE to send via GEOFENCE if car not in geofence. Overrides the default of "" which will delete any retained value.                                                                                                                                                                              | "" (no quotes)                |