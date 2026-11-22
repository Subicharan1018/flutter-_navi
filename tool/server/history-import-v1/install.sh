#!/usr/bin/env bash
# history-import-v1: import past ListenBrainz listens / Last.fm scrobbles into the shuffle server's taste data;
# songs not in the library go on the Wishlist (exportify-v1) (see README.md).
#   tg-fetcher   new tgfetch/history_import.py + history_import_api.py; 1 anchored patch (api.py)
#   shuffle srv  new navivibe/history_import_proxy.py; 2 anchored patches (server.py, hardening.py)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh           test on a scratch copy, back up, patch, test the live tree
#     bash install.sh --check   only the scratch-copy tests: nothing live is touched
# Needs exportify-v1 (the Wishlist) and server-fixes-v1 installed first. Safe to re-run. Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$TG/venv/bin/python
SPY=$SHUF/venv/bin/python
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/history-import-v1-$STAMP
TG_NEW="tgfetch/history_import.py tgfetch/history_import_api.py tests/test_history_import_v1.py"
TG_PATCHED="tgfetch/api.py"
NV_NEW="history_import_proxy.py tests/test_history_import_v1_proxy.py"
NV_PATCHED="server.py hardening.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
[ -f "$TG/tgfetch/exportify.py" ] || { echo "!! exportify-v1 is not installed (tgfetch/exportify.py is missing): install it first"; exit 1; }
[ -f "$NV/exportify_proxy.py" ] || { echo "!! exportify-v1 is not installed on the shuffle server: install it first"; exit 1; }
for f in $TG_PATCHED; do [ -f "$TG/$f" ] || { echo "!! $TG/$f not found"; exit 1; }; done
for f in $NV_PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done

copy_tg() {  # $1 = a tg-fetcher root
  mkdir -p "$1/tests/fixtures_history"
  cp "$HERE/files/tgfetch/history_import.py" "$HERE/files/tgfetch/history_import_api.py" "$1/tgfetch/"
  cp "$HERE/files/tests/test_history_import_v1.py" "$1/tests/"
  cp "$HERE/files/tests/fixtures/"*.json "$1/tests/fixtures_history/"
}
copy_nv() {  # $1 = a navivibe folder
  mkdir -p "$1/tests"
  cp "$HERE/files/navivibe/history_import_proxy.py" "$1/"
  cp "$HERE/files/navivibe-tests/test_history_import_v1_proxy.py" "$1/tests/"
}
run_nv_tests() {  # $1 = folder holding navivibe/, $2 = log
  (cd "$1" && PYTHONPATH="$1" "$SPY" -m pytest navivibe/tests -q -rf -p no:cacheprovider > "$2" 2>&1) || true
  grep -E '^FAILED ' "$2" | sed 's/ - .*//' | sort -u > "$2.failed" || true
  tail -1 "$2"
}
new_failures() { comm -13 "$T/.base.log.failed" "$1"; }

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NAVIVIBE_LOG_DIR="$T/listening_logs"       # no test ever writes a real listening log
export NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db"
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
grep -q 'test_history_import_v1' "$T/.new.log.failed" 2>/dev/null && { echo "!! history-import-v1 proxy tests failed"; exit 1; }
if [ "$CHECK" = 1 ]; then echo "== --check: all scratch tests passed; nothing live was touched"; exit 0; fi

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
  rm -rf "$TG/tests/fixtures_history"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 patch the live code, add the new files"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
copy_tg "$TG"
"$PY" -m py_compile "$TG"/tgfetch/history_import.py "$TG"/tgfetch/history_import_api.py "$TG"/tgfetch/api.py || restore
"$SPY" -I "$HERE/patch_proxy.py" "$NV" || restore
copy_nv "$NV"
"$SPY" -m py_compile "$NV"/history_import_proxy.py "$NV"/server.py "$NV"/hardening.py || restore

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
grep -q 'test_history_import_v1' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

Restart tg-fetcher and the shuffle server so they load it (needs sudo):
    sudo systemctl restart tg-fetcher navivibe
    sleep 30; curl -s http://127.0.0.1:5510/health; echo; curl -s http://127.0.0.1:5500/ready; echo

Rollback:
    for f in $(echo $TG_PATCHED); do cp -a $BK/tg/\$f $TG/\$f; done
    for f in $(echo $NV_PATCHED); do cp -a $BK/shuf/\$f $NV/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-tg.txt
    xargs -r -I{} rm -f $NV/{} < $BK/new-shuf.txt
    rm -rf $TG/tests/fixtures_history
    sudo systemctl restart tg-fetcher navivibe
    (history_* tables stay in fetch.db: harmless. Imported plays stay in the listening logs; the app's "Remove
    imported history" takes them back, or: DELETE FROM play_events WHERE play_id LIKE 'imp:%';)
EOS
