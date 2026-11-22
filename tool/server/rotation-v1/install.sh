#!/usr/bin/env bash
# rotation-v1: Rest a song (snooze + auto-rest), seasonal songs stay in season, Back in rotation.
# See README.md.
#   shuffle srv  new navivibe/rotation.py; 3 anchored patches
#                (taste_exclusions.py blocked_ids, discover.py user_context, server.py routes)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh            (tests on a scratch copy, then installs)
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
# Safe to re-run. The shuffle server's suite runs before and after the patch on a scratch copy, so a
# test that already failed does not block it. Backs up, patches, tests the live tree and puts
# everything back if a test fails. Prints the sudo line only after "Done". Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
SPY=${SPY:-$SHUF/venv/bin/python}
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/rotation-v1-$STAMP
NV_NEW="rotation.py tests/test_rotation_v1.py"
NV_PATCHED="taste_exclusions.py discover.py server.py"

[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $NV_PATCHED tests/test_listen_routes.py; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done

copy_nv() {  # $1 = a navivibe folder
  mkdir -p "$1/tests"
  cp "$HERE/files/navivibe/rotation.py" "$1/"
  cp "$HERE/files/navivibe-tests/test_rotation_v1.py" "$1/tests/"
}

run_nv_tests() {  # $1 = folder holding navivibe/, $2 = log; prints the summary, writes $2.failed
  (cd "$1" && PYTHONPATH="$1" "$SPY" -m pytest navivibe/tests -q -rf -p no:cacheprovider > "$2" 2>&1) || true
  grep -E '^FAILED ' "$2" | sed 's/ - .*//' | sort -u > "$2.failed" || true
  tail -1 "$2"
}
new_failures() { comm -13 "$T/.base.log.failed" "$1"; }

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/base" "$T/new"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T/base"
cp -a "$T/base/navivibe" "$T/new/navivibe"
echo "   shuffle server before the patch: $(run_nv_tests "$T/base" "$T/.base.log")"
"$SPY" -I "$HERE/patch_server.py" "$T/new/navivibe"
copy_nv "$T/new/navivibe"
echo "   shuffle server after the patch:  $(run_nv_tests "$T/new" "$T/.new.log")"
if [ -s "$T/.new.log.failed" ] && [ -n "$(new_failures "$T/.new.log.failed")" ]; then
  tail -40 "$T/.new.log"; echo "!! new failures on the scratch copy:"; new_failures "$T/.new.log.failed"
  echo "!! nothing installed"; exit 1
fi
[ -s "$T/.base.log.failed" ] && echo "   (already failing before, ignored: $(wc -l < "$T/.base.log.failed"))"
grep -q 'test_rotation_v1' "$T/.new.log.failed" 2>/dev/null && { echo "!! rotation-v1 tests failed"; exit 1; }
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/shuf"
for f in $NV_PATCHED; do mkdir -p "$BK/shuf/$(dirname "$f")"; cp -a "$NV/$f" "$BK/shuf/$f"; done
: > "$BK/new-shuf.txt"
for f in $NV_NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-shuf.txt"; done

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $NV_PATCHED; do cp -a "$BK/shuf/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-shuf.txt"
  echo "   restored from $BK"
  exit 1
}

echo "== 3/4 patch the live code, add the new files"
"$SPY" -I "$HERE/patch_server.py" "$NV" || restore
copy_nv "$NV"
"$SPY" -m py_compile "$NV"/rotation.py $(for f in $NV_PATCHED; do echo "$NV/$f"; done) || restore

echo "== 4/4 tests on the live tree"
echo "   shuffle server: $(run_nv_tests "$SHUF" "$T/.live.log")"
if [ -s "$T/.live.log.failed" ] && [ -n "$(new_failures "$T/.live.log.failed")" ]; then
  tail -40 "$T/.live.log"; new_failures "$T/.live.log.failed"; restore
fi
grep -q 'test_rotation_v1' "$T/.live.log.failed" 2>/dev/null && restore

cat <<EOS

Done. Backup: $BK

Restart the shuffle server so it loads the patch (needs sudo):
    sudo systemctl restart navivibe
    sleep 30; curl -s http://127.0.0.1:5500/ready; echo

Rollback:
    for f in $(echo $NV_PATCHED); do cp -a $BK/shuf/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-shuf.txt
    sudo systemctl restart navivibe
    (Listeners' files in the log dir's rotation/ folder stay: harmless.)
EOS
