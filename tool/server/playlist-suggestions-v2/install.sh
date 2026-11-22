#!/usr/bin/env bash
# playlist-suggestions-v2: "Suggested songs" under a playlist fit the playlist itself
# (closest songs, its artists, moods and language mix) and /predict/playlist-suggestions
# reads "exclude". Patches navivibe/discover.py and navivibe/server.py.
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests a scratch copy first, backs up, patches, tests the live tree
# and puts the files back if a test fails. Prints the restart; does not restart.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/playlist-suggestions-v2-$STAMP
TESTS="navivibe/tests/test_playlist_suggestions_v2.py navivibe/tests/test_discover.py navivibe/tests/test_taste_exclusions.py"

[ -f "$SHUF/navivibe/discover.py" ] || { echo "!! $SHUF/navivibe/discover.py not found"; exit 1; }
[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shuf" && cp -a "$SHUF/navivibe" "$T/shuf/navivibe"
"$PY" -I "$HERE/patch_playlist.py" "$T/shuf"
cp "$HERE/tests/test_playlist_suggestions_v2.py" "$T/shuf/navivibe/tests/"
(cd "$T/shuf" && PYTHONPATH="$T/shuf" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3)

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK"
cp -a "$SHUF/navivibe/discover.py" "$SHUF/navivibe/server.py" "$BK/"

restore() {
  echo "!! a test failed on the live tree: putting the files back"
  cp -a "$BK/discover.py" "$SHUF/navivibe/discover.py"
  cp -a "$BK/server.py" "$SHUF/navivibe/server.py"
  rm -f "$SHUF/navivibe/tests/test_playlist_suggestions_v2.py"
  exit 1
}

echo "== 3/4 patch the live code"
"$PY" -I "$HERE/patch_playlist.py" "$SHUF"
cp "$HERE/tests/test_playlist_suggestions_v2.py" "$SHUF/navivibe/tests/"
"$PY" -m py_compile "$SHUF/navivibe/discover.py" "$SHUF/navivibe/server.py" || restore

echo "== 4/4 tests on the live tree"
(cd "$SHUF" && PYTHONPATH="$SHUF" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3) || restore

cat <<EOS

Done. Backup: $BK

Restart the shuffle server so it loads the patch (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Rollback:
    cp -a $BK/discover.py $BK/server.py $SHUF/navivibe/ && rm -f $SHUF/navivibe/tests/test_playlist_suggestions_v2.py
EOS
