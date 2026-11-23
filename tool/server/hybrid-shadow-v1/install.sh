#!/usr/bin/env bash
# hybrid-shadow-v1: the Smart Shuffle hybrid (blend top-100 -> LightGBM re-ranker) in SHADOW mode.
#   HYBRID_ORDER=off|shadow|on (default shadow). Shadow: /next returns exactly what it returned
#   before; after the response is sent, the hybrid ranking for the same request is computed in a
#   background worker and written to a `hybrid_shadow` table. A nightly fit (03:54 IST) trains
#   the re-ranker. `on` serves the hybrid for next-song positions only (openers stay on v3).
#   Adds navivibe/hybrid.py (the research harness file, unchanged), hybrid_store.py, hybrid_shadow.py,
#   hybrid_train.py; patches server.py, recsys/recommender.py and
#   scheduler.py (small anchored edits, see patch.py). NEEDS play-events-v2 installed first.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run the tests, install nothing
#     bash install.sh             # the real thing
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the live tree and puts
# everything back if a test fails. Does NOT restart anything and never opens a listening log.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/hybrid-shadow-v1-$STAMP
NEW_FILES="navivibe/hybrid.py navivibe/hybrid_store.py navivibe/hybrid_shadow.py navivibe/hybrid_train.py navivibe/tests/test_hybrid_shadow_v1.py navivibe/tests/harness_hybrid_reference.py"
PATCHED="navivibe/server.py navivibe/scheduler.py navivibe/recsys/recommender.py"
TESTS=${TESTS:-"navivibe/tests/test_hybrid_shadow_v1.py navivibe/tests/test_play_events_v2.py navivibe/tests/test_feedback_played_at.py navivibe/tests/test_v3.py navivibe/tests/test_hardening.py navivibe/tests/test_security.py"}
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/navivibe/server.py" ] || { echo "!! $SHUF/navivibe/server.py not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
grep -q "play_events import log_served" "$SHUF/navivibe/server.py" || { echo "!! install play-events-v2 first (this package needs its served_id)"; exit 1; }
"$PY" -c "import lightgbm, numpy" || { echo "!! lightgbm / numpy missing in the server venv"; exit 1; }

echo "== 1/4 patch + tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -a "$SHUF/navivibe" "$T/navivibe"
find "$T/navivibe" -name __pycache__ -prune -exec rm -rf {} +
"$PY" -I "$HERE/patch.py" "$T"
for f in hybrid.py hybrid_store.py hybrid_shadow.py hybrid_train.py; do cp "$HERE/files/navivibe/$f" "$T/navivibe/"; done
cp "$HERE/files/navivibe/tests/test_hybrid_shadow_v1.py" "$HERE/files/navivibe/tests/harness_hybrid_reference.py" "$T/navivibe/tests/"
"$PY" -m py_compile $(for f in $PATCHED $NEW_FILES; do case $f in *tests*) ;; *) echo "$T/$f";; esac; done)
if (cd "$T" && PYTHONPATH="$T" NAVIVIBE_LOG_DIR="$T/logs" HYBRID_ORDER=shadow "$PY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.tests.log" 2>&1); then
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
mkdir -p "$BK/navivibe/recsys" "$BK/navivibe/tests"
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
for f in hybrid.py hybrid_store.py hybrid_shadow.py hybrid_train.py; do cp "$HERE/files/navivibe/$f" "$SHUF/navivibe/"; done
cp "$HERE/files/navivibe/tests/test_hybrid_shadow_v1.py" "$HERE/files/navivibe/tests/harness_hybrid_reference.py" "$SHUF/navivibe/tests/"
"$PY" -I "$HERE/patch.py" "$SHUF" || restore
"$PY" -m py_compile $(for f in $PATCHED navivibe/hybrid.py navivibe/hybrid_store.py navivibe/hybrid_shadow.py navivibe/hybrid_train.py; do echo "$SHUF/$f"; done) || restore

echo "== 4/4 tests on the live tree (temp log folder; the real listening logs are not opened)"
LOGS=$(mktemp -d)
(cd "$SHUF" && PYTHONPATH="$SHUF" NAVIVIBE_LOG_DIR="$LOGS" HYBRID_ORDER=shadow "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3) || { rm -rf "$LOGS"; restore; }
rm -rf "$LOGS"

cat <<EOS

Done. Backup: $BK

Restart the shuffle server (needs sudo; the start runs preprocess --full first):
    sudo systemctl restart navivibe
    sleep 60; curl -s http://127.0.0.1:5500/ready; echo

It starts in shadow mode (the default). To change the mode, set HYBRID_ORDER=off|shadow|on in
$SHUF/.env and restart. AI_ORDER is independent and untouched.

The first model is fitted at 03:54 IST. To fit it now (reads the logs, writes only
$SHUF/models/hybrid/hybrid_v1.json; takes a few minutes):
    cd $SHUF && venv/bin/python -m navivibe.hybrid_train

Rollback:
    for f in $PATCHED; do cp -a $BK/\$f $SHUF/\$f; done
    rm -f $SHUF/navivibe/hybrid.py $SHUF/navivibe/hybrid_store.py $SHUF/navivibe/hybrid_shadow.py $SHUF/navivibe/hybrid_train.py $SHUF/navivibe/tests/test_hybrid_shadow_v1.py $SHUF/navivibe/tests/harness_hybrid_reference.py
    sudo systemctl restart navivibe
(The extra table in each listening log is harmless to the old code.)
EOS
