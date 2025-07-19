---
title: NixOS install
sidebar_label: NixOS
---

This document provides the necessary steps for installation of TeslaMate on [NixOS](https://nixos.org/).

This setup is recommended only if you are running TeslaMate **on your home network**, as otherwise your Tesla API tokens might be at risk.

If you intend to access TeslaMate from the Internet, the recommended way is to use a secure connection (such as a VPN, Cloudflare Tunnel, Tailscale, Zero Tier and a reverse proxy for portless access like [Caddy](https://nixos.wiki/wiki/Caddy)) for secured access to your TeslaMate instance outside your home network.
Alternatively, you can use a reverse proxy (such as Traefik or [Caddy](https://nixos.wiki/wiki/Caddy)) with appropriate hardening to secure your TeslaMate instance before expose it to the internet.

## Requirements

- NixOS _(if you are new to NixOS, see [NixOS getting started](https://nixos.org/learn/))_
- A Machine that's always on, so TeslaMate can continually fetch data
- At least 1 GB of RAM on the machine for the installation to succeed. It is recommended to have at least 2 GB of RAM for optimal operation.
- External internet access, to talk to tesla.com

## Instructions

We provide a flake module that can be used to install TeslaMate on NixOS. To use it, you need to have Nix flakes enabled. If you don't have them enabled yet, follow the [NixOS documentation](https://nixos.wiki/wiki/Flakes).

The options for the module are documented in the [module.nix](https://github.com/teslamate-org/teslamate/blob/48fb4fa2675ed742bf1b125a784dbbbcb1aceb24/nix/module.nix).

In the `inputs` section of your flake add:

```nix
teslamate.url = "github:teslamate-org/teslamate/main";
```

If you would like to pin to a specific version, you can do so for example like this:

```nix
teslamate.url = "github:teslamate-org/teslamate?rev=c37638b320e0beea97c5d51fea51cd9fdbd07ce0"; # v2.0.0
```

If you have a MCU2 upgraded car, you can use the following URL instead to get the latest version of TeslaMate that supports MCU2 upgraded cars (improved sleeping behavior for MCU2 upgraded cars):

```nix
teslamate.url = "github:teslamate-org/teslamate/mcu2-upgraded-cars";
```

To enable the TeslaMate service, your config could look like this (note: this will conflict with any existing PostgreSQL/Grafana servers, because NixOS modules do not support multiple instances).

```nix
{
  config,
  lib,
  inputs,
  ...
}:
{
imports = [ inputs.teslamate.nixosModules.default ];

config = services.teslamate = {
      enable = true;
      secretsFile = "/run/secrets/teslamate.env"; # you can use agenix for sure: config.age.secrets.teslamateEnv.path;
      # the secrets file must contain at least:
      #  - `ENCRYPTION_KEY` - encryption key used to encrypt database
      #  - `DATABASE_PASS` - password used to authenticate to database
      #  - `RELEASE_COOKIE` - unique value used by elixir for clustering
      autoStart = true;
      listenAddress = "127.0.0.1";
      port = 4000;
      virtualHost = "$[your-domain]";
      urlPath = "/";

      postgres = {
        enable_server = true;
        user = "teslamate";
        database = "teslamate";
        host = "127.0.0.1";
        port = 5432;
      };

      grafana = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = 3000;
        urlPath = "/";
      };

      mqtt = {
        enable = true;
        host = "127.0.0.1";
        port = 1883;
      };
    };
}
```

If you want to use the TeslaMate web interface via a reverse proxy, you can use the following snippet if you have already Caddy service running:

```nix
{
    services.caddy.virtualHosts."[your-sub-domain for TeslaMate]" = {
      useACMEHost = "[your-baseDomain]";
      extraConfig = ''
        reverse_proxy http://127.0.0.1:4000
      '';
    };

    services.caddy.virtualHosts."[your-sub-domain for grafana]" = {
      useACMEHost = "[your-baseDomain]";
      extraConfig = ''
        reverse_proxy http://127.0.0.1:3000
      '';
    };
}
```
