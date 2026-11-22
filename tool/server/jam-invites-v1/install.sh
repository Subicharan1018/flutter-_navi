#!/usr/bin/env bash
# jam-invites-v1: invite a friend into a live Jam from the app (they accept with one tap).
# Adds navivibe/jam_invites.py and registers it in navivibe/social.py.
# Needs the social v3 server (people.py, reactions.py) that is already live.
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
BK=$SHUF/backups/jam-invites-v1-$STAMP
TESTS="navivibe/tests/test_social.py navivibe/tests/test_jam_roles.py navivibe/tests/test_jam_invites_v1.py"

[ -f "$SHUF/navivibe/social.py" ] || { echo "!! $SHUF/navivibe/social.py not found"; exit 1; }
[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/shuf" && cp -a "$SHUF/navivibe" "$T/shuf/navivibe"
cp "$HERE/files/navivibe/jam_invites.py" "$T/shuf/navivibe/"
"$PY" -I "$HERE/patch_social.py" "$T/shuf/navivibe/social.py"
cp "$HERE/tests/test_jam_invites_v1.py" "$T/shuf/navivibe/tests/"
(cd "$T/shuf" && PYTHONPATH="$T/shuf" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3)

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK"
cp -a "$SHUF/navivibe/social.py" "$BK/"

restore() {
  echo "!! a test failed on the live tree: putting social.py back"
  cp -a "$BK/social.py" "$SHUF/navivibe/social.py"
  rm -f "$SHUF/navivibe/jam_invites.py" "$SHUF/navivibe/tests/test_jam_invites_v1.py"
  exit 1
}

echo "== 3/4 patch the live code"
cp "$HERE/files/navivibe/jam_invites.py" "$SHUF/navivibe/"
"$PY" -I "$HERE/patch_social.py" "$SHUF/navivibe/social.py"
cp "$HERE/tests/test_jam_invites_v1.py" "$SHUF/navivibe/tests/"
"$PY" -m py_compile "$SHUF/navivibe/jam_invites.py" "$SHUF/navivibe/social.py" || restore

echo "== 4/4 tests on the live tree"
(cd "$SHUF" && PYTHONPATH="$SHUF" "$PY" -m pytest $TESTS -q -p no:cacheprovider | tail -3) || restore

cat <<EOS

Done. Backup: $BK

Restart the shuffle server so it loads the new routes (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Rollback:
    cp -a $BK/social.py $SHUF/navivibe/social.py && rm -f $SHUF/navivibe/jam_invites.py $SHUF/navivibe/tests/test_jam_invites_v1.py
EOS
