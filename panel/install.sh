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

for dep in podman openssl sed grep; do
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

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

get_env() {
  sed -nE "s|^${1}=||p" .env | tail -n 1
}

set_env() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '%s=%s\n' "$key" "$value" >> .env
  fi
}

generate_if_unset() {
  local key="$1"
  local bytes="$2"
  local current
  current="$(get_env "$key")"
  if [[ -z "$current" || "$current" == "change_me" || "$current" == "changeme" ]]; then
    set_env "$key" "$(openssl rand -hex "$bytes")"
  fi
}

generate_if_unset APP_SECRET 64
generate_if_unset METRICS_PASS 64
generate_if_unset POSTGRES_PASSWORD 24
generate_if_unset WEBHOOK_SECRET_HEADER 32

if [[ -z "$(get_env DATABASE_URL)" || "$(get_env DATABASE_URL)" == *change_me* ]]; then
  set_env DATABASE_URL "postgresql://postgres:$(get_env POSTGRES_PASSWORD)@remnawave-db:5432/postgres"
fi

prompt_if_unset() {
  local key="$1"
  local prompt="$2"
  local default="$3"
  local current answer
  current="$(get_env "$key")"
  if [[ -z "$current" ]]; then
    read -r -p "${prompt} [${default}]: " answer
    set_env "$key" "${answer:-${default}}"
  fi
}

prompt_if_unset PANEL_DOMAIN "Panel domain" "panel.example.com"
prompt_if_unset SUB_PUBLIC_DOMAIN "Subscription public domain/path" "$(get_env PANEL_DOMAIN)/api/sub"

sed "s|PANEL_DOMAIN|$(get_env PANEL_DOMAIN)|g" Caddyfile.template > Caddyfile

info "starting stack (${COMPOSE_CMD[*]} up -d)"
"${COMPOSE_CMD[@]}" -f compose.yaml up -d

wait_for_health() {
  local name="$1"
  local id status
  for _ in $(seq 1 60); do
    id="$(podman ps --filter "name=${name}" --format '{{.ID}}' | head -n 1)"
    if [[ -z "$id" ]]; then
      sleep 2
      continue
    fi
    status="$(podman inspect --format '{{.State.Health.Status}}' "$id" 2>/dev/null || true)"
    if [[ "$status" == "healthy" ]]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

if ! wait_for_health remnawave; then
  warn "remnawave backend is not healthy yet; check '${COMPOSE_CMD[*]} logs remnawave'"
else
  ok "remnawave backend is healthy"
fi

echo
info "Panel is starting at https://$(get_env PANEL_DOMAIN)"
info "1. Register the first account; it becomes super-admin."
info "2. Then run node/install.sh on the node server and add the node in the panel."
