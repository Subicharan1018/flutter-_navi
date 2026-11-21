#!/usr/bin/env bash
# lyrics-v3: a failed lookup is never remembered as "no lyrics", a looser matcher with a false-positive
# guard, refresh=1 ("Search again"), per-song locking, a 12-second request budget (see README.md).
# Needs lyrics-v2 (installed).
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first (before and after), backs up, installs, tests the live
# tree and puts everything back if a test fails that passed before. Prints the sudo lines. Nothing is
# restarted, no lyrics are fetched and no file under the music folder is written here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/lyrics-v3-$STAMP
V2_SHA=2b448ba5ce56314fa9220f71e097718e78f18297e450b8dfb802135246068288   # lyrics_proxy.py as lyrics-v2 installed it
NEW="tests/test_lyrics_v3.py"
REPLACED="lyrics_proxy.py lyrics_prefetch.py ytmusic_lyrics_helper.py tests/test_lyrics_v2.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$NV/lyrics_proxy.py" ] && [ -f "$NV/lyrics_prefetch.py" ] || { echo "!! lyrics-v2 is not installed: install it first"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
live_sha=$(sha256sum "$NV/lyrics_proxy.py" | cut -d' ' -f1)
if [ "$live_sha" != "$V2_SHA" ] && ! grep -q '(lyrics-v3)' "$NV/lyrics_proxy.py"; then
  echo "!! $NV/lyrics_proxy.py is not the lyrics-v2 this package was built on (sha $live_sha): nothing written"
  exit 2
fi

copy_files() {   # $1 = a navivibe folder
  for f in $NEW $REPLACED; do mkdir -p "$1/$(dirname "$f")"; cp "$HERE/files/navivibe/$f" "$1/$f"; done
}

run_tests() {  # $1 = folder holding navivibe/, $2 = log; prints the summary, writes $2.failed
  (cd "$1" && PYTHONPATH="$1" "$PY" -m pytest navivibe/tests -q -rf -p no:cacheprovider > "$2" 2>&1) || true
  grep -E '^FAILED ' "$2" | sed 's/ - .*//' | sort -u > "$2.failed" || true
  tail -1 "$2"
}

new_failures() { comm -13 "$T/.base.log.failed" "$1"; }

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/new"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
echo "   before: $(run_tests "$T/base" "$T/.base.log")"
copy_files "$T/new/navivibe"
echo "   after:  $(run_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_lyrics_v' "$T/.new.log.failed" 2>/dev/null && { echo "!! lyrics tests failed"; exit 1; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $REPLACED; do mkdir -p "$BK/$(dirname "$f")"; cp -a "$NV/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-files.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $REPLACED; do cp -a "$BK/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/5 install the files"
copy_files "$NV"
"$PY" -m py_compile "$NV"/lyrics_proxy.py "$NV"/lyrics_prefetch.py "$NV"/ytmusic_lyrics_helper.py || restore

echo "== 4/5 tests on the live tree"
echo "   $(run_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_lyrics_v' "$T/.live.log.failed" 2>/dev/null && restore

echo "== 5/5 done"
cat <<EOS

Backup: $BK

Restart the shuffle server so it loads the change (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Nothing else is needed for the app: songs that were remembered as "no lyrics" by lyrics-v1 / v2 are
asked about again the next time they are opened (the cache version is now 3). To fill them in ahead of
time instead of waiting for tonight's timer (a gentle 45-minute pass that resumes where it stopped):
    cd $SHUF && PYTHONPATH=$SHUF $PY -m navivibe.lyrics_prefetch --max-minutes 45
    journalctl -u navivibe-lyrics-prefetch -f            # when the nightly timer runs it

Rollback:
    for f in $(echo $REPLACED); do cp -a $BK/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-files.txt
    sudo systemctl restart navivibe
EOS
