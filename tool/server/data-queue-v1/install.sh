#!/usr/bin/env bash
# data-queue-v1: the admin's hidden weekly data queue (see README.md).
#   shuffle srv  new navivibe/data_queue.py, data_queue_store.py, data_queue_model.py, data_queue_tools/;
#                2 anchored patches to server.py (route registration, a 12 MB body cap on /data-queue)
#   tg-fetcher   new tgfetch/data_queue_hook.py; 1 anchored patch to db.py (update_job -> hook when a job is `ready`)
#   data         /opt/shuffle-server/data_queue.db is created on first use (queue, batches, audit, predicted features)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
#     bash install.sh            (tests on a scratch copy, then installs)
# Needs exportify-v1 installed (spotify_details.db, the matching rules). Safe to re-run. Backs up, patches, tests
# the live tree and puts everything back if a test fails. Prints the sudo lines only after "Done".
# Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$TG/venv/bin/python
SPY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/data-queue-v1-$STAMP
TG_NEW="tgfetch/data_queue_hook.py tests/test_data_queue_v1_hook.py"
TG_PATCHED="tgfetch/db.py"
NV_NEW="data_queue.py data_queue_store.py data_queue_model.py tests/test_data_queue_v1.py"
NV_PATCHED="server.py"
TOOLS="library_sample.py embedding_gap.py spotify_match.py song_match.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $TG_PATCHED; do [ -f "$TG/$f" ] || { echo "!! $TG/$f not found"; exit 1; }; done
for f in $NV_PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done
[ -f "$NV/exportify_proxy.py" ] || { echo "!! exportify-v1 is not installed (navivibe/exportify_proxy.py is missing): install it first"; exit 1; }

copy_nv() {  # $1 = a navivibe folder
  mkdir -p "$1/tests" "$1/data_queue_tools"
  cp "$HERE/files/navivibe/data_queue.py" "$HERE/files/navivibe/data_queue_store.py" "$HERE/files/navivibe/data_queue_model.py" "$1/"
  cp "$HERE/files/navivibe/data_queue_tools/__init__.py" "$1/data_queue_tools/"
  for t in $TOOLS; do cp "$HERE/files/navivibe/data_queue_tools/$t" "$1/data_queue_tools/"; done
  cp "$HERE/files/navivibe-tests/test_data_queue_v1.py" "$1/tests/"
}
copy_tg() {  # $1 = a tg-fetcher root
  mkdir -p "$1/tests"
  cp "$HERE/files/tgfetch/data_queue_hook.py" "$1/tgfetch/"
  cp "$HERE/files/tests/test_data_queue_v1_hook.py" "$1/tests/"
}
# the web server's tests that touch what is patched (server.py), plus the new ones
NV_SUITE="navivibe/tests/test_data_queue_v1.py navivibe/tests/test_fetch_proxy.py navivibe/tests/test_exportify_v1_proxy.py navivibe/tests/test_security.py"

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NAVIVIBE_DATA_QUEUE_DB="$T/data_queue.test.db"          # no test ever writes the real one
export NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db"
mkdir -p "$T/shuf" "$T/tg"
(cd "$SHUF" && tar cf - --exclude=./venv --exclude=./venv-audio --exclude='*/__pycache__' \
   --exclude=./backups --exclude=./_archive --exclude=./models --exclude=./lyrics_cache --exclude='*.bak*' \
   navivibe) | tar xf - -C "$T/shuf"
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T/tg"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe" >/dev/null     # a second run changes nothing
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg" >/dev/null
copy_nv "$T/shuf/navivibe"
copy_tg "$T/tg"
if (cd "$T/shuf" && PYTHONPATH="$T/shuf" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv.log")"
else
  tail -30 "$T/.nv.log"; echo "!! scratch tests failed (shuffle server): nothing installed"; exit 1
fi
if (cd "$T/tg" && NAVIVIBE_ROOT="$T/shuf" "$PY" -m pytest tests/test_data_queue_v1_hook.py -q -p no:cacheprovider > "$T/.tg.log" 2>&1); then
  echo "   tg-fetcher:     $(tail -1 "$T/.tg.log")"
else
  tail -30 "$T/.tg.log"; echo "!! scratch tests failed (tg-fetcher): nothing installed"; exit 1
fi
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK/tg/tgfetch" "$BK/nv"
for f in $TG_PATCHED; do cp -a "$TG/$f" "$BK/tg/$f"; done
for f in $NV_PATCHED; do cp -a "$NV/$f" "$BK/nv/$f"; done
: > "$BK/new-tg.txt"; : > "$BK/new-nv.txt"
for f in $TG_NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-tg.txt"; done
for f in $NV_NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-nv.txt"; done
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $TG_PATCHED; do cp -a "$BK/tg/$f" "$TG/$f"; done
  for f in $NV_PATCHED; do cp -a "$BK/nv/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-tg.txt"
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-nv.txt"
  echo "   restored from $BK"; exit 1
}

echo "== 3/5 patch the live code, add the new files (web server first: the hook imports its store)"
copy_nv "$NV"
"$SPY" -I "$HERE/patch_proxy.py" "$NV" || restore
"$SPY" -m py_compile "$NV/data_queue.py" "$NV/data_queue_store.py" "$NV/data_queue_model.py" "$NV/server.py" || restore
copy_tg "$TG"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
"$PY" -m py_compile "$TG/tgfetch/data_queue_hook.py" "$TG/tgfetch/db.py" || restore

echo "== 4/5 tests on the live tree"
if (cd "$SHUF" && PYTHONPATH="$SHUF" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv-live.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv-live.log")"
else
  tail -30 "$T/.nv-live.log"; restore
fi
if (cd "$TG" && "$PY" -m pytest tests/test_data_queue_v1_hook.py -q -p no:cacheprovider > "$T/.tg-live.log" 2>&1); then
  echo "   tg-fetcher:     $(tail -1 "$T/.tg-live.log")"
else
  tail -30 "$T/.tg-live.log"; restore
fi

cat <<EOS

== 5/5 Done. Backup: $BK

Restart both services (needs sudo). The queue starts empty and fills as songs arrive:
    sudo systemctl restart navivibe tg-fetcher
    sleep 20; systemctl is-active navivibe tg-fetcher; curl -s http://127.0.0.1:5510/health; echo

Seed it with the library songs that still lack real Spotify features (read-only on the library; add your earlier
export files and Exportify CSVs with --exclude so nothing already covered is queued):
    cd $SHUF && venv/bin/python -m navivibe.data_queue backfill --dry-run
    cd $SHUF && venv/bin/python -m navivibe.data_queue backfill --exclude ~/exports/batch1.csv
    cd $SHUF && venv/bin/python -m navivibe.data_queue status

Look at it (as the admin; anyone else gets 404):
    sqlite3 $SHUF/data_queue.db "select state, count(*) from queue group by 1"
    sqlite3 $SHUF/data_queue.db "select id, state, size, datetime(created_at,'unixepoch') from batches order by id desc limit 5"

Switch the arrival hook off without uninstalling: add DATA_QUEUE_OFF=1 to $TG/.env and restart tg-fetcher.

Rollback:
    for f in $TG_PATCHED; do cp -a $BK/tg/\$f $TG/\$f; done
    for f in $NV_PATCHED; do cp -a $BK/nv/\$f $NV/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-tg.txt
    xargs -r -I{} rm -f $NV/{} < $BK/new-nv.txt
    sudo systemctl restart navivibe tg-fetcher
(data_queue.db and the rows it added to spotify_details.db stay; they are harmless and re-usable.)
EOS
