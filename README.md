# Remnawave on Podman

Minimal, security-first Podman installers for a **Remnawave Panel** and **Node** stack.
Default transport: **VLESS + XHTTP** behind a TLS-terminating reverse proxy (Caddy, ACME).

Plain bash + Podman Compose. No Kubernetes, no systemd units, no client generator.

## Requirements

- Podman with `podman compose` or `podman-compose`
- A domain (or subdomain) pointing to each server (Panel domain, one per Node)
- Ports `80`/`443` reachable for ACME; `NODE_PORT` reachable from the Panel IP only

## Quickstart

### 1. Panel server

```sh
cd panel
./install.sh
```

Generates secrets, prompts for the panel domain, starts the stack.
Open `https://<panel-domain>` and register the first account — it becomes super-admin.

### 2. Node server

```sh
cd node
./install.sh
```

Prompts for `NODE_PORT`, `SECRET_KEY`, `NODE_DOMAIN`; downloads a decoy web app
(skip with `--no-decoy`); starts the stack. Re-running keeps existing values.
To use your own decoy, drop any static site into `node/web/` before installing.

### 3. Add the node in the Panel

- address = `NODE_DOMAIN`, port = `NODE_PORT`
- config profile: `VLESS-XHTTP-TLS` (see `profiles/`)
- Host: network `xhttp`, security `tls`, port `443`, SNI = `NODE_DOMAIN`, path `/x`

## Firewall

- **Panel**: `80`/`443` for ACME + Caddy. Backend/DB/Redis stay on `127.0.0.1`.
- **Node**: `80`/`443` for ACME + Caddy; `NODE_PORT` only from the Panel IP.

## Notes

- Rootless Podman can't bind ports below 1024 without extra setup — run as root
  or use an ACME DNS challenge.
- The Node's Xray core listens on a Unix socket (no TCP port); all traffic on `443`
  goes through the TLS-terminating proxy, and non-tunnel requests get the decoy site.
- Routing: CN/RU destinations are blocked by default; Google is whitelisted.
- Design details and rationale: [`docs/DESIGN.md`](docs/DESIGN.md)

## Sources

- Xray-core discussion #4113 (XHTTP): <https://github.com/XTLS/Xray-core/discussions/4113>
- Xray examples: <https://github.com/XTLS/Xray-examples>
- Remnawave docs: <https://docs.rw/>
