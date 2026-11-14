#!/usr/bin/env bash
# Puts a NaviVibe web build live on subiserver, atomically. Run as subi (no sudo
# once /opt/navivibe-web exists and belongs to subi; see docs/web-deploy.md).
#
#   bash deploy-web.sh                 # newest GitHub release's navivibe-web-*.zip
#   bash deploy-web.sh --tag v1.0.0+130
#   bash deploy-web.sh ~/navivibe-web-1.0.0+130.zip
#   bash deploy-web.sh ~/build/web     # a local `flutter build web` output
#   bash deploy-web.sh --rollback      # back to the previous release
#
# Layout: /opt/navivibe-web/releases/<build>/ and a `current` symlink that is
# replaced with an atomic rename, so a request never sees half a build. Caddy
# (compose.yaml next to it) follows the symlink per request: no restart.
# The newest 3 releases are kept for rollback.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${NAVIVIBE_WEB_ROOT:-/opt/navivibe-web}
REPO=${NAVIVIBE_REPO:-Subicharan1018/flutter-_navi}
KEEP=${KEEP:-3}
REQUIRED=(index.html flutter_bootstrap.js sw.js manifest.json sqlite3.wasm drift_worker.js)

die() { echo "!! $*" >&2; exit 1; }
[ -d "$ROOT" ] && [ -w "$ROOT" ] || die "$ROOT missing or not writable: sudo install -d -o $USER -g $USER $ROOT"
mkdir -p "$ROOT/releases"

switch_to() { # $1 = release folder name
  ln -sfn "releases/$1" "$ROOT/current.tmp"
  mv -T "$ROOT/current.tmp" "$ROOT/current" # rename(2): atomic
  echo "   live: $ROOT/current -> releases/$1"
}

if [ "${1:-}" = "--rollback" ]; then
  cur=$(basename "$(readlink "$ROOT/current" 2>/dev/null || echo none)")
  # The newest release older than the live one (names start with the time).
  prev=$(ls -1 "$ROOT/releases" | grep -v '\.partial$' | sort -r | awk -v c="$cur" '$0 < c' | head -n 1 || true)
  [ -n "$prev" ] || die "no other release to roll back to"
  switch_to "$prev"
  exit 0
fi

# Caddy files: (re)installed from this checkout so config changes ship too.
for f in Caddyfile compose.yaml; do
  if ! cmp -s "$HERE/$f" "$ROOT/$f" 2>/dev/null; then cp "$HERE/$f" "$ROOT/$f"; echo "   installed $ROOT/$f"; CONFIG_CHANGED=1; fi
done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SRC=""
TAG=""
if [ "${1:-}" = "--tag" ]; then TAG=${2:?--tag needs a release tag}; shift 2; fi
if [ -n "${1:-}" ] && [ -d "$1" ]; then
  SRC=$1
elif [ -n "${1:-}" ] && [ -f "$1" ]; then
  unzip -q "$1" -d "$T/unz"
else
  api="https://api.github.com/repos/$REPO/releases/latest"
  [ -n "$TAG" ] && api="https://api.github.com/repos/$REPO/releases/tags/$(jq -rn --arg t "$TAG" '$t|@uri')"
  echo "== looking up ${TAG:-the latest release} of $REPO"
  url=$(curl -fsSL -H 'User-Agent: navivibe-deploy' "$api" |
    jq -r '[.assets[] | select(.name | test("^navivibe-web-.*\\.zip$"))][0].browser_download_url // empty')
  [ -n "$url" ] || die "that release has no navivibe-web-*.zip (web builds come from main)"
  echo "== downloading $(basename "$url")"
  curl -fsSL -o "$T/web.zip" "$url"
  unzip -q "$T/web.zip" -d "$T/unz"
fi
if [ -z "$SRC" ]; then
  SRC=$(dirname "$(find "$T/unz" -name index.html -print -quit)")
  [ -f "$SRC/index.html" ] || die "no index.html in the zip"
fi
for f in "${REQUIRED[@]}"; do [ -f "$SRC/$f" ] || die "$f missing: not a NaviVibe web build"; done

# Name the release after the build (version.json), plus the time.
ver=$(jq -r '"\(.version // "0")+\(.build_number // "0")"' "$SRC/version.json" 2>/dev/null || echo unknown)
NAME="$(date +%Y%m%d-%H%M%S)_${ver//[^A-Za-z0-9.+_-]/_}"
DEST="$ROOT/releases/$NAME"
mkdir -p "$DEST.partial"
cp -a "$SRC/." "$DEST.partial/"
find "$DEST.partial" -name '*.symbols' -delete
chmod -R a+rX "$DEST.partial"
mv "$DEST.partial" "$DEST"
switch_to "$NAME"

# Keep the newest $KEEP (never the live one).
ls -1 "$ROOT/releases" | grep -v '\.partial$' | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  [ "$old" = "$NAME" ] || rm -rf "${ROOT:?}/releases/$old"
done

if docker ps --format '{{.Names}}' | grep -qx navivibe-web; then
  if [ "${CONFIG_CHANGED:-0}" = 1 ]; then
    echo "   Caddy config changed: (cd $ROOT && docker compose up -d --force-recreate)"
  fi
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/ || true)
  echo "   http://127.0.0.1:8090/ -> $code"
else
  echo "   Caddy is not running yet: (cd $ROOT && docker compose up -d)"
fi
echo "Rollback: bash $0 --rollback"
