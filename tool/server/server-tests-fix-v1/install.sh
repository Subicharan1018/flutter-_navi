#!/usr/bin/env bash
# server-tests-fix-v1: the shuffle server's own test suite passes with 0 failed and 0 skipped.
#   Before: 8 failed, 1133 passed, 2 skipped (every installer printed "already failing before, ignored: 8").
#   Test files only, no server code is changed:
#     tests/conftest.py               patched (a test never reads a real/shared spotify_details.db): 7 lyrics tests
#     tests/test_trending.py          patched (the live-chart check no longer depends on the day): 1 test
#     tests/test_session_security.py  patched (the HTTP test runs without httpx instead of being skipped): 1 skip
#     tests/patch_bearer_jwt.py       new (the file test_web_auth's patch test looks for next to itself): 1 skip
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run the WHOLE suite, install nothing
#     bash install.sh             # the real thing
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the live tree, and puts the old
# files back if anything fails or is skipped. Nothing is restarted (nothing the service runs changes).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/server-tests-fix-v1-$STAMP
PATCHED="navivibe/tests/conftest.py navivibe/tests/test_trending.py navivibe/tests/test_session_security.py"
NEW_FILES="navivibe/tests/patch_bearer_jwt.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/navivibe/tests/conftest.py" ] || { echo "!! $SHUF/navivibe/tests/conftest.py not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

# run_suite <folder holding navivibe/> <log>: the whole suite, a private log + spotify-details folder.
run_suite() {
  (cd "$1" && PYTHONPATH="$1" NAVIVIBE_LOG_DIR="$T/logs" NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db" \
     "$PY" -m pytest navivibe/tests -q -rfs -p no:cacheprovider > "$2" 2>&1) || true
  tail -1 "$2"
}
clean() { ! grep -qE '^(FAILED|ERROR|SKIPPED)|[0-9] (failed|skipped|error)' "$1"; }

echo "== 1/4 patch + the whole suite on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/new"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
echo "   before: $(run_suite "$T/base" "$T/.base.log")"
"$PY" -I "$HERE/patch.py" "$T/new"
cp "$HERE/files/navivibe/tests/patch_bearer_jwt.py" "$T/new/navivibe/tests/"
echo "   after:  $(run_suite "$T/new" "$T/.new.log")"
clean "$T/.new.log" || { tail -40 "$T/.new.log"; echo "!! the patched scratch copy still has failed/skipped tests: nothing installed"; exit 1; }
if [ "$CHECK" = 1 ]; then echo "== --check: the patch applies cleanly and the whole suite is green with 0 skipped. Nothing was installed."; exit 0; fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/navivibe/tests"
for f in $PATCHED; do cp -a "$SHUF/$f" "$BK/$f"; done
: > "$BK/was-new.txt"
for f in $NEW_FILES; do if [ -e "$SHUF/$f" ]; then cp -a "$SHUF/$f" "$BK/$f"; else echo "$f" >> "$BK/was-new.txt"; fi; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$SHUF/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$SHUF/$f"; done < "$BK/was-new.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/4 patch the live test files"
"$PY" -I "$HERE/patch.py" "$SHUF" || restore
cp "$HERE/files/navivibe/tests/patch_bearer_jwt.py" "$SHUF/navivibe/tests/"
"$PY" -m py_compile $(for f in $PATCHED $NEW_FILES; do echo "$SHUF/$f"; done) || restore

echo "== 4/4 the whole suite on the live tree (temp log folder; the real listening logs are not opened)"
echo "   live: $(run_suite "$SHUF" "$T/.live.log")"
clean "$T/.live.log" || { tail -40 "$T/.live.log"; restore; }

cat <<EOS

Done. Backup: $BK
Nothing to restart: only test files changed, the running service loads none of them.

Rollback:
    for f in $PATCHED; do cp -a $BK/\$f $SHUF/\$f; done
    xargs -r -I{} rm -f $SHUF/{} < $BK/was-new.txt
EOS
