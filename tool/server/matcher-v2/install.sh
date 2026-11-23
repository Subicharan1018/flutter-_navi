#!/usr/bin/env bash
# matcher-v2: ONE song matcher for every importer (see README.md for the measured before / after)
#   adds tgfetch/song_match.py; patches tgfetch/library_sweep.py (Index), library.py (composer / album artist),
#   exportify.py, history_import.py, weekly_exploration.py and, if spotify-history-import-v1 is there, spotify_history.py.
#   Needs server-fixes-v1 (library_sweep.py). Install it AFTER exportify-v1 / history-import-v1 / spotify-history-import-v1 /
#   weekly-exploration so their call sites get the album and the fuzzy handling (a missing file is skipped, not an error).
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run the whole tg-fetcher suite, install nothing
#     bash install.sh             # the real thing
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the live tree and puts everything back if a
# test fails. Does NOT restart anything:   sudo systemctl restart tg-fetcher
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
SHUF=${SHUF:-/opt/shuffle-server}
PY=$TG/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/matcher-v2-$STAMP
NEW="tgfetch/song_match.py tests/test_matcher_v2.py tests/fixtures/matcher_gold.json"
PATCHED="tgfetch/library_sweep.py tgfetch/library.py tgfetch/exportify.py tgfetch/history_import.py
         tgfetch/weekly_exploration.py tgfetch/spotify_history.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$TG/tgfetch/library_sweep.py" ] || { echo "!! server-fixes-v1 is not installed (tgfetch/library_sweep.py is missing)"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

copy_new() {   # $1 = tg-fetcher root
  mkdir -p "$1/tests/fixtures"
  for f in $NEW; do cp "$HERE/files/$f" "$1/$f"; done
}

echo "== 1/4 patch + tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T"
"$PY" -I "$HERE/patch_tgfetch.py" "$T"
copy_new "$T"
# the shuffle server's navivibe package (norm_title / phonetic_key parity), read only: a copy, never the live one
N=$(mktemp -d); trap 'rm -rf "$T" "$N"' EXIT
[ -d "$SHUF/navivibe" ] && cp -a "$SHUF/navivibe" "$N/navivibe" && find "$N" -name __pycache__ -prune -exec rm -rf {} +
if (cd "$T" && PYTHONPATH="$N" "$PY" -m pytest -q -p no:cacheprovider > "$T/.tests.log" 2>&1); then
  tail -1 "$T/.tests.log"
else
  tail -30 "$T/.tests.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
if [ "$CHECK" = 1 ]; then
  "$PY" -I "$HERE/patch_tgfetch.py" "$TG" --check || true
  echo "== --check: every edit applies to a scratch copy and every tg-fetcher test passes. Nothing was installed."
  exit 0
fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $PATCHED; do [ -f "$TG/$f" ] && { mkdir -p "$BK/$(dirname "$f")"; cp -a "$TG/$f" "$BK/$f"; }; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-files.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do [ -f "$BK/$f" ] && cp -a "$BK/$f" "$TG/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK (the running service never saw the change: it was not restarted)"
  exit 1
}

echo "== 3/4 patch the live code"
copy_new "$TG"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
"$PY" -m py_compile $(for f in tgfetch/song_match.py $PATCHED; do [ -f "$TG/$f" ] && echo "$TG/$f"; done) || restore

echo "== 4/4 tests on the live tree"
(cd "$TG" && PYTHONPATH="$N" "$PY" -m pytest -q -p no:cacheprovider | tail -3) || restore

cat <<EOS

Done. Backup: $BK

Restart (needs sudo):
    sudo systemctl restart tg-fetcher

Nothing about ISRC matches changed. What changed is in README.md (the table). Fuzzy matches ("probably the same
song") never become "owned": Exportify lists them as the "maybe" (similar_id), the history imports do not count them,
Weekly Exploration treats them as owned (does not suggest them).

Rollback (the old matcher comes back; the new file can stay, nothing imports it):
    for f in $PATCHED; do [ -f $BK/\$f ] && cp -a $BK/\$f $TG/\$f; done
    sudo systemctl restart tg-fetcher
EOS
