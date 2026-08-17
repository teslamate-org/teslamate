---
title: Generating Tokens
sidebar_label: Tokens
---

## Types of tokens

There are two types of tokens:

- Tokens that only work for the unofficial owners API.
- Tokens that only work with the [fleet API](../configuration/api.md).

As by default Teslamate uses the owners API, this page will show you
how to obtain the first type of token.

## How to generate your own tokens

Teslamate does not have built in support for creating the initial token. This
is because the code required to do this requires regular updates to keep it working
properly.

There are multiple apps available to securely generate access tokens yourself, for example:

- [Tesla Auth 0.13.0 or newer (macOS, Linux, Windows)](https://github.com/adriankumpf/tesla_auth/releases/latest)
- [Auth app for Tesla (iOS, macOS)](https://apps.apple.com/us/app/auth-app-for-tesla/id1552058613)

Tesla Auth is available in NixOS, currently nixos-unstable:

```bash
nix shell 'github:nixos/nixpkgs/nixos-unstable#tesla_auth'
```
