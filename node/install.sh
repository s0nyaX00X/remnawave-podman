#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Color helpers: [info] [ok] [warn] [error] — colors only when stdout is a TTY
# (and NO_COLOR is unset); tags stay in logs/pipes.
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_INFO='\033[1;34m'; C_OK='\033[1;32m'; C_WARN='\033[1;33m'; C_ERR='\033[1;31m'; C_END='\033[0m'
else
  C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_END=''
fi
info()  { printf '%b[info]%b %s\n' "$C_INFO" "$C_END" "$*"; }
ok()    { printf '%b[ok]%b %s\n' "$C_OK" "$C_END" "$*"; }
warn()  { printf '%b[warn]%b %s\n' "$C_WARN" "$C_END" "$*" >&2; }
error() { printf '%b[error]%b %s\n' "$C_ERR" "$C_END" "$*" >&2; }

# Refuse root: this stack is user-level only (rootless podman).
if [[ "$(id -u)" -eq 0 ]]; then
  error "refusing to run as root; run as your normal user (rootless podman)"
  exit 1
fi

for dep in podman openssl sed grep curl tar; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    error "missing dependency: $dep"
    exit 1
  fi
done

COMPOSE_CMD=()
if podman compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(podman compose)
elif command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
else
  error "'podman compose' or 'podman-compose' is required but not found"
  error "install hint: enable podman's compose provider or install podman-compose"
  exit 1
fi

NO_DECOY=0
for arg in "$@"; do
  if [[ "$arg" == "--no-decoy" ]]; then
    NO_DECOY=1
  fi
done

# Re-runs keep existing values (rotating SECRET_KEY would break the panel pairing).
OLD_PORT=""; OLD_SECRET=""; OLD_DOMAIN=""; OLD_TOR=""
if [[ -f .env ]]; then
  OLD_PORT="$(sed -nE 's|^NODE_PORT=||p' .env | tail -n 1)"
  OLD_SECRET="$(sed -nE 's|^SECRET_KEY=||p' .env | tail -n 1)"
  OLD_DOMAIN="$(sed -nE 's|^NODE_DOMAIN=||p' .env | tail -n 1)"
  OLD_TOR="$(sed -nE 's|^ENABLE_TOR=||p' .env | tail -n 1)"
fi

read -r -p "NODE_PORT [${OLD_PORT:-2222}]: " NODE_PORT
NODE_PORT="${NODE_PORT:-${OLD_PORT:-2222}}"

default_secret="${OLD_SECRET:-$(openssl rand -hex 32)}"
read -r -p "SECRET_KEY [keep ${default_secret:0:8}...]: " SECRET_KEY
SECRET_KEY="${SECRET_KEY:-${default_secret}}"

while [[ -z "${NODE_DOMAIN:-}" ]]; do
  read -r -p "NODE_DOMAIN [${OLD_DOMAIN:-}]: " NODE_DOMAIN
  NODE_DOMAIN="${NODE_DOMAIN:-${OLD_DOMAIN:-}}"
done

tor_default="${OLD_TOR:-n}"
read -r -p "Enable Tor exit container for the TOR profile? [y/N] (${tor_default}): " enable_tor
enable_tor="${enable_tor:-${tor_default}}"
case "$enable_tor" in
  y|Y|yes|YES) ENABLE_TOR=1 ;;
  *) ENABLE_TOR=0 ;;
esac

cat > .env <<EOF
NODE_PORT=${NODE_PORT}
SECRET_KEY=${SECRET_KEY}
NODE_DOMAIN=${NODE_DOMAIN}
ENABLE_TOR=${ENABLE_TOR}
EOF
chmod 600 .env

mkdir -p sockets web

if [[ "$NO_DECOY" -eq 1 ]]; then
  info "skipping decoy download (--no-decoy)"
elif [[ -f web/index.html ]]; then
  info "web/index.html already exists; keeping current decoy"
else
  info "downloading Element Web v1.12.25 as the Caddy decoy..."
  ELEMENT_SHA256="14d7f2671eb1fbccc690e7f176042d72ed2b4e34f7326a007e8b1540b1e748bb"
  curl -fsSL "https://github.com/element-hq/element-web/releases/download/v1.12.25/element-v1.12.25.tar.gz" -o element-web.tar.gz
  if ! echo "$ELEMENT_SHA256  element-web.tar.gz" | sha256sum -c - >/dev/null 2>&1; then
    error "Element Web checksum mismatch; aborting (possible tampering or version bump)"
    rm -f element-web.tar.gz
    exit 1
  fi
  tar -xzf element-web.tar.gz -C web --strip-components=1
  rm -f element-web.tar.gz
  if [[ ! -f web/index.html ]]; then
    error "Element Web archive did not contain web/index.html"
    exit 1
  fi
  ok "decoy ready (web/)"
fi

sed "s|NODE_DOMAIN|${NODE_DOMAIN}|g" Caddyfile.template > Caddyfile

info "starting node stack (${COMPOSE_CMD[*]} up -d)"
"${COMPOSE_CMD[@]}" -f compose.yaml up -d

if [[ "$ENABLE_TOR" -eq 1 ]]; then
  info "starting Tor exit container (dokomo-door, SOCKS5 @127.0.0.1:9050)..."
  "${COMPOSE_CMD[@]}" -f compose.tor.yaml up -d
  ok "Tor container started"
elif [[ "${OLD_TOR:-n}" == [yY]* ]] || [[ "${OLD_TOR:-}" == "1" ]]; then
  info "Tor was previously enabled; stopping container (compose.tor.yaml down)..."
  "${COMPOSE_CMD[@]}" -f compose.tor.yaml down 2>/dev/null || true
  info "Tor container stopped"
else
  info "Tor container disabled (ENABLE_TOR=0); re-run installer to enable"
fi

echo
ok "node stack started"
info "Panel-side setup:"
echo "  add node: address=${NODE_DOMAIN}, port=${NODE_PORT}"
echo "  secret    = ${SECRET_KEY} (also stored in node/.env)"
echo "  select profile: VLESS-XHTTP-TLS${ENABLE_TOR:+ or VLESS-XHTTP-TLS-TOR (Tor exit)}"
echo "  open NODE_PORT only to the Panel IP"
echo "  create Host: vless, port 443, SNI=${NODE_DOMAIN}, path=/x, network=xhttp, security=tls"
if [[ "$ENABLE_TOR" -eq 1 ]]; then
  echo
  info "Tor (dokomo-door) details:"
  echo "  SOCKS5 127.0.0.1:9050 inside the node network (container, never installed locally)"
  echo "  the VLESS-XHTTP-TLS-TOR profile routes .onion domains to it"
fi
