# Remnawave on Podman

Minimal, security-first Podman installers for a **Remnawave Panel** server and a
**Remnawave Node** server. The default transport is **VLESS + XHTTP + TLS**, with
Caddy terminating TLS and the Xray inbound listening only on a Unix domain socket
behind a real Element Web decoy site.

Everything is deliberately small: plain bash, `openssl`/`sed`/`grep`/`curl`, Podman
Compose, and Caddy. No Kubernetes, no systemd units, no client generator.

## Architecture

### Panel server

`remnawave/backend:3`, `postgres:18.4`, and `valkey/valkey:9-alpine` run on the
compose bridge network. Backend, PostgreSQL, and metrics host ports are bound to
`127.0.0.1` only (docs.rw requires that backend services are never
exposed publicly). Valkey uses a Unix socket shared through a named volume with the
backend. A Caddy container in the same stack does ACME for `PANEL_DOMAIN` and serves
both the UI and `/api/sub` with `reverse_proxy remnawave:3000`.

### Node server (unix socket + Caddy decoy fallback)

- `remnawave/node:latest` uses `network_mode: host` and receives `NODE_PORT` plus
  `SECRET_KEY` via environment variables.
- The Xray VLESS-XHTTP inbound listens on a **Unix domain socket**:
  `unix:/var/run/remnawave/xray.sock`. It has **no TCP port at all**, so there is
  nothing to actively probe at the transport layer; only Caddy's 443 is exposed.
- Caddy (`docker.io/library/caddy:2-alpine`, also `network_mode: host`) terminates TLS
  with ACME for `NODE_DOMAIN` and routes:
  - `/x/*` to `reverse_proxy unix//var/run/remnawave/xray.sock` (the XHTTP tunnel);
  - everything else to a decoy static web app served from `./web`.
- The default decoy is **Element Web** (`element-v1.12.25.tar.gz`), a real Matrix
  client with a login page. Active probers hitting 443 get a Matrix login page, not a
  proxy error.
- Xray-level `fallbacks` is **not** used: official Xray docs state `fallbacks` can only
  be used with TCP+TLS transports, and XHTTP is not TCP+TLS. The fallback lives in
  Caddy, which is stronger here because Xray has zero network presence.
- Both node containers share `./sockets` read-write so the Xray Unix socket is visible
  to Caddy.

## Quickstart

### 1. Install the Panel

```sh
cd panel
./install.sh
```

The installer copies `.env.example` to `.env` if needed, generates secrets
(`APP_SECRET`, `METRICS_PASS`, `POSTGRES_PASSWORD`, `WEBHOOK_SECRET_HEADER`), prompts
for `PANEL_DOMAIN` and `SUB_PUBLIC_DOMAIN`, renders `Caddyfile`, and starts the stack.

Open `https://PANEL_DOMAIN` and register the first account. The first registered user
becomes super-admin.

### 2. Install a Node

On the node server:

```sh
cd node
./install.sh
```

The installer prompts for `NODE_PORT` (default `2222`), `SECRET_KEY` (default: random),
and `NODE_DOMAIN`. It creates `sockets/` and `web/`, downloads the Element Web decoy
(skip with `./install.sh --no-decoy`), renders `Caddyfile`, and starts the node stack.

### 3. Add the Node in the Panel

1. Add a node with `address = NODE_DOMAIN` and `port = NODE_PORT`.
2. Select the **VLESS-XHTTP-TLS** profile from `profiles/vless-xhttp-tls.json`.
3. Open `NODE_PORT` on the node firewall **only to the Panel server's IP**.
4. Create a Host with `network = xhttp`, `security = tls`, port `443`, `SNI = NODE_DOMAIN`,
   `path = /x`, and empty flow.

Clients are delivered by Remnawave's own subscription system; no client generator is
included here.

## Firewall

