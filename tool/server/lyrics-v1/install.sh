#!/usr/bin/env bash
# lyrics-v1: GET /lyrics/fetch, synced lyrics (word by word where a source has it) from lrc.red and
# BetterLyrics, an optional Paxsenix/Spotify source, cached per song on the server (see README.md).
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first (before and after the patch, so a test that already
# failed doesn't block it), backs up, patches, tests the live tree and puts everything back if a test
# fails that passed before. Prints the sudo line. Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/lyrics-v1-$STAMP
NEW="lyrics_proxy.py tests/test_lyrics_v1.py"
PATCHED="server.py"

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
"$PY" -I "$HERE/patch_lyrics_v1.py" "$T/new/navivibe"
copy_new "$T/new/navivibe"
echo "   after the patch:  $(run_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_lyrics_v1' "$T/.new.log.failed" 2>/dev/null && { echo "!! lyrics-v1 tests failed"; exit 1; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $PATCHED; do mkdir -p "$BK/$(dirname "$f")"; cp -a "$NV/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-files.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 patch the live code, add the new files"
"$PY" -I "$HERE/patch_lyrics_v1.py" "$NV" || restore
copy_new "$NV"
"$PY" -m py_compile "$NV"/lyrics_proxy.py "$NV"/server.py || restore
mkdir -p "$SHUF/lyrics_cache" && chmod 700 "$SHUF/lyrics_cache"

echo "== 4/5 tests on the live tree"
echo "   $(run_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_lyrics_v1' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

lrc.red asks every client for a contact address in its User-Agent. Put yours in the service's
environment (it is only ever sent to lrc.red and BetterLyrics) before the restart:
    sudo systemctl edit navivibe
        [Service]
        Environment=NAVIVIBE_LYRICS_CONTACT=you@example.com
    (Optional, off unless set: Environment=NAVIVIBE_PAXSENIX_URL=https://your-paxsenix-instance. Read README.md first.)

Restart the shuffle server so it loads the change (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo
    curl -s -o /dev/null -w '%{http_code}\n' "https://shuffle.subimusic.me/lyrics/fetch?title=x"   # 401 without a sign-in

Rollback:
    for f in $(echo $PATCHED); do cp -a $BK/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-files.txt
    sudo systemctl restart navivibe
EOS
