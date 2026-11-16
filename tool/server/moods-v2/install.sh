#!/usr/bin/env bash
# moods-v2: mood labels you can trust, and a mood editor (see README.md). Needs moods-v1.
#   1 evidence rules over the labeller's labels: a mood the audio and lyrics rule out is dropped
#     (no label rather than a wrong one); the labeller rates its confidence, unsure = no label
#   2 admin labels (mood_admin.json, who + when) beat the labeller for everyone; a relabel never
#     overwrites them
#   3 the mood editor: GET /moods/editor (https://shuffle.subimusic.me/moods/editor)
#   4 relabel_moods.sh (ask again about flagged songs) and mood_eval (accuracy on the reference
#     sample). NOT run here: run them yourself after the restart.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first (before and after the patch, so a test that
# already failed doesn't block it), backs up, patches, tests the live tree and puts everything
# back if a test fails that passed before. Prints the sudo line.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/moods-v2-$STAMP
NEW="catalog/mood_quality.py catalog/mood_eval.py mood_editor.py
     mood_editor_static/index.html mood_editor_static/app.js mood_editor_static/app.css
     tests/test_moods_v2.py tests/fixtures/mood_reference.json"
PATCHED="catalog/mood_tags.py catalog/mood_lyrics.py catalog/mood_audit.py catalog/api.py server.py tests/conftest.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
for f in $PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done
grep -q 'moods-v1' "$NV/catalog/mood_tags.py" || { echo "!! install moods-v1 first"; exit 1; }
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
"$PY" -I "$HERE/patch_moods_v2.py" "$T/new/navivibe"
copy_new "$T/new/navivibe"
echo "   after the patch:  $(run_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_moods_v2' "$T/.new.log.failed" 2>/dev/null && { echo "!! moods-v2 tests failed"; exit 1; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $PATCHED; do mkdir -p "$BK/$(dirname "$f")"; cp -a "$NV/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-files.txt"; done
for f in mood_tags.json mood_admin.json mood_meta.json; do [ -f "$SHUF/$f" ] && cp -a "$SHUF/$f" "$BK/$f"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 patch the live code, add the new files"
"$PY" -I "$HERE/patch_moods_v2.py" "$NV" || restore
copy_new "$NV"
"$PY" -m py_compile "$NV"/mood_editor.py "$NV"/catalog/*.py "$NV"/server.py || restore

echo "== 4/5 tests on the live tree"
echo "   $(run_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_moods_v2' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

Restart the shuffle server so it loads the change (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo
    curl -s -o /dev/null -w '%{http_code}\n' https://shuffle.subimusic.me/moods/editor   # 200

The mood editor: https://shuffle.subimusic.me/moods/editor  (admins: NAVIVIBE_ADMIN_USERS, now "admin")

How good are the labels? (read-only, the 54-song reference sample):
    cd $SHUF && PYTHONPATH=$SHUF venv/bin/python -m navivibe.catalog.mood_eval

Ask the labeller again about flagged songs with the new rules (dry run first; asks before writing):
    bash $HERE/relabel_moods.sh

Rollback:
    for f in $(echo $PATCHED); do cp -a $BK/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-files.txt
    sudo systemctl restart navivibe
EOS
