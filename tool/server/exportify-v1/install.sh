#!/usr/bin/env bash
# exportify-v1: import a Spotify playlist from an Exportify CSV, match it to the library, and fetch the
# Wishlist a little at a time, never past a disk floor (see README.md).
#   tg-fetcher   new tgfetch/exportify.py + exportify_api.py; 3 anchored patches (api.py, worker.py, db.py)
#   shuffle srv  new navivibe/exportify_proxy.py, spotify_details.py, catalog/spotify_evidence.py; 9 anchored
#                patches (server.py, hardening.py, catalog/mood_quality.py, catalog/api.py)
#   data         tg-fetcher writes /opt/shuffle-server/spotify_details.db (table spotify_details) on import
#   systemd      tg-fetcher-exportify.timer: the nightly pass (optional: you copy the units with sudo)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Needs server-fixes-v1 installed first. Safe to re-run. Tests on a scratch copy first (the shuffle
# server's suite before and after the patch, so a test that already failed doesn't block it), backs up,
# patches, tests the live tree and puts everything back if a test fails. Prints the sudo lines.
# Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$TG/venv/bin/python
SPY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/exportify-v1-$STAMP
TG_NEW="tgfetch/exportify.py tgfetch/exportify_api.py tests/test_exportify_v1.py"
TG_PATCHED="tgfetch/api.py tgfetch/worker.py tgfetch/db.py"
NV_NEW="exportify_proxy.py spotify_details.py catalog/spotify_evidence.py tests/test_exportify_v1_proxy.py tests/test_exportify_v1_details.py"
NV_PATCHED="server.py hardening.py catalog/mood_quality.py catalog/api.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
[ -f "$TG/tgfetch/youtube_batch.py" ] || { echo "!! server-fixes-v1 is not installed (tgfetch/youtube_batch.py is missing): install it first"; exit 1; }
for f in $TG_PATCHED; do [ -f "$TG/$f" ] || { echo "!! $TG/$f not found"; exit 1; }; done
for f in $NV_PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found (the mood rules need moods-v2 installed)"; exit 1; }; done

copy_tg() {  # $1 = a tg-fetcher root
  mkdir -p "$1/tests"
  cp "$HERE/files/tgfetch/exportify.py" "$HERE/files/tgfetch/exportify_api.py" "$1/tgfetch/"
  cp "$HERE/files/tests/test_exportify_v1.py" "$1/tests/"
}
copy_nv() {  # $1 = a navivibe folder
  mkdir -p "$1/tests"
  cp "$HERE/files/navivibe/exportify_proxy.py" "$HERE/files/navivibe/spotify_details.py" "$1/"
  cp "$HERE/files/navivibe/catalog/spotify_evidence.py" "$1/catalog/"
  cp "$HERE/files/navivibe-tests/"test_exportify_v1_*.py "$1/tests/"
}

run_nv_tests() {  # $1 = folder holding navivibe/, $2 = log; prints the summary, writes $2.failed
  (cd "$1" && PYTHONPATH="$1" "$SPY" -m pytest navivibe/tests -q -rf -p no:cacheprovider > "$2" 2>&1) || true
  grep -E '^FAILED ' "$2" | sed 's/ - .*//' | sort -u > "$2.failed" || true
  tail -1 "$2"
}
new_failures() { comm -13 "$T/.base.log.failed" "$1"; }

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db"    # no test ever writes the real one
mkdir -p "$T/tg"
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg"
copy_tg "$T/tg"
if (cd "$T/tg" && "$PY" -m pytest -q -p no:cacheprovider > "$T/.tg.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.tg.log")"
else
  tail -30 "$T/.tg.log"; echo "!! tg-fetcher scratch tests failed: nothing installed"; exit 1
fi
mkdir -p "$T/base" "$T/new"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
echo "   shuffle server before the patch: $(run_nv_tests "$T/base" "$T/.base.log")"
"$SPY" -I "$HERE/patch_proxy.py" "$T/new/navivibe"
copy_nv "$T/new/navivibe"
echo "   shuffle server after the patch:  $(run_nv_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_exportify_v1' "$T/.new.log.failed" 2>/dev/null && { echo "!! exportify-v1 proxy tests failed"; exit 1; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK/tg" "$BK/shuf"
for f in $TG_PATCHED; do mkdir -p "$BK/tg/$(dirname "$f")"; cp -a "$TG/$f" "$BK/tg/$f"; done
for f in $NV_PATCHED; do mkdir -p "$BK/shuf/$(dirname "$f")"; cp -a "$NV/$f" "$BK/shuf/$f"; done
: > "$BK/new-tg.txt"; : > "$BK/new-shuf.txt"
for f in $TG_NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-tg.txt"; done
for f in $NV_NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-shuf.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $TG_PATCHED; do cp -a "$BK/tg/$f" "$TG/$f"; done
  for f in $NV_PATCHED; do cp -a "$BK/shuf/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-tg.txt"
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-shuf.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 patch the live code, add the new files"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
copy_tg "$TG"
"$PY" -m py_compile "$TG"/tgfetch/exportify.py "$TG"/tgfetch/exportify_api.py "$TG"/tgfetch/api.py "$TG"/tgfetch/worker.py "$TG"/tgfetch/db.py || restore
"$SPY" -I "$HERE/patch_proxy.py" "$NV" || restore
copy_nv "$NV"
"$SPY" -m py_compile "$NV"/exportify_proxy.py "$NV"/server.py "$NV"/hardening.py || restore

echo "== 4/5 tests on the live tree"
if (cd "$TG" && "$PY" -m pytest -q -p no:cacheprovider > "$T/.tg-live.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.tg-live.log")"
else
  tail -30 "$T/.tg-live.log"; restore
fi
echo "   shuffle server: $(run_nv_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_exportify_v1' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

Restart tg-fetcher and the shuffle server so they load it (needs sudo):
    sudo systemctl restart tg-fetcher navivibe
    sleep 30; curl -s http://127.0.0.1:5510/health; echo; curl -s http://127.0.0.1:5500/ready; echo

Turn on the nightly pass (needs sudo; without it a fetch only moves when someone taps Start or Resume):
    sudo cp $HERE/systemd/tg-fetcher-exportify.service $HERE/systemd/tg-fetcher-exportify.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now tg-fetcher-exportify.timer

Watch it:
    journalctl -u tg-fetcher-exportify -f
    journalctl -u tg-fetcher | grep -E "exportify|youtube"

Rollback:
    sudo systemctl disable --now tg-fetcher-exportify.timer
    for f in $(echo $TG_PATCHED); do cp -a $BK/tg/\$f $TG/\$f; done
    for f in $(echo $NV_PATCHED); do cp -a $BK/shuf/\$f $NV/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-tg.txt
    xargs -r -I{} rm -f $NV/{} < $BK/new-shuf.txt
    sudo systemctl restart tg-fetcher navivibe
    (The exportify_* tables stay in fetch.db: harmless, and a re-install finds the imports again.)
EOS
