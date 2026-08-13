# Remnawave on Podman

Minimal, security-first Podman installers for a **Remnawave Panel** and **Node** stack.
Default transport: **VLESS + XHTTP** behind a TLS-terminating reverse proxy (Caddy, ACME).

Plain bash + Podman Compose.

## Install

On each server, run:

```sh
curl -fsSL https://raw.githubusercontent.com/s0nyaX00X/remnawave-podman/main/bootstrap.sh | bash
```

The script asks whether to install the **panel** or a **node**, checks dependencies,
generates secrets, and starts the stack. It refuses to run as root; for rootless
Podman to bind ports 80/443, allow unprivileged low ports once:
`sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0`.

Installs to `~/.local/share/remnawave-podman`; re-running updates files but keeps
`.env`, `web/` and `sockets/`.

### After installing the panel

Open `https://<panel-domain>` and register the first account — it becomes super-admin.

### After installing a node

In the Panel: add the node (address = `NODE_DOMAIN`, port = `NODE_PORT`, profile
`VLESS-XHTTP-TLS`), then create a Host (network `xhttp`, security `tls`, port `443`,
SNI = `NODE_DOMAIN`, path `/x`).

## Firewall

- **Panel**: `80`/`443` for ACME + Caddy. Backend/DB/Redis stay on `127.0.0.1`.
- **Node**: `80`/`443` for ACME + Caddy; `NODE_PORT` only from the Panel IP.

## Notes

- The Node's Xray core listens on a Unix socket (no TCP port); all traffic on `443`
  goes through the TLS-terminating proxy, and non-tunnel requests get a decoy site.
- Routing: CN/RU destinations are blocked by default; the Google whitelist
  (incl. CN-reachable endpoints like `gstatic.cn`/`googleapis.cn`) is evaluated
  first so Google pages don't lose their CDN assets to the CN block.
- Anti-RKN: XMUX connection rotation + randomized header padding live in the
  profile's `xhttpSettings.extra` (flows to both Node and clients; per-node
  override via the Host's `xhttpExtraParams`). Transport is H2-only.
- Optional: post-quantum Panel↔Node tunnel (WireGuard + Rosenpass) — see `vpn/`.
- Multi-node client templates (`profiles/xray-json-template*.json`): paste into
  Panel → Subscription → Templates → Xray JSON, assign to a visible virtual
  Host; name participating Hosts `proxy-*` and hide them. `xray-json-template.json`
  uses Cloudflare DoH; `xray-json-template-mullvad.json` (Mullvad DoH) is the
  paranoid variant — reserved for upcoming extensions.

## Sources

- Xray-core discussion #4113 (XHTTP): <https://github.com/XTLS/Xray-core/discussions/4113>
- Xray examples: <https://github.com/XTLS/Xray-examples>
- Remnawave docs: <https://docs.rw/>
