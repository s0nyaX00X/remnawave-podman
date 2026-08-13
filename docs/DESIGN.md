# Design

This repo is a minimalist Podman deployment of Remnawave Panel and Node with a
default **VLESS + XHTTP + TLS** profile. Caddy terminates TLS everywhere; Xray has no
TCP listener on the node.

## Decisions

### Panel

`remnawave/backend:3`, `postgres:18.4`, and `valkey/valkey:9-alpine` run on the compose
bridge network. Backend and database host ports are bound to `127.0.0.1` only, as the
Remnawave docs require. Valkey uses a Unix socket (`/var/run/valkey/valkey.sock`)
shared through a named volume with the backend. Caddy fronts the backend, performs
ACME for `PANEL_DOMAIN`, and reverse-proxies to `remnawave:3000`, which serves both the
UI and `/api/sub`.

### Node: Unix socket + Caddy decoy

`remnawave/node:latest` runs with `network_mode: host` and only `NODE_PORT` +
`SECRET_KEY`. The Xray VLESS-XHTTP inbound listens on
`unix:/var/run/remnawave/xray.sock` (port field stays `443` only to satisfy schema
validators; Xray opens no TCP port for a unix listener). Caddy also runs with
`network_mode: host`, ACME-issues a certificate for `NODE_DOMAIN`, and routes:

- `/x/*` -> `reverse_proxy unix//var/run/remnawave/xray.sock`
- everything else -> the decoy static site in `/srv/web`

Both containers share `./sockets:/var/run/remnawave`, so Caddy can connect to the
socket that Xray creates.

### Why Caddy in front of XHTTP

Xray-core discussion #4113 recommends hiding XHTTP behind a real reverse proxy such as
Caddy or Nginx to reduce fingerprints. Caddy also automates per-domain ACME (HTTP-01).
Using a Unix socket instead of a TCP listener means Xray has zero network presence:
active probes only ever see Caddy's TLS port and the decoy fallback.

### Why the fallback is in Caddy, not Xray

Official Xray docs state that VLESS `fallbacks` can only be used with TCP+TLS
transports. XHTTP is not TCP+TLS, so `fallbacks` cannot be used here. Caddy's decoy
branch is the fallback. The default decoy is Element Web v1.12.25, a real Matrix client
with a login page; any static site dropped into `./web` also works.

### Profile shape

The profile is a full Xray JSON: `log`, `inbounds[]`, `outbounds[]`, and `routing`.
The VLESS inbound has an empty `clients` array; Remnawave manages user UUIDs at the
Host level. The stable inbound tag is `VLESS-XHTTP-TLS`. `xhttpSettings` uses flat
fields (`path`, `mode`, `xPaddingBytes`, `scMaxBufferedPosts`, `scStreamUpServerSecs`)
rather than `extra`, so both Xray and xray-typed parse them natively.

### Routing order

`domainStrategy` is `IPIfNonMatch`. First match wins:

1. `geoip:private` -> `BLOCK`
2. `geosite:google` -> `DIRECT`
3. `geoip:cn`, `geoip:ru` -> `BLOCK`
4. `geosite:cn`, `geosite:category-ru` -> `BLOCK`

The Google whitelist is deliberately placed before the CN/RU blocks so Google websites
remain reachable.

## Deliberately omitted

- Docker files, Kubernetes, systemd units, Ansible, and CI workflows.
- A client-side configuration generator; Remnawave subscriptions handle clients.
- Zapret geosite/geoip mounts in the default profile; the option is documented in the
  README only.
