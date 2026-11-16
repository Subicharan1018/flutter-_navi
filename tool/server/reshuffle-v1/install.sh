#!/usr/bin/env bash
# reshuffle-v1: Smart Reshuffle picks across your top songs instead of the same
# few, so two reshuffles in a row give different queues. Normal playback is
# unchanged. Patches navivibe/recsys/recommender.py only.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the
# live tree and puts the file back if a test fails. Prints the restart.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
F=navivibe/recsys/recommender.py
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/reshuffle-v1-$STAMP
TESTS="navivibe/tests/test_reshuffle_v1.py navivibe/tests/test_v3.py"

[ -f "$SHUF/$F" ] || { echo "!! $SHUF/$F not found"; exit 1; }
[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -a "$SHUF/navivibe" "$T/navivibe"
"$PY" -I "$HERE/patch_reshuffle.py" "$T/$F"
cp "$HERE/tests/test_reshuffle_v1.py" "$T/navivibe/tests/"
(cd "$T" && PYTHONPATH="$T" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3)

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK"
cp -a "$SHUF/$F" "$BK/"

restore() {
  echo "!! a test failed on the live tree: putting recommender.py back"
  cp -a "$BK/recommender.py" "$SHUF/$F"
  rm -f "$SHUF/navivibe/tests/test_reshuffle_v1.py"
  exit 1
}

echo "== 3/4 patch the live code"
"$PY" -I "$HERE/patch_reshuffle.py" "$SHUF/$F"
cp "$HERE/tests/test_reshuffle_v1.py" "$SHUF/navivibe/tests/test_reshuffle_v1.py"

echo "== 4/4 tests on the live tree"
(cd "$SHUF" && PYTHONPATH="$SHUF" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3) || restore

cat <<EOS

Done. Backup: $BK

Restart the shuffle server so it loads the patch (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Rollback:
    cp -a $BK/recommender.py $SHUF/$F && rm -f $SHUF/navivibe/tests/test_reshuffle_v1.py
    sudo systemctl restart navivibe
EOS
