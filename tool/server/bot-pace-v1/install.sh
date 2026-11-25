#!/usr/bin/env bash
# bot-pace-v1: the music bot's inline searches are spaced out (BOT_SEARCH_GAP_S, default 4 s) and fewer spellings of a
# song are tried on it (BOT_QUERIES_PER_SONG, default 2). See README.md.
#   tg-fetcher   new tgfetch/bot_pace.py; anchored patches to sources/deezload.py and youtube_batch.py
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh            (tests on a scratch copy, then installs)
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
# Safe to re-run. Backs up, patches, tests the live tree, puts everything back if a test fails.
# Prints the sudo line only after "Done". Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
PY=$TG/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/bot-pace-v1-$STAMP
NEW="tgfetch/bot_pace.py tests/test_bot_pace_v1.py"
PATCHED="tgfetch/sources/deezload.py tgfetch/youtube_batch.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $PATCHED; do
  [ -f "$TG/$f" ] || { echo "!! $TG/$f not found (install channel-fallback-v1 first)"; exit 1; }
done

copy_files() {
  mkdir -p "$1/tests"
  cp "$HERE/files/tgfetch/bot_pace.py" "$1/tgfetch/"
  cp "$HERE/files/tests/test_bot_pace_v1.py" "$1/tests/"
}

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tg"
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg" >/dev/null       # a second run changes nothing
copy_files "$T/tg"
if (cd "$T/tg" && HUMAN_CHECK_FILE="$T/flag.json" "$PY" -m pytest -q -p no:cacheprovider > "$T/.tg.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.tg.log")"
else
  tail -30 "$T/.tg.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/tg/tgfetch/sources"
for f in $PATCHED; do cp -a "$TG/$f" "$BK/tg/$f"; done
: > "$BK/new-tg.txt"
for f in $NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-tg.txt"; done
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/tg/$f" "$TG/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-tg.txt"
  echo "   restored from $BK"; exit 1
}

echo "== 3/4 patch the live code, add the new files"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
copy_files "$TG"
"$PY" -m py_compile "$TG/tgfetch/bot_pace.py" $(for f in $PATCHED; do echo "$TG/$f"; done) || restore

echo "== 4/4 tests on the live tree"
if (cd "$TG" && HUMAN_CHECK_FILE="$T/flag-live.json" "$PY" -m pytest -q -p no:cacheprovider > "$T/.live.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.live.log")"
else
  tail -30 "$T/.live.log"; restore
fi

cat <<EOS

Done. Backup: $BK

Restart to load it (needs sudo):
    sudo systemctl restart tg-fetcher
    sleep 20; curl -s http://127.0.0.1:5510/health; echo

Watch it:
    journalctl -u tg-fetcher -f | grep -E "not found:|youtube:"
Who delivered what:
    sqlite3 $TG/data/fetch.db "select source, count(*) from jobs where source is not null group by 1"

Rollback:
    for f in $PATCHED; do cp -a $BK/tg/\$f $TG/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-tg.txt
    sudo systemctl restart tg-fetcher
EOS
