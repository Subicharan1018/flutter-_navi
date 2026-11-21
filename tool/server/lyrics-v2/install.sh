#!/usr/bin/env bash
# lyrics-v2: finds songs with several artists, ISRC lookup, cache versions, YouTube Music as a source,
# a slow prefetch of the whole library's lyrics, and an opt-in .lrc sidecar writer (see README.md).
# Needs lyrics-v1 (installed).
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first (before and after), backs up, installs, tests the live
# tree and puts everything back if a test fails that passed before. Prints the sudo lines. Nothing is
# restarted, no timer is enabled, no lyrics are fetched and no .lrc file is written here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
PY=$SHUF/venv/bin/python
TGPY=${NAVIVIBE_YTMUSIC_PYTHON:-/opt/tg-fetcher/venv/bin/python}
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/lyrics-v2-$STAMP
V1_SHA=454060f2ee7d939ebccf0a9d5901be7041b15eada0e408e76586885a17ccf6ac   # lyrics_proxy.py as lyrics-v1 installed it
NEW="lyrics_prefetch.py lyrics_sidecar.py ytmusic_lyrics_helper.py tests/test_lyrics_v2.py"
REPLACED="lyrics_proxy.py tests/test_lyrics_v1.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ -f "$NV/lyrics_proxy.py" ] || { echo "!! lyrics-v1 is not installed: install it first"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
live_sha=$(sha256sum "$NV/lyrics_proxy.py" | cut -d' ' -f1)
if [ "$live_sha" != "$V1_SHA" ] && ! grep -q '(lyrics-v2)' "$NV/lyrics_proxy.py"; then
  echo "!! $NV/lyrics_proxy.py is not the lyrics-v1 this package was built on (sha $live_sha): nothing written"
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
"$PY" -m py_compile "$NV"/lyrics_proxy.py "$NV"/lyrics_prefetch.py "$NV"/lyrics_sidecar.py || restore
"$TGPY" -c 'import ytmusicapi' 2>/dev/null \
  && echo "   YouTube Music: ytmusicapi found in $TGPY" \
  || echo "   !! ytmusicapi is not importable by $TGPY: the YouTube Music source will stay silent (everything else works)"

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

Optional, to turn YouTube Music off: add  Environment=NAVIVIBE_YTMUSIC_LYRICS=0  (sudo systemctl edit navivibe).
Optional, lrc.red asks for a contact address in the User-Agent: you choose it, see README.md.

Fetch the library's lyrics slowly, every night (needs sudo; it keeps going where it stopped):
    sudo cp $HERE/systemd/navivibe-lyrics-prefetch.service $HERE/systemd/navivibe-lyrics-prefetch.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now navivibe-lyrics-prefetch.timer
    journalctl -u navivibe-lyrics-prefetch -f            # what it found, by source
  or once by hand, 100 songs, into a scratch cache that you can delete:
    cd $SHUF && PYTHONPATH=$SHUF $PY -m navivibe.lyrics_prefetch --sample 100 --cache-dir /tmp/lyrics-sample

Write .lrc files next to the audio (OFF; this is a dry run that only counts):
    cd $SHUF && PYTHONPATH=$SHUF $PY -m navivibe.lyrics_sidecar
  only after you have read the count:  ... -m navivibe.lyrics_sidecar --apply

Rollback:
    for f in $(echo $REPLACED); do cp -a $BK/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-files.txt
    sudo systemctl disable --now navivibe-lyrics-prefetch.timer; sudo rm -f /etc/systemd/system/navivibe-lyrics-prefetch.*
    sudo systemctl restart navivibe
EOS
