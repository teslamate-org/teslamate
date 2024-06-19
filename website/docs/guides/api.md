---
title: Using the new Tesla Fleet API and Telemetry streaming
---

## Why Tesla Fleet and Telemetry should be needed?

By default, TeslaMate uses the  _unofficial_ Owner API and streaming.

Tesla now provides official APIs: the Fleet API and the Telemetry API, which replace the Owner API and streaming respectively.

If the Owner API stops working, the Fleet API will become the only alternative.

## Impact/limitations of new endpoints

### Tesla Fleet API

The [Fleet API](https://developer.tesla.com/docs/fleet-api) is similar to the Owner API but more comprehensive. However, retrieving vehicle information (`vehicle_data`) is limited to 300 hits per day. The limits on the Owner API were historically much higher.

### Tesla Telemetry

The [Tesla Telemetry](https://github.com/teslamotors/fleet-telemetry) differs from the "Owner" streaming. By default, metrics are sent to message queues instead of a websocket as streaming did. Historical streaming could send events every second, whereas Telemetry will only send information every minute at the minimum.

### How to use Tesla APIs?

To use the official Tesla APIs, you need to create a [Tesla developer account](https://developer.tesla.com/), register an application, and follow a process that requires advanced skills and specific hosting.

To easily access these APIs, you can use a third-party provider.

## Guide for third-party

Environment variables allow changing the API and streaming endpoints.

You must obtain the `URL` to use for your third-party API calls and the `TOKEN` that serves to identify your calls.

### [MyTeslaMate](https://www.myteslamate.com) (free)

Simply log in with your Tesla account and go to the [MyTeslamate Fleet](https://app.myteslamate.com/fleet) page to get your `TOKEN`.

You must use your `TOKEN` instead of _`xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx`_

```yml
# API Fleet
- TOKEN=?token=xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx
- TESLA_API_HOST=https://api.myteslamate.com
- TESLA_AUTH_HOST=https://api.myteslamate.com
- TESLA_AUTH_PATH=/api/oauth2/v3
```

MyTeslaMate also provides streaming by [reproducing the old streaming from the data sent by Telemetry](https://github.com/MyTeslaMate/websocket). 

You need to "_Pair your vehicle(s)_" on the [MyTeslamate Fleet](https://app.myteslamate.com/fleet) page and then use dedicated environment variables :

```yml
# Streaming from Telemetry
- TESLA_WSS_HOST=wss://streaming.myteslamate.com
- TESLA_WSS_TLS_ACCEPT_INVALID_CERTS=true
- TESLA_WSS_USE_VIN=true
```

### Teslemetry ($)

You must use your `TOKEN` instead of _`xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx`_ and add the following environment variables.

_No streaming given, you must disable the streaming in Teslamate settings._

```yml
# API Fleet
- TOKEN=?token=xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx
- TESLA_API_HOST=https://api.teslemetry.com
- TESLA_AUTH_HOST=https://api.teslemetry.com
- TESLA_AUTH_PATH=/api/oauth2/v3
```

## Guide for Tesla API

_TODO_