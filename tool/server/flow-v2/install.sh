#!/usr/bin/env bash
# flow-v2: Flow chooses and orders songs by their sound (real Spotify energy / valence / tempo / key),
#   fits a mood chip to what that mood sounds like in this library, keeps one artist from filling a batch
#   and from touching itself, and logs what it would do. FLOW_V2=off|shadow|on, default OFF.
#   Adds navivibe/flow_v2.py, patches navivibe/flow.py only (exact-text edits: it refuses and changes nothing
#   when the live flow.py is not the text this package was made for).
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: the whole live suite BEFORE and AFTER the patch; installs nothing
#     bash install.sh             # the real thing
# Safe to re-run. Backs up, patches, tests the live tree and puts everything back if a test that passed
# before now fails. Does NOT restart anything and never opens a listening log (tests use a temp log folder).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/flow-v2-$STAMP
F=navivibe/flow.py
NEW="navivibe/flow_v2.py navivibe/tests/test_flow_v2.py navivibe/tests/flow_v2_golden.json navivibe/tests/flow_v2_patch.py"
SUITE=${SUITE:-navivibe/tests}      # the whole live suite; only narrow it to try this script somewhere small
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/$F" ] || { echo "!! $SHUF/$F not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

put_new() {  # $1 = tree root
  cp "$HERE/files/navivibe/flow_v2.py" "$1/navivibe/flow_v2.py"
  cp "$HERE/tests/test_flow_v2.py" "$HERE/tests/flow_v2_golden.json" "$1/navivibe/tests/"
  cp "$HERE/patch_flow.py" "$1/navivibe/tests/flow_v2_patch.py"
}

suite() {  # $1 = tree root, $2 = file the failed test ids go to; the whole navivibe suite, temp log folder
  local logs; logs=$(mktemp -d)
  local out; out=$(mktemp)
  (cd "$1" && PYTHONPATH="$1" NAVIVIBE_LOG_DIR="$logs" FLOW_V2=off timeout 1700 "$PY" -m pytest $SUITE -q -rfE -p no:cacheprovider > "$out" 2>&1) || true
  { grep -E '^(FAILED|ERROR) ' "$out" || true; } | sed -E 's/ - .*$//' | sort -u > "$2"
  tail -1 "$out"
  if ! grep -qE ' (passed|failed)' "$out"; then cat "$out"; echo "!! the test run printed no result line: it did not run"; exit 1; fi
  rm -rf "$logs" "$out"
}

echo "== 1/4 the whole live suite on a scratch copy, BEFORE the patch (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -a "$SHUF/navivibe" "$T/navivibe"
find "$T/navivibe" -name __pycache__ -prune -exec rm -rf {} +
suite "$T" "$T/before.txt"
echo "   failing before the patch: $(wc -l < "$T/before.txt") (these are not ours)"

echo "== 2/4 patch the scratch copy, then the whole suite AFTER (FLOW_V2=off) and our tests with each mode"
"$PY" -I "$HERE/patch_flow.py" "$T/$F" || { echo "!! the live flow.py is not the text this package expects: nothing installed"; exit 1; }
put_new "$T"
"$PY" -m py_compile "$T/$F" "$T/navivibe/flow_v2.py"
suite "$T" "$T/after.txt"
comm -13 "$T/before.txt" "$T/after.txt" > "$T/new.txt" || true
if [ -s "$T/new.txt" ]; then
  echo "!! tests that passed before and fail now:"; cat "$T/new.txt"; echo "!! nothing installed"; exit 1
fi
echo "   no new failures. Still failing, as before: $(wc -l < "$T/after.txt")"
for m in off shadow on; do
  (cd "$T" && PYTHONPATH="$T" NAVIVIBE_LOG_DIR="$(mktemp -d)" FLOW_V2=$m "$PY" -m pytest navivibe/tests/test_flow_v2.py navivibe/tests/test_flow.py navivibe/tests/test_flow_v1.py navivibe/tests/test_flow_moods.py -q -p no:cacheprovider 2>&1 | tail -1 | sed "s/^/   FLOW_V2=$m: /") || true
done
echo "   (the Flow tests above include any pre-existing failure counted before the patch; only a NEW failure stops the install)"

if [ "$CHECK" = 1 ]; then
  echo "== --check: the patch applies, no test that passed before fails, FLOW_V2 defaults to off. Nothing was installed."
  exit 0
fi

echo "== 3/4 back up what runs now -> $BK, patch the live code"
mkdir -p "$BK/navivibe/tests"
cp -a "$SHUF/$F" "$BK/$F"
for f in $NEW; do if [ -e "$SHUF/$f" ]; then cp -a "$SHUF/$f" "$BK/$f"; else echo "$f" >> "$BK/was-new.txt"; fi; done
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  cp -a "$BK/$F" "$SHUF/$F"
  for f in $NEW; do if [ -e "$BK/$f" ]; then cp -a "$BK/$f" "$SHUF/$f"; else rm -f "$SHUF/$f"; fi; done
  echo "   restored from $BK (the running service never saw the change: it was not restarted)"
  exit 1
}
"$PY" -I "$HERE/patch_flow.py" "$SHUF/$F" || restore
put_new "$SHUF"
"$PY" -m py_compile "$SHUF/$F" "$SHUF/navivibe/flow_v2.py" || restore

echo "== 4/4 the whole suite on the live tree (temp log folder; the real listening logs are not opened)"
suite "$SHUF" "$T/live.txt"
comm -13 "$T/before.txt" "$T/live.txt" > "$T/livenew.txt" || true
if [ -s "$T/livenew.txt" ]; then cat "$T/livenew.txt"; restore; fi
echo "   no new failures on the live tree"

cat <<EOS

Done. Backup: $BK

FLOW_V2 is not set, so Flow behaves exactly as before. Restart the shuffle server to load the code (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Then, to watch it first (Flow serves what it always did; each batch also logs the order v2 would have used):
    echo 'FLOW_V2=shadow' | sudo tee -a $SHUF/.env     # or edit the line if it exists
    sudo systemctl restart navivibe
Log: the listening-log folder's flow_v2/shadow.jsonl (one line per batch). Use FLOW_V2=on to serve v2, FLOW_V2=off to stop.

Rollback:
    cp -a $BK/$F $SHUF/$F
    rm -f $SHUF/navivibe/flow_v2.py $SHUF/navivibe/tests/test_flow_v2.py $SHUF/navivibe/tests/flow_v2_golden.json $SHUF/navivibe/tests/flow_v2_patch.py
    sudo systemctl restart navivibe
(Setting FLOW_V2=off and restarting is enough to stop it without removing anything.)
EOS
