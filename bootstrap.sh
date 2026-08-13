#!/usr/bin/env bash
# One-shot installer: curl -fsSL <this-URL> | bash
# Interactive: arrow-key menu for panel|node, then downloads the repo to
# ~/.local/share/remnawave-podman and runs the target installer.
set -euo pipefail

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

# Refuse root: user-level only.
if [[ "$(id -u)" -eq 0 ]]; then
  error "refusing to run as root; run as your normal user (rootless podman)"
  exit 1
fi

for dep in curl tar; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    error "missing dependency: $dep"
    exit 1
  fi
done

# Arrow-key radio menu; sets TARGET. Only usable on a real terminal.
select_target() {
  local options=("panel" "node")
  local n=${#options[@]}
  local sel=0 key esc i

  printf 'which do you want to install:\n'
  for i in "${!options[@]}"; do
    printf '[%s] %s\n' "$([[ $i -eq 0 ]] && echo '*' || echo ' ')" "${options[$i]}"
  done
  printf '\033[%dA' "$n"   # cursor to first option

  while :; do
    read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 esc
        case "$esc" in
          '[A') sel=$(( (sel + n - 1) % n )) ;;
          '[B') sel=$(( (sel + 1) % n )) ;;
        esac
        ;;
      ''|$'\r') break ;;
    esac
    for i in "${!options[@]}"; do
      printf '\033[2K\r[%s] %s\n' "$([[ $i -eq $sel ]] && echo '*' || echo ' ')" "${options[$i]}"
    done
    printf '\033[%dA' "$n"
  done

  printf '\033[%dB' "$n"   # below the menu
  printf '\r\033[K'
  TARGET="${options[$sel]}"
}

TARGET="${1:-}"
if [[ "$TARGET" != "panel" && "$TARGET" != "node" ]]; then
  if [[ -t 0 ]]; then
    select_target
  else
    read -r -p "Install (panel|node) [panel]: " TARGET
    TARGET="${TARGET:-panel}"
    case "$TARGET" in
      panel|node) ;;
      *) error "unknown target: $TARGET (use panel or node)"; exit 1 ;;
    esac
  fi
fi

DEST="${XDG_DATA_HOME:-$HOME/.local/share}/remnawave-podman"
REPO="https://github.com/s0nyaX00X/remnawave-podman"

info "installing remnawave-podman ($TARGET) to $DEST"
mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" -o "$tmp/repo.tar.gz"
tar -xzf "$tmp/repo.tar.gz" -C "$tmp"
# Overwrite scripts/templates only; existing .env, sockets/, web/, Caddyfile are
# untracked and never shipped in the tarball, so they survive updates.
cp -a "$tmp/remnawave-podman-main/." "$DEST/"

ok "fetched remnawave-podman"
exec "$DEST/$TARGET/install.sh"
