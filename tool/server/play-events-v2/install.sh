#!/usr/bin/env bash
# play-events-v2: one validated, idempotent door for play events + server-side weather + a log
#   of what /next served + the server bugs from docs/audit/server-bugs.md.
#   Adds navivibe/play_events.py; patches server.py, recsys/recommender.py, scheduler.py, weather.py and
#   sync_navidrome.py (small anchored edits, see patch.py). Old app payloads keep working.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run the tests, install nothing
#     bash install.sh             # the real thing
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the live tree and
# puts everything back if a test fails. Does NOT restart anything and never opens a listening
# log (the schema upgrade happens inside the service on the first event after the restart).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/play-events-v2-$STAMP
NEW_FILES="navivibe/play_events.py navivibe/tests/test_play_events_v2.py"
PATCHED="navivibe/server.py navivibe/recsys/recommender.py navivibe/scheduler.py navivibe/sync_navidrome.py navivibe/weather.py"
TESTS="navivibe/tests/test_play_events_v2.py navivibe/tests/test_feedback_played_at.py navivibe/tests/test_hardening.py navivibe/tests/test_security.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/navivibe/server.py" ] || { echo "!! $SHUF/navivibe/server.py not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

echo "== 1/4 patch + tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -a "$SHUF/navivibe" "$T/navivibe"
find "$T/navivibe" -name __pycache__ -prune -exec rm -rf {} +
"$PY" -I "$HERE/patch.py" "$T"
cp "$HERE/files/navivibe/play_events.py" "$T/navivibe/"
cp "$HERE/files/navivibe/tests/test_play_events_v2.py" "$T/navivibe/tests/"
"$PY" -m py_compile $(for f in $PATCHED navivibe/play_events.py; do echo "$T/$f"; done)
if (cd "$T" && PYTHONPATH="$T" NAVIVIBE_LOG_DIR="$T/logs" "$PY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.tests.log" 2>&1); then
  tail -1 "$T/.tests.log"
else
  tail -40 "$T/.tests.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
if [ "$CHECK" = 1 ]; then
  "$PY" -I "$HERE/patch.py" "$SHUF" --check || true
  echo "== --check: the patch applies cleanly to a scratch copy and every test passes. Nothing was installed."
  exit 0
fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/navivibe/recsys"
for f in $PATCHED; do cp -a "$SHUF/$f" "$BK/$f"; done
for f in $NEW_FILES; do [ -e "$SHUF/$f" ] && cp -a "$SHUF/$f" "$BK/$f" || echo "$f" >> "$BK/was-new.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$SHUF/$f"; done
  if [ -e "$BK/was-new.txt" ]; then while read -r f; do rm -f "$SHUF/$f"; done < "$BK/was-new.txt"; fi
  echo "   restored from $BK (the running service never saw the change: it was not restarted)"
  exit 1
}

echo "== 3/4 patch the live code"
cp "$HERE/files/navivibe/play_events.py" "$SHUF/navivibe/"
cp "$HERE/files/navivibe/tests/test_play_events_v2.py" "$SHUF/navivibe/tests/"
"$PY" -I "$HERE/patch.py" "$SHUF" || restore
"$PY" -m py_compile $(for f in $PATCHED navivibe/play_events.py; do echo "$SHUF/$f"; done) || restore

echo "== 4/4 tests on the live tree (temp log folder; the real listening logs are not opened)"
LOGS=$(mktemp -d)
(cd "$SHUF" && PYTHONPATH="$SHUF" NAVIVIBE_LOG_DIR="$LOGS" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3) || { rm -rf "$LOGS"; restore; }
rm -rf "$LOGS"

cat <<EOS

Done. Backup: $BK

Restart the shuffle server so it loads the new code (needs sudo; the start runs preprocess --full first):
    sudo systemctl restart navivibe
    sleep 60; curl -s http://127.0.0.1:5500/ready; echo

The nightly Navidrome sync (03:00 IST) starts a fresh Python each night, so it picks up its fix on its own.
The session server (navivibe-session) is not touched.

Rollback:
    for f in $PATCHED; do cp -a $BK/\$f $SHUF/\$f; done
    rm -f $SHUF/navivibe/play_events.py $SHUF/navivibe/tests/test_play_events_v2.py
    sudo systemctl restart navivibe
(The extra columns/tables added to each listening log on first use are harmless to the old code.)
EOS
