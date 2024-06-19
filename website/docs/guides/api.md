---
title: Using the Official Tesla Fleet API and Telemetry Streaming
---

## Why Tesla Fleet and Telemetry are Needed

By default, TeslaMate uses the _unofficial_ Owner API and streaming.

Tesla now provides official APIs: the Fleet API and the Telemetry API, which replace the Owner API and streaming respectively.

**Migration to the new API depends on your Tesla account type:**

1. **_Tesla Business Fleet users:_** the Owner API is [being shut down](https://developer.tesla.com/docs/fleet-api#2024-03-26-shutting-down-legacy-vehicle-api-endpoints) for Tesla Business Fleet users. This is done gradually and an error message means that they must now use the official API.

1. **_Individual users:_** the Owner API is currently still accessible. Even if it seems to incorporate new limitations similar to those present on the official API.

**Resume: if you are a Tesla Business Fleet user, you should migrate to the official API ASAP!** The official Tesla API will only become mandatory when the Owner API shuts down for all users.

## Impact/Limitations of New Endpoints

### Tesla Fleet API

The [Fleet API](https://developer.tesla.com/docs/fleet-api) is similar to the Owner API but more comprehensive. However, retrieving vehicle information (`vehicle_data`) is limited to 300 hits per day. The limits on the Owner API were historically much higher.

### Tesla Fleet Telemetry

The [Tesla Fleet Telemetry](https://github.com/teslamotors/fleet-telemetry) differs from the "Owner" streaming. By default, metrics are sent to message queues instead of a websocket as streaming did. Historical streaming could send events every second, whereas Fleet Telemetry will only send information every minute at the minimum.

### How to Use Tesla APIs

The process to use the official Tesla APIs is complex.

You can use a third-party provider to easily access these APIs.

## Guide for Third-Party Providers

Environment variables allow changing the API and streaming endpoints.

You must obtain the `URL` to use for your third-party API calls and the `TOKEN` that serves to identify your calls.

### [MyTeslaMate](https://www.myteslamate.com) (free)
#### MyTeslaMate Fleet API
Log in the [MyTeslaMate](https://app.myteslamate.com) website **with your Tesla account** and go to the [MyTeslaMate Fleet](https://app.myteslamate.com/fleet) page to get your `TOKEN`.

You must use your `TOKEN` instead of _`xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx`_

```yml
# API Fleet
- TOKEN=?token=xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx
- TESLA_API_HOST=https://api.myteslamate.com
- TESLA_AUTH_HOST=https://api.myteslamate.com
- TESLA_AUTH_PATH=/api/oauth2/v3
```

#### MyTeslaMate Streaming
MyTeslaMate also provides streaming by [reproducing the old streaming from the data sent by Fleet Telemetry](https://github.com/MyTeslaMate/websocket). 

You need to "_Pair your vehicle(s)_" on the [fleet](https://app.myteslamate.com/fleet) page and then use the following dedicated environment variables:

```yml
# Streaming from Fleet Telemetry
- TESLA_WSS_HOST=wss://streaming.myteslamate.com
- TESLA_WSS_TLS_ACCEPT_INVALID_CERTS=true
- TESLA_WSS_USE_VIN=true
```

### [Teslemetry](https://teslemetry.com/pricing) (paid)

#### Teslemetry Fleet API
Log in the [Teslemetry website](https://teslemetry.com) and create your `TOKEN`. Use this `TOKEN` instead of _`xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx`_ and add the following environment variables.

```yml
# API Fleet
- TOKEN=?token=xxxxxxxx-xxxxxxxx-xxxxxxxx-xxxxxxxx
- TESLA_API_HOST=https://api.teslemetry.com
- TESLA_AUTH_HOST=https://api.teslemetry.com
- TESLA_AUTH_PATH=/api/oauth2/v3
```

#### Streaming
**_Important: no streaming provided by Teslemetry, you MUST disable manually the streaming in Teslamate settings._**

## Guide for official Tesla API

_This solution requires advanced skills._

### Tesla Fleet API
You can follow the official [Setup documentation](https://developer.tesla.com/docs/fleet-api#setup):
1. Set up a third-party account at [developer.tesla.com](https://developer.tesla.com)
1. Complete registration of an account: you need to share your public key on a public domain (eg: _api.mydomain.com_)
1. Request authorization permissions from a customer: _the generation of tokens usable in Teslamate no longer requires a third-party application as with the Owner API_
4. Send drivers a "Pairing request" to be able to use your own [Tesla Vehicle Command Protocol http proxy to send commands](https://github.com/teslamotors/vehicle-command?tab=readme-ov-file#using-the-http-proxy). 
This proxy must be accessible from your Teslamate instance. You need to host this http proxy on the same domain
1. Add the following environment variable with your own domain :
```yml
# API Fleet
- TESLA_API_HOST=https://api.mydomain.com
```

_Authentication endpoint remains unchanged. Teslamate will take care of the tokens renewal as usual._

### Tesla Streaming

**_Important: if you don't setup the streaming, you MUST disable manually the streaming in Teslamate settings._**

To get your own streaming server, you can follow these steps:
1. Setup a [Tesla Fleet Telemetry](https://github.com/teslamotors/fleet-telemetry) instance on a public domain (eg: _telemetry.mydomain.com_)
1. Add a [Google pubsub dispatcher](https://github.com/teslamotors/fleet-telemetry?tab=readme-ov-file#backendsdispatchers) to your own GCP PubSub.
1. Setup a [Streaming Server from Fleet Telemetry Events](https://github.com/MyTeslaMate/websocket) on a public domain (eg: _streaming.mydomain.com_)
1. Manually create a subscription to the `telemetry_V` PubSub with:
    - Delivery type: Push
    - Endpoint URL: https://streaming.mydomain.com
1. Update your environment variables:

```yml
- TESLA_WSS_HOST=wss://streaming.mydomain.com
- TESLA_WSS_TLS_ACCEPT_INVALID_CERTS=true
- TESLA_WSS_USE_VIN=true
```