# Multi-Tenancy Configuration

_Note: This document is a work in progress and is subject to ongoing testing. If you have feedback or suggestions on this topic, please feel free to provide the feedback via GitHub_

## Introduction

This document covers a number of approaches to multi-tenancy for TeslaMate installations. The TeslaMate application doesn't integrate a mechanism for multi-user access, however there are approaches which would offer a lightweight

### Manual Installation

Using a Manual Installation is the lightweight approach to TeslaMate multi-tenancy. In this configuration:

- We install one PostgreSQL server for all TeslaMate instances. This PostgreSQL server listens locally on a single port, is accessible to TeslaMate and Grafana, and contains all of the individual tenant's data.
  - As users do not connect directly to the PostgreSQL database for any reason and do not have permissions to modify data sources in Grafana, there is no need to configure any complex authentication. Each tenant can have a database name, username and password assigned.
- We install one Grafana server for all TeslaMate instances. We use a feature called Organizations to allow different users to access only their database.
- We install one TeslaMate server for each TeslaMate instance. This server will listen on a unique TCP port, and is best implemented using a reverse-proxy.

### Docker Installation

Using Docker, each individual tenancy will have its own Grafana, TeslaMate and PostgreSQL instances. This provides the highest level of separation between instances and allows each to be entirely encapsulated, however it results in higher resource utilization than the Manual Installation Method.

To use Docker multi-tenancy, no additional configuration outside of the assigning of unique port numbers for TeslaMate, Grafana and MQTT Broker are required. The database server port is not exposed and therefore does not require a unique port allocation.
