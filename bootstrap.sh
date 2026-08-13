#!/usr/bin/env bash
# One-shot installer: curl -fsSL <this-URL> | bash -s -- panel|node
# Downloads the repo to ~/.local/share/remnawave-podman and runs the target installer.
set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
  panel|node) ;;
  *)
    echo "usage: curl -fsSL https://raw.githubusercontent.com/s0nyaX00X/remnawave-podman/main/bootstrap.sh | bash -s -- panel|node" >&2
    exit 1
    ;;
esac

# Refuse root: user-level only.
if [[ "$(id -u)" -eq 0 ]]; then
  echo "error: refusing to run as root; run as your normal user (rootless podman)" >&2
  exit 1
fi

for dep in curl tar; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "error: missing dependency: $dep" >&2
    exit 1
  fi
done

DEST="${XDG_DATA_HOME:-$HOME/.local/share}/remnawave-podman"
REPO="https://github.com/s0nyaX00X/remnawave-podman"

echo "==> installing remnawave-podman ($TARGET) to $DEST"
mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$REPO/archive/refs/heads/main.tar.gz" -o "$tmp/repo.tar.gz"
tar -xzf "$tmp/repo.tar.gz" -C "$tmp"
# Overwrite scripts/templates only; existing .env, sockets/, web/, Caddyfile are
# untracked and never shipped in the tarball, so they survive updates.
cp -a "$tmp/remnawave-podman-main/." "$DEST/"

exec "$DEST/$TARGET/install.sh"
