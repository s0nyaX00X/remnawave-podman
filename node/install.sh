#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# Refuse root: this stack is user-level only (rootless podman).
if [[ "$(id -u)" -eq 0 ]]; then
  echo "error: refusing to run as root; run as your normal user (rootless podman)" >&2
  exit 1
fi

for dep in podman openssl sed grep curl tar; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "error: missing dependency: $dep" >&2
    exit 1
  fi
done

COMPOSE_CMD=()
if podman compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(podman compose)
elif command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(podman-compose)
else
  echo "error: 'podman compose' or 'podman-compose' is required but not found" >&2
  echo "install hint: enable podman's compose provider or install podman-compose" >&2
  exit 1
fi

NO_DECOY=0
for arg in "$@"; do
  if [[ "$arg" == "--no-decoy" ]]; then
    NO_DECOY=1
  fi
done

# Re-runs keep existing values (rotating SECRET_KEY would break the panel pairing).
OLD_PORT=""; OLD_SECRET=""; OLD_DOMAIN=""
if [[ -f .env ]]; then
  OLD_PORT="$(sed -nE 's|^NODE_PORT=||p' .env | tail -n 1)"
  OLD_SECRET="$(sed -nE 's|^SECRET_KEY=||p' .env | tail -n 1)"
  OLD_DOMAIN="$(sed -nE 's|^NODE_DOMAIN=||p' .env | tail -n 1)"
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

cat > .env <<EOF
NODE_PORT=${NODE_PORT}
SECRET_KEY=${SECRET_KEY}
NODE_DOMAIN=${NODE_DOMAIN}
EOF

mkdir -p sockets web

if [[ "$NO_DECOY" -eq 1 ]]; then
  echo "skipping decoy download (--no-decoy)"
elif [[ -f web/index.html ]]; then
  echo "web/index.html already exists; keeping current decoy"
else
  echo "Downloading Element Web v1.12.25 as the Caddy decoy..."
  curl -fsSL "https://github.com/element-hq/element-web/releases/download/v1.12.25/element-v1.12.25.tar.gz" -o element-web.tar.gz
  tar -xzf element-web.tar.gz -C web --strip-components=1
  rm -f element-web.tar.gz
  if [[ ! -f web/index.html ]]; then
    echo "error: Element Web archive did not contain web/index.html" >&2
    exit 1
  fi
fi

sed "s|NODE_DOMAIN|${NODE_DOMAIN}|g" Caddyfile.template > Caddyfile

"${COMPOSE_CMD[@]}" -f compose.yaml up -d

echo
echo "Node stack started."
echo "Panel-side setup:"
echo "  add node: address=${NODE_DOMAIN}, port=${NODE_PORT}"
echo "  secret    = ${SECRET_KEY} (also stored in node/.env)"
echo "  select profile: VLESS-XHTTP-TLS"
echo "  open NODE_PORT only to the Panel IP"
echo "  create Host: vless, port 443, SNI=${NODE_DOMAIN}, path=/x, network=xhttp, security=tls"
