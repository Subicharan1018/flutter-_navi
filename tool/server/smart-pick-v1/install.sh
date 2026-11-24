#!/usr/bin/env bash
# smart-pick-v1: Smart Shuffle from a playlist. Familiar songs first, cold songs last, never a cold
# opener, and the MODEL chooses from the whole playlist. Accepts the playlist as titles (old apps),
# song ids (`candidate_ids`, `exclude_ids`) or just a `playlist_id` (read on the server, cached 30 s).
#   SMART_PICK=on|off (default on; off = exactly the old behaviour). Adds navivibe/smart_pick.py;
#   patches navivibe/server.py and navivibe/recsys/recommender.py (small anchored edits, see patch.py).
#   NEEDS play-events-v2 and hybrid-shadow-v1 installed first. Does not change HYBRID_ORDER / AI_ORDER.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy: WHOLE live suite before and after the patch; installs nothing
#     bash install.sh             # the real thing
# Safe to re-run. Backs up, patches, runs the whole suite on the live tree and puts everything back if
# anything fails. Does NOT restart anything and never opens a listening log.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/smart-pick-v1-$STAMP
NEW_FILES="navivibe/smart_pick.py navivibe/tests/test_smart_pick_v1.py"
PATCHED="navivibe/server.py navivibe/recsys/recommender.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$SHUF/navivibe/server.py" ] || { echo "!! $SHUF/navivibe/server.py not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
grep -q "play_events import log_served" "$SHUF/navivibe/server.py" || { echo "!! install play-events-v2 first"; exit 1; }
grep -q "_hybrid_serve" "$SHUF/navivibe/server.py" || { echo "!! install hybrid-shadow-v1 first (this package is built on its server.py)"; exit 1; }

suite() {   # suite <root> <label>: the whole live suite, in a temp log folder
  local root=$1 label=$2 logs; logs=$(mktemp -d)
  if (cd "$root" && PYTHONPATH="$root" NAVIVIBE_LOG_DIR="$logs" "$PY" -m pytest navivibe/tests -q -p no:cacheprovider -x > "$logs/.suite.log" 2>&1); then
    echo "   $label: $(tail -1 "$logs/.suite.log")"; rm -rf "$logs"; return 0
  fi
  tail -40 "$logs/.suite.log"; rm -rf "$logs"; echo "!! $label: the suite failed"; return 1
}

echo "== 1/4 scratch copy: whole suite BEFORE, patch, whole suite AFTER (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$SHUF" && tar --exclude=./venv --exclude=./venv-audio --exclude=./backups --exclude=./_archive \
  --exclude=./lyrics_cache --exclude='./navivibe.bak*' --exclude='*/__pycache__' --exclude='*.bak*' -cf - .) | tar -xf - -C "$T"
suite "$T" "before (live code, unpatched)" || { echo "!! the live suite is not clean to begin with: nothing to compare against, nothing installed"; exit 1; }
"$PY" -I "$HERE/patch.py" "$T"
cp "$HERE/files/navivibe/smart_pick.py" "$T/navivibe/"
cp "$HERE/files/navivibe/tests/test_smart_pick_v1.py" "$T/navivibe/tests/"
"$PY" -m py_compile "$T/navivibe/smart_pick.py" "$T/navivibe/server.py" "$T/navivibe/recsys/recommender.py"
suite "$T" "after (patched)" || { echo "!! nothing installed"; exit 1; }
if [ "$CHECK" = 1 ]; then
  "$PY" -I "$HERE/patch.py" "$SHUF" --check || true
  echo "== --check: the patch applies cleanly and the whole suite passes before and after. Nothing was installed."
  exit 0
fi

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/navivibe/recsys" "$BK/navivibe/tests"
for f in $PATCHED; do cp -a "$SHUF/$f" "$BK/$f"; done
for f in $NEW_FILES; do if [ -e "$SHUF/$f" ]; then cp -a "$SHUF/$f" "$BK/$f"; else echo "$f" >> "$BK/was-new.txt"; fi; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$SHUF/$f"; done
  if [ -e "$BK/was-new.txt" ]; then while read -r f; do rm -f "$SHUF/$f"; done < "$BK/was-new.txt"; fi
  echo "   restored from $BK (the running service never saw the change: it was not restarted)"
  exit 1
}

echo "== 3/4 patch the live code"
cp "$HERE/files/navivibe/smart_pick.py" "$SHUF/navivibe/"
cp "$HERE/files/navivibe/tests/test_smart_pick_v1.py" "$SHUF/navivibe/tests/"
"$PY" -I "$HERE/patch.py" "$SHUF" || restore
"$PY" -m py_compile "$SHUF/navivibe/smart_pick.py" "$SHUF/navivibe/server.py" "$SHUF/navivibe/recsys/recommender.py" || restore

echo "== 4/4 whole suite on the live tree (temp log folder; the real listening logs are not opened)"
suite "$SHUF" "live tree" || restore

cat <<EOS

Done. Backup: $BK

Restart the shuffle server (needs sudo; the start runs preprocess --full first):
    sudo systemctl restart navivibe
    sleep 60; curl -s http://127.0.0.1:5500/ready; echo

On by default. To switch it off without touching code: SMART_PICK=off in $SHUF/.env, restart.
Tunables (optional, .env): SMART_PICK_COLD_PLAYS=3  SMART_PICK_STALE_DAYS=30  SMART_PICK_PLAYLIST_TTL=30

Rollback:
    for f in $PATCHED; do cp -a $BK/\$f $SHUF/\$f; done
    rm -f $SHUF/navivibe/smart_pick.py $SHUF/navivibe/tests/test_smart_pick_v1.py
    sudo systemctl restart navivibe
(The extra table smart_pick_items in each listening log is harmless to the old code.)
EOS