- Panel server: expose `80/tcp` and `443/tcp` for ACME/Caddy.
- Node server: expose `80/tcp` and `443/tcp` for ACME/Caddy, and `NODE_PORT` only to
  the Panel IP.
- Never expose the panel backend, PostgreSQL, Valkey, or metrics ports publicly. This
  repo binds those host ports to `127.0.0.1`.

## Rootless caveat

ACME HTTP-01 needs ports `80` and `443`. On rootless Podman, binding ports below 1024
usually requires running the stack as root or using a DNS challenge. The scripts do not
assume sudo; if your rootless setup cannot bind `80/443`, run as root or switch ACME to
a DNS challenge.

## Security / anti-RKN notes

The profile and node setup follow Xray upstream recommendations:

1. XHTTP header padding `xPaddingBytes: "100-1000"` breaks header-length fingerprinting.
2. XMUX randomized reuse ranges are a client-side default and rotate connections;
   no fixed patterns are configured on the server side.
3. XHTTP stream-up uses gRPC header disguise (`Content-Type: application/grpc`) by
   default.
4. XHTTP is hidden behind a real Caddy reverse proxy, as recommended upstream:
   "应将 XHTTP 隐藏在真正的 Nginx、Caddy 后面以减少指纹特征" (Xray-core discussion
   #4113). This repo goes further: the Xray inbound is a Unix socket, so Xray has no
   TCP port at all and only Caddy's 443 is exposed.
5. TLS 1.3 and modern ciphers come from Caddy defaults; the documented client settings
   use `fingerprint: "chrome"`.
6. Routing hardening: `geoip:private` is blocked, and CN/RU destinations are blocked by
   default with a Google whitelist evaluated first.

### Probing-resistance rationale

The Xray inbound listens on `unix:/var/run/remnawave/xray.sock`, not a TCP address.
There is no Xray listener for a prober to scan on the network. Caddy owns port 443,
terminates TLS, and forwards only `/x/*` to the Unix socket. Any other request gets the
Element Web decoy, so an active probe sees a normal-looking Matrix login page.

### Routing semantics (order matters)

`domainStrategy` is `IPIfNonMatch`, and rules are evaluated first-match-wins in this
exact order:

1. `geoip:private` -> `BLOCK` (security baseline)
2. `geosite:google` -> `DIRECT` (Google whitelist; must come before the CN/RU blocks)
3. `geoip:cn`, `geoip:ru` -> `BLOCK`
4. `geosite:cn`, `geosite:category-ru` -> `BLOCK`

The Google whitelist is intentionally **before** the CN/RU blocks so Google websites
keep working. `geosite:google-cn` does not exist in `v2fly/domain-list-community`;
`geosite:google` is the correct category and covers CN-reachable Google domains.

### Optional zapret geosite/geoip

For RU-specific routing, the node docs describe mounting zapret data and routing
`ext:geo-zapret.dat:zapret` / `ext:ip-zapret.dat:zapret`. This is intentionally **not**
in the default profile. If you enable it, mount each file separately into
`/usr/local/share/xray/` in the node container; never mount the whole folder, because
that overwrites the default `geoip`/`geosite` files.

## Client-side notes

For VLESS + XHTTP over TLS, Remnawave Host fields should be:

- `network`: `xhttp`
- `security`: `tls`
- port: `443`
- `SNI`: node domain
- `path`: `/x`
- `flow`: `""` (no flow for XHTTP)
- `tlsSettings`: `fingerprint: "chrome"`, `alpn: ["h2", "http/1.1"]`

Do not enable `mux.cool` with XHTTP.

## Citations

- Xray-core discussion #4113, "XHTTP: Beyond REALITY":
  <https://github.com/XTLS/Xray-core/discussions/4113>
- Xray examples repository:
  <https://github.com/XTLS/Xray-examples>
- Remnawave docs:
  <https://docs.rw/>
- Xray fallback docs (TCP+TLS only; not used for XHTTP):
  <https://xtls.github.io/en/config/features/fallback.html>
