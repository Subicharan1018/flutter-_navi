#!/usr/bin/env bash
# session-queue-v1: any of your devices edits the playing device's queue
#   protocol 4 of navivibe-session: queue_insert, queue_remove, queue_move,
#   queue_clear_upcoming (acked, versioned, rebased by track id when stale);
#   set_queue and protocol 1-3 clients keep working unchanged.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the
# live tree and puts everything back if a test fails. Prints the sudo line.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/session-queue-v1-$STAMP
NEW_TEST=navivibe/tests/test_session_queue_v1.py
TESTS="navivibe/tests/test_session_sync.py navivibe/tests/test_session_proto3.py
       navivibe/tests/test_session_security.py $NEW_TEST"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/navivibe/session.py" ] || { echo "!! $SHUF/navivibe/session.py not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -a "$SHUF/navivibe" "$T/navivibe"
find "$T/navivibe" -name __pycache__ -prune -exec rm -rf {} +
"$PY" -I "$HERE/patch_session.py" "$T/navivibe/session.py"
cp "$HERE/files/$NEW_TEST" "$T/$NEW_TEST"
if (cd "$T" && PYTHONPATH="$T" "$PY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.tests.log" 2>&1); then
  tail -1 "$T/.tests.log"
else
  tail -30 "$T/.tests.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK"
cp -a "$SHUF/navivibe/session.py" "$BK/session.py"
[ -e "$SHUF/$NEW_TEST" ] && cp -a "$SHUF/$NEW_TEST" "$BK/test_session_queue_v1.py" || : > "$BK/test-was-new"

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  cp -a "$BK/session.py" "$SHUF/navivibe/session.py"
  if [ -e "$BK/test-was-new" ]; then rm -f "$SHUF/$NEW_TEST"; else cp -a "$BK/test_session_queue_v1.py" "$SHUF/$NEW_TEST"; fi
  echo "   restored from $BK (the running service never saw the change: it was not restarted)"
  exit 1
}

echo "== 3/4 patch the live code, add the tests"
"$PY" -I "$HERE/patch_session.py" "$SHUF/navivibe/session.py" || restore
cp "$HERE/files/$NEW_TEST" "$SHUF/$NEW_TEST"
"$PY" -m py_compile "$SHUF/navivibe/session.py" || restore

echo "== 4/4 tests on the live tree"
if (cd "$SHUF" && PYTHONPATH="$SHUF" "$PY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.live.log" 2>&1); then
  tail -1 "$T/.live.log"
else
  tail -30 "$T/.live.log"; restore
fi

cat <<EOS

Done. Backup: $BK

Restart the session service so it speaks protocol 4 (needs sudo; every
device reconnects by itself within a few seconds):
    sudo systemctl restart navivibe-session
    sleep 3; curl -s http://127.0.0.1:5501/health; echo

Watch it:
    journalctl -u navivibe-session -f

Rollback:
    cp -a $BK/session.py $SHUF/navivibe/session.py
    rm -f $SHUF/$NEW_TEST
    sudo systemctl restart navivibe-session
EOS
