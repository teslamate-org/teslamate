---
title: Using the Official Tesla Fleet API and Telemetry Streaming
---

## Table of Contents

- [Official Tesla APIs](#official-tesla-apis)
    - [Why Tesla Fleet and Telemetry are Needed](#why-tesla-fleet-and-telemetry-are-needed)
    - [Impacts/Limitations of New Endpoints](#impactslimitations-of-new-endpoints)
        - [Tesla Fleet API: no impact](#tesla-fleet-api-no-impact)
        - [Tesla Fleet Telemetry: non compatible by default](#tesla-fleet-telemetry-non-compatible-by-default)
    - [How to Use Tesla APIs](#how-to-use-tesla-apis)
- [Guide for Third-Party Providers](#guide-for-third-party-providers)
    - [MyTeslaMate (free)](#myteslamate-free)
        - [MyTeslaMate Fleet API](#myteslamate-fleet-api)
        - [MyTeslaMate Streaming](#myteslamate-streaming)
    - [Teslemetry (paid)](#teslemetry-paid)
        - [Teslemetry Fleet API](#teslemetry-fleet-api)
        - [Teslemetry Streaming](#teslemetry-streaming)
- [Guide for Official Tesla API](#guide-for-official-tesla-api)
    - [Requirements](#requirements)
    - [Tesla Fleet API](#tesla-fleet-api)
    - [Streaming via Tesla Telemetry](#streaming-via-tesla-telemetry)

## Official Tesla APIs
### Why Tesla Fleet and Telemetry are Needed

By default, TeslaMate uses the _unofficial_ Owner API and streaming.

Tesla now provides official APIs: the Fleet API and the Telemetry API, which replace the Owner API and streaming respectively.

**Migration to the new API depends on your Tesla account type:**

1. **_[Tesla Business Fleet users](https://www.tesla.com/fleet):_** the Owner API is [being shut down](https://developer.tesla.com/docs/fleet-api#2024-03-26-shutting-down-legacy-vehicle-api-endpoints). Fleet vehicles are upgraded gradually and an error message means that they must now use the official API.

1. **_Individual users:_** the Owner API is currently still accessible. Even if it seems to incorporate new limitations similar to those present on the official API.

**Resume: if you are a Tesla Business Fleet user, you should migrate to the official API ASAP!** The official Tesla API will only become mandatory when the Owner API shuts down for all users.

### Impacts/Limitations of New Endpoints

#### Tesla Fleet API: no impact

The [Fleet API](https://developer.tesla.com/docs/fleet-api) is similar to the Owner API but more comprehensive. However, retrieving vehicle information (`vehicle_data`) or sending commands is limited. The limits on the Owner API were historically much higher. It is likely that [these limits](https://developer.tesla.com/docs/fleet-api#membership-levels) will also be applied soon to the API Owner.

#### Tesla Fleet Telemetry: non compatible by default

The [Tesla Fleet Telemetry](https://github.com/teslamotors/fleet-telemetry) differs from the "Owner" streaming. By default, metrics are sent to message queues instead of a websocket as streaming did. Historical streaming could send events every second, whereas Fleet Telemetry will only send information every minute at the minimum.

#### How to Use Tesla APIs

The setup to use the official Tesla APIs ([described below](#tesla-fleet-api)) is complex.
You can use a [third-party providers](#guide-for-third-party-providers) to easily access these APIs.

### Guide for Third-Party Providers

Environment variables allow changing the API and streaming endpoints.
You must use the `URL` and the `TOKEN` given by the third party API provider.

#### [MyTeslaMate](https://www.myteslamate.com) (free)
##### MyTeslaMate Fleet API
1. Log in the [MyTeslaMate](https://app.myteslamate.com) website **with your Tesla account** and go to the [MyTeslaMate Fleet](https://app.myteslamate.com/fleet) page to get your `TOKEN`. 
1. Add the following environment variables (using your `TOKEN` instead of _`xxxx-xxxx-xxxx-xxxx`_):

```yml
# API Fleet
- TOKEN=?token=xxxx-xxxx-xxxx-xxxx
- TESLA_API_HOST=https://api.myteslamate.com
- TESLA_AUTH_HOST=https://api.myteslamate.com
- TESLA_AUTH_PATH=/api/oauth2/v3
```

##### MyTeslaMate Streaming
MyTeslaMate also provides streaming by [reproducing the old streaming from the data sent by Fleet Telemetry](https://github.com/MyTeslaMate/websocket). 

1. You need to "_Pair your vehicle(s)_" on the [fleet](https://app.myteslamate.com/fleet) page
1. Use the following dedicated environment variables:
    ```yml
    - TESLA_WSS_HOST=wss://streaming.myteslamate.com
    - TESLA_WSS_TLS_ACCEPT_INVALID_CERTS=true
    - TESLA_WSS_USE_VIN=true
    ```
1. Restart your instance    

#### [Teslemetry](https://teslemetry.com/pricing) (paid)

##### Teslemetry Fleet API
1. Log in the [Teslemetry website](https://teslemetry.com) and create your `TOKEN`. 
1. Use this `TOKEN` instead of _`xxxx-xxxx-xxxx-xxxx`_ and add the following environment variables:
    ```yml
    - TOKEN=?token=xxxx-xxxx-xxxx-xxxx
    - TESLA_API_HOST=https://api.teslemetry.com
    - TESLA_AUTH_HOST=https://api.teslemetry.com
    - TESLA_AUTH_PATH=/api/oauth2/v3
    ```
1. Restart your instance

##### Teslemetry Streaming
**_Important: no streaming provided by Teslemetry, you MUST disable manually the streaming in Teslamate settings._**

### Guide for official Tesla API


#### Requirements
- A dedicated public hosting
- Advanced IT skills
#### Tesla Fleet API
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

#### Streaming via Tesla Telemetry

**_Important: if you don't setup your own streaming, you MUST disable manually the streaming in Teslamate settings._**

To setup your own streaming server, you can follow these steps:
1. Setup a [Tesla Fleet Telemetry](https://github.com/teslamotors/fleet-telemetry) instance on a public domain (eg: _telemetry.mydomain.com_)
1. Add a [Google pubsub dispatcher](https://github.com/teslamotors/fleet-telemetry?tab=readme-ov-file#backendsdispatchers) to your own GCP PubSub.
1. Setup a [MyTeslaMate Streaming Server from Fleet Telemetry Events](https://github.com/MyTeslaMate/websocket) on a public domain (eg: _streaming.mydomain.com_)
1. Manually create a subscription to the `telemetry_V` created in PubSub by the Tesla Telemetry with:
    - Delivery type: Push
    - Endpoint URL: https://streaming.mydomain.com
1. Update your environment variables:
    ```yml
    - TESLA_WSS_HOST=wss://streaming.mydomain.com
    - TESLA_WSS_TLS_ACCEPT_INVALID_CERTS=true
    - TESLA_WSS_USE_VIN=true
    ```
1. Restart your instance