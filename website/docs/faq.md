---
title: Frequently Asked Questions
sidebar_label: FAQ
---

## Why are no consumption values displayed in Grafana?

Unfortunately the Tesla API does not return consumption values for a trip. In order to still be able to display values TeslaMate estimates the consumption on the basis of the recorded (charging) data. It takes **at least two** charging sessions before the first estimate can be displayed. Each charging session will slightly improve the accuracy of the estimate, which is applied retroactively to all data.

## What is the geo-fence feature for?

At the moment geo-fences are a way to create custom locations like `🏡 Home` or `🛠️ Work` That may be particularly useful if the addresses (which are provided by [OpenStreetMap](https://www.openstreetmap.org)) in your region are inaccurate or if you street-park at locations where the exact address may vary.

## How do I use my API token instead of my Tesla username/password?

1. Run the following command on any linux/unix console that has curl installed replacing `YOURTESLAEMAIL@DOMAIN.COM` and `YOURPASSWORD` as appropriate:

   ```bash
   $ curl -X POST -H 'Content-Type: application/json' \
          -d '{"grant_type": "password", "client_id": "81527cff06843c8634fdc09e8ac0abefb46ac849f38fe1e431c2ef2106796384", "client_secret": "c7257eb71a564034f9419ee651c7d0e5f7aa6bfbd18bafb5c5c033b093bb2fa3", "email": "YOURTESLAEMAIL@DOMAIN.COM","password": "YOURPASSWORD"}' \
          'https://owner-api.teslamotors.com/oauth/token'
   ```

   Returns:

   ```json
   {
     "access_token": "YOURACCESSTOKEN",
     "token_type": "bearer",
     "expires_in": 3888000,
     "refresh_token": "YOURREFRESHTOKEN",
     "created_at": 1579971894
   }
   ```

2. Connect to the database container:

   ```bash
   docker-compose exec database psql -U teslamate -d teslamate
   ```

   And insert the values from curl into the table `tokens`:

   ```sql
   INSERT INTO tokens
       VALUES(DEFAULT, 'YOURACCESSTOKEN', 'YOURREFRESHTOKEN', NOW(), NOW());
   ```

3. Restart teslamate to pick up new values

   ```bash
   docker-compose restart
   ```

   OR if running in foreground

   ```
   CTRL-C
   docker-compose up
   ```

At this point it should automatically pick up your token and bypass the login screen on the TeslaMate web interface. If it does not look for errors in the logs.
