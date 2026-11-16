#!/usr/bin/env bash
# moods-v1: the shuffle server's mood labels (see README.md)
#   1 /catalog/songs carries each song's labels as "moods": [..] (other fields unchanged)
#   2 the labeller reads the first verse plus the chorus (~600-800 chars, was 220),
#     with its own prompt for English songs
#   3 "Not this mood": per listener, stored on the server, beats the LLM label
#     (GET /moods/overrides, POST/DELETE /moods/not-this; Flow chips, taste)
#   4 relabel_moods.sh: ask again about the songs mood_audit flags. NOT run here:
#     run it yourself after the restart.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first (before and after the patch, so a
# test that already failed doesn't block it), backs up, patches, tests the live tree
# and puts everything back if a test fails that passed before. Prints the sudo line.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/moods-v1-$STAMP
NEW="mood_overrides.py catalog/mood_lyrics.py tests/test_moods_v1.py"
PATCHED="catalog/mood_tags.py catalog/mood_audit.py catalog/api.py discover.py flow.py server.py tests/conftest.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
for f in $PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

copy_new() {   # $1 = a navivibe folder
  for f in $NEW; do mkdir -p "$1/$(dirname "$f")"; cp "$HERE/files/navivibe/$f" "$1/$f"; done
}

run_tests() {  # $1 = folder holding navivibe/, $2 = log; prints the summary, writes $2.failed
  (cd "$1" && PYTHONPATH="$1" "$PY" -m pytest navivibe/tests -q -rf -p no:cacheprovider > "$2" 2>&1) || true
  grep -E '^FAILED ' "$2" | sed 's/ - .*//' | sort -u > "$2.failed" || true
  tail -1 "$2"
}

new_failures() {  # $1 = log.failed; the failures that were not in the baseline
  comm -13 "$T/.base.log.failed" "$1"
}

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/new"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
echo "   before the patch: $(run_tests "$T/base" "$T/.base.log")"
"$PY" -I "$HERE/patch_moods.py" "$T/new/navivibe"
copy_new "$T/new/navivibe"
echo "   after the patch:  $(run_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_moods_v1' "$T/.new.log.failed" 2>/dev/null && { echo "!! moods-v1 tests failed"; exit 1; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $PATCHED; do mkdir -p "$BK/$(dirname "$f")"; cp -a "$NV/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-files.txt"; done
[ -f "$SHUF/mood_tags.json" ] && cp -a "$SHUF/mood_tags.json" "$BK/mood_tags.json"

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 patch the live code, add the new files"
"$PY" -I "$HERE/patch_moods.py" "$NV" || restore
copy_new "$NV"
"$PY" -m py_compile "$NV"/mood_overrides.py "$NV"/catalog/*.py "$NV"/discover.py "$NV"/flow.py "$NV"/server.py || restore

echo "== 4/5 tests on the live tree"
echo "   $(run_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_moods_v1' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

Restart the shuffle server so it loads the change (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Then ask the labeller again about the songs mood_audit flags (dry run first; it asks
before writing anything, and backs up mood_tags.json):
    bash $HERE/relabel_moods.sh

Rollback:
    for f in $(echo $PATCHED); do cp -a $BK/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-files.txt
    [ -f $BK/mood_tags.json ] && cp -a $BK/mood_tags.json $SHUF/mood_tags.json
    sudo systemctl restart navivibe
EOS
