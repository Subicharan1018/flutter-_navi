#!/usr/bin/env bash
# preview-feed-v1: "Swipe to fetch": a feed of 30 s previews of songs that are not in the library (see README.md).
#   shuffle srv  new navivibe/preview_feed.py (+ its tests); 1 anchored patch to server.py (route registration)
#   data         /opt/shuffle-server/preview_feed.db is created on first use (signals, a preview-URL cache that expires)
#   tg-fetcher   untouched (the feed reads fetch.db read-only; fetching stays on the app's /fetch path)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
#     bash install.sh            (tests on a scratch copy, then installs)
# Needs weekly-exploration-v1 (its server.py line is the anchor). Safe to re-run. Backs up, patches, tests the live tree and
# puts everything back if a test fails. Prints the sudo line only after "Done". Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
SPY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/preview-feed-v1-$STAMP
NV_NEW="preview_feed.py tests/test_preview_feed_v1.py"
NV_PATCHED="server.py"
NV_SUITE="navivibe/tests/test_preview_feed_v1.py navivibe/tests/test_fetch_proxy.py navivibe/tests/test_security.py"

[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $NV_PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done
[ -f "$NV/weekly_exploration.py" ] || { echo "!! weekly-exploration-v1 is not installed (navivibe/weekly_exploration.py is missing): install it first"; exit 1; }
[ -f "$NV/fetch_access.py" ] || { echo "!! navivibe/fetch_access.py is missing"; exit 1; }

copy_nv() {  # $1 = a navivibe folder
  mkdir -p "$1/tests"
  cp "$HERE/files/navivibe/preview_feed.py" "$1/"
  cp "$HERE/files/navivibe-tests/test_preview_feed_v1.py" "$1/tests/"
}

echo "== 1/4 tests on a scratch copy first (no network, nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NAVIVIBE_PREVIEW_FEED_DB="$T/preview_feed.test.db"      # no test ever writes the real one
mkdir -p "$T/shuf"
(cd "$SHUF" && tar cf - --exclude=./venv --exclude=./venv-audio --exclude='*/__pycache__' \
   --exclude=./backups --exclude=./_archive --exclude=./models --exclude=./lyrics_cache --exclude='*.bak*' \
   navivibe) | tar xf - -C "$T/shuf"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe" >/dev/null     # a second run changes nothing
copy_nv "$T/shuf/navivibe"
if (cd "$T/shuf" && PYTHONPATH="$T/shuf" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv.log")"
else
  tail -30 "$T/.nv.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/nv"
for f in $NV_PATCHED; do cp -a "$NV/$f" "$BK/nv/$f"; done
: > "$BK/new-nv.txt"
for f in $NV_NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-nv.txt"; done
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $NV_PATCHED; do cp -a "$BK/nv/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-nv.txt"
  echo "   restored from $BK"; exit 1
}

echo "== 3/4 patch the live code, add the new files"
copy_nv "$NV"
"$SPY" -I "$HERE/patch_proxy.py" "$NV" || restore
"$SPY" -m py_compile "$NV/preview_feed.py" "$NV/server.py" || restore

echo "== 4/4 tests on the live tree"
if (cd "$SHUF" && PYTHONPATH="$SHUF" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv-live.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv-live.log")"
else
  tail -30 "$T/.nv-live.log"; restore
fi

cat <<EOS

Done. Backup: $BK

Restart the web server (needs sudo; tg-fetcher is not touched):
    sudo systemctl restart navivibe
    sleep 15; systemctl is-active navivibe; curl -s http://127.0.0.1:5510/health; echo

Look at it (a signed-in account with download access; others get 403):
    sqlite3 $SHUF/preview_feed.db "select user, verdict, count(*) from signals group by 1,2"
Daily hearts per listener default to 25: set PREVIEW_FEED_DAILY_CAP=N in $SHUF/.env and restart to change it.

Rollback:
    for f in $NV_PATCHED; do cp -a $BK/nv/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-nv.txt
    sudo systemctl restart navivibe
(preview_feed.db stays; it is harmless and re-usable.)
EOS
