#!/usr/bin/env bash
# moods-v3: mood labels decided from all the evidence (real Spotify numbers, tags, lyrics, labeller).
# Installing changes NO label: the rules stay off until `mood_relabel --write` (see README.md).
# Needs moods-v2 and exportify-v1.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     # scratch copy only: patch + run every test, install nothing
#     bash install.sh             # the real thing
# Safe to re-run. The whole test suite runs on a scratch copy before and after the patch, so a test
# that already fails there doesn't block it; any NEW failure does, and on the live tree it also puts
# the old files back. Does not restart anything.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
BK=$SHUF/backups/moods-v3-$(date +%Y%m%d-%H%M%S)
NEW="catalog/mood_fusion.py catalog/mood_relabel.py catalog/mood_review.py catalog/mood_review_page.html tests/test_moods_v3.py"
PATCHED="catalog/mood_quality.py catalog/mood_tags.py catalog/mood_audit.py"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $PATCHED catalog/spotify_evidence.py; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found (moods-v2 and exportify-v1 come first)"; exit 1; }; done

copy_new() { for f in $NEW; do cp "$HERE/files/navivibe/$f" "$1/$f"; done; }

run_tests() {  # $1 = folder holding navivibe/, $2 = log. Prints the summary, writes $2.failed; stops if pytest itself broke.
  local rc=0
  (cd "$1" && PYTHONPATH="$1" NAVIVIBE_LOG_DIR="$T/logs" "$PY" -m pytest navivibe/tests -q -rfE -p no:cacheprovider > "$2" 2>&1) || rc=$?
  { grep -E '^(FAILED|ERROR) ' "$2" || true; } | sed 's/ - .*//' | sort -u > "$2.failed"
  tail -1 "$2"
  [ "$rc" -le 1 ]
}

gate() {       # $1 = log; fails on a failure that was not in the baseline, or any moods-v3 one
  local new; new=$(comm -13 "$T/base.log.failed" "$1.failed")
  if [ -n "$new" ] || grep -q test_moods_v3 "$1.failed"; then tail -40 "$1"; echo "!! new failures:"; echo "$new"; return 1; fi
}

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/new" "$T/logs"
echo "== 1/4 tests on a scratch copy (nothing live is touched)"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
run_tests "$T/base" "$T/base.log" || { tail -20 "$T/base.log"; echo "!! the test run itself broke on the unpatched copy"; exit 1; }
"$PY" -I "$HERE/patch_moods_v3.py" "$T/new/navivibe"
copy_new "$T/new/navivibe"
run_tests "$T/new" "$T/new.log" || { tail -20 "$T/new.log"; echo "!! the test run itself broke: nothing installed"; exit 1; }
gate "$T/new.log" || { echo "!! nothing installed"; exit 1; }
echo "   failing before and after, not from this package: $(wc -l < "$T/base.log.failed")"
if [ "$CHECK" = 1 ]; then echo "== --check: the patch applies and adds no failure. Nothing was installed."; exit 0; fi

echo "== 2/4 back up -> $BK"
mkdir -p "$BK/catalog"
for f in $PATCHED; do cp -a "$NV/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do
  if [ -e "$NV/$f" ]; then mkdir -p "$BK/$(dirname "$f")"; cp -a "$NV/$f" "$BK/$f"; else echo "$f" >> "$BK/new-files.txt"; fi
done

restore() {
  echo "!! putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$NV/$f"; done
  for f in $NEW; do if [ -e "$BK/$f" ]; then cp -a "$BK/$f" "$NV/$f"; else rm -f "$NV/$f"; fi; done
  echo "   restored from $BK (nothing was restarted)"; exit 1
}

echo "== 3/4 patch the live code"
"$PY" -I "$HERE/patch_moods_v3.py" "$NV" || restore
copy_new "$NV" || restore
"$PY" -m py_compile "$NV"/catalog/mood_*.py || restore

echo "== 4/4 tests on the live tree"
run_tests "$SHUF" "$T/live.log" || restore
gate "$T/live.log" || restore

cat <<EOS

Done. No label has changed. Backup: $BK

Restart (needs sudo):
    sudo systemctl restart navivibe
Dry run (reads only):
    cd $SHUF && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --list 40
Turn the rules on / off (no restart needed):
    cd $SHUF && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --write
    cd $SHUF && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --off
Rollback the code (turn the rules off first):
    for f in $PATCHED; do cp -a $BK/\$f $NV/\$f; done; sudo systemctl restart navivibe
EOS
