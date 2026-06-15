# Security Policy

## Security Model

TeslaMate has no built-in authentication; it must be run behind network-level protection
(such as a VPN, Cloudflare Tunnel, Tailscale, Zero Tier and a reverse proxy for portless access
that enforces authentication), as clearly stated in the docs. The network is the trust boundary.

Therefore, reports that any endpoint is reachable without authentication, or that an
exposed port is accessible, are expected behavior and out of scope.

## Reporting a Vulnerability

For reporting a security vulnerability, please contact `security AT teslamate DOT org`.
