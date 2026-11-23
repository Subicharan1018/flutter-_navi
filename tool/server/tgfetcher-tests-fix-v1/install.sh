#!/usr/bin/env bash
# tgfetcher-tests-fix-v1: the tg-fetcher test suite no longer depends on /opt/tg-fetcher/.env.
#   Before: with the live .env (EXPORTIFY_BATCH_SIZE=100, EXPORTIFY_GB_PER_HOUR=0.77, ...) the "tests on the live
#   tree" step of every package that runs the tg-fetcher suite failed on test_exportify_v1 (2 tests) and rolled the
#   package back; the scratch run has no .env and passed.
#   Now: tests/conftest.py pins every tunable the code reads to its documented default before tgfetch is imported.
#   Test file only (tests/conftest.py, one exact-text patch). No tg-fetcher code changes, nothing to restart.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run the suite with NO .env and with the live .env values
#     bash install.sh             # the real thing
# Safe to re-run. Backs up, patches, runs the suite on the live tree (with its real .env), puts the old file back on a failure.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
PY=$TG/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/tgfetcher-tests-fix-v1-$STAMP
PATCHED="tests/conftest.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$TG/$PATCHED" ] || { echo "!! $TG/$PATCHED not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

# suite <tg root> <log>: the whole tg-fetcher suite with private log / details paths; prints the last line.
suite() {
  (cd "$1" && NAVIVIBE_LOG_DIR="$T/logs" NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db" \
     "$PY" -m pytest -q -rfs -p no:cacheprovider > "$2" 2>&1) || true
  tail -1 "$2"
}
clean() { ! grep -qE '^(FAILED|ERROR|SKIPPED)|[0-9] (failed|skipped|error)' "$1"; }

echo "== 1/4 patch + the whole suite on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tg"
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T/tg"
# only the NON-secret tunables of the live .env are copied into the scratch tree: never a key or token
grep -E '^(FETCH_PRIMARY|FETCH_BOT_FALLBACK|EXPORTIFY_BATCH_SIZE|EXPORTIFY_GB_PER_HOUR|CHANNEL_[A-Z_]+|JOB_CONCURRENCY|TG_DOWNLOAD_CONNECTIONS)=' "$TG/.env" > "$T/tunables.env" 2>/dev/null || : > "$T/tunables.env"
echo "   before the patch, no .env:          $(suite "$T/tg" "$T/.b0.log")"
cp "$T/tunables.env" "$T/tg/.env"
echo "   before the patch, with live values: $(suite "$T/tg" "$T/.b1.log")   ($(wc -l < "$T/tunables.env") tunables from the live .env)"
"$PY" -I "$HERE/patch.py" "$T/tg"
echo "   after the patch,  with live values: $(suite "$T/tg" "$T/.a1.log")"
clean "$T/.a1.log" || { tail -30 "$T/.a1.log"; echo "!! failed/skipped tests with the live values: nothing installed"; exit 1; }
rm -f "$T/tg/.env"
echo "   after the patch,  no .env:          $(suite "$T/tg" "$T/.a0.log")"
clean "$T/.a0.log" || { tail -30 "$T/.a0.log"; echo "!! failed/skipped tests without a .env: nothing installed"; exit 1; }
if [ "$CHECK" = 1 ]; then echo "== --check: the patch applies and the suite is green with and without the live .env values. Nothing was installed."; exit 0; fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/tests"
cp -a "$TG/$PATCHED" "$BK/$PATCHED"

restore() {
  echo "!! a test failed on the live tree: putting the old file back"
  cp -a "$BK/$PATCHED" "$TG/$PATCHED"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/4 patch the live test file"
"$PY" -I "$HERE/patch.py" "$TG" || restore
"$PY" -m py_compile "$TG/$PATCHED" || restore

echo "== 4/4 the whole suite on the live tree (its real .env is read; private temp log folder)"
echo "   live: $(suite "$TG" "$T/.live.log")"
clean "$T/.live.log" || { tail -30 "$T/.live.log"; restore; }

cat <<EOS

Done. Backup: $BK
Nothing to restart: only a test file changed.

Rollback:
    cp -a $BK/$PATCHED $TG/$PATCHED
EOS
