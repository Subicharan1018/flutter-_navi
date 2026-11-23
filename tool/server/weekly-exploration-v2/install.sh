#!/usr/bin/env bash
# weekly-exploration-v2: build this week's Weekly Exploration for every listener, without each one opening the page.
# See README.md. Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     scratch tests only: nothing live is touched, nothing copied
#     bash install.sh             tests, then adds navivibe/weekly_build.py (no restart needed; the cron job stays OFF)
#     bash install.sh --cron      as above, then shows the exact Monday cron line and asks (type yes)
# Needs weekly-exploration-v1 (and so exportify-v1). Patches nothing: one new file and its tests.
# Never prints a key. Never restarts anything.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
SPY=$SHUF/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
MODE=${1:-}
LOG=${WEEKLY_BUILD_LOG:-/DATA/AppData/navivibe/weekly_exploration_build.log}
TESTS="navivibe/tests/test_weekly_build_v2.py navivibe/tests/test_weekly_exploration_v1.py"

[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
[ -f "$NV/weekly_exploration.py" ] || { echo "!! weekly-exploration-v1 is not installed (navivibe/weekly_exploration.py is missing): install it first"; exit 1; }
[ -f "$NV/fetch_signing.py" ] || { echo "!! navivibe/fetch_signing.py is missing"; exit 1; }
case "$MODE" in ""|--check|--cron) ;; *) echo "usage: bash install.sh [--check|--cron]"; exit 2;; esac

echo "== 1/3 tests on a scratch copy (fake tg-fetcher, no network; nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/navivibe"
(cd "$SHUF" && tar cf - --exclude='*/__pycache__' --exclude='*.bak*' --exclude='*.orig' --exclude='*.png' navivibe) | tar xf - -C "$T"
cp "$HERE/files/navivibe/weekly_build.py" "$T/navivibe/"
cp "$HERE/files/navivibe-tests/test_weekly_build_v2.py" "$T/navivibe/tests/"
if (cd "$T" && PYTHONPATH="$T" "$SPY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.log" 2>&1); then
  echo "   shuffle server, weekly tests: $(tail -1 "$T/.log")"
else
  tail -30 "$T/.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
[ "$MODE" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/3 add navivibe/weekly_build.py"
HAD=0
if [ -f "$NV/weekly_build.py" ]; then HAD=1; cp -a "$NV/weekly_build.py" "$NV/weekly_build.py.bak-$STAMP"; fi
cp "$HERE/files/navivibe/weekly_build.py" "$NV/weekly_build.py"
cp "$HERE/files/navivibe-tests/test_weekly_build_v2.py" "$NV/tests/test_weekly_build_v2.py"
restore() {
  echo "!! a test failed on the live tree: putting the old file back"
  if [ "$HAD" = 1 ]; then cp -a "$NV/weekly_build.py.bak-$STAMP" "$NV/weekly_build.py"; else rm -f "$NV/weekly_build.py"; fi
  rm -f "$NV/tests/test_weekly_build_v2.py"
  exit 1
}
"$SPY" -m py_compile "$NV/weekly_build.py" || restore

echo "== 3/3 tests on the live tree"
(cd "$SHUF" && PYTHONPATH="$SHUF" "$SPY" -m pytest $TESTS -q -p no:cacheprovider > "$T/.live" 2>&1) || { tail -30 "$T/.live"; restore; }
echo "   $(tail -1 "$T/.live")"

# 06:00 IST on Monday = 00:30 UTC (the server clock is UTC).
CRON="30 0 * * 1 cd $SHUF && nice -n 19 $SPY -m navivibe.weekly_build --users all-eligible >> $LOG 2>&1 # navivibe-weekly-build"
cat <<EOS

Done. No restart is needed (it is a command, not part of the running service). The Monday job is NOT enabled.

ListenBrainz is per listener: only an account with its own ListenBrainz key in Navidrome gets hints (today: the admin).
Everyone else gets taste-only picks. The admin's key is never used for anyone else.

1. See who is eligible and whether ListenBrainz hints are used (builds nothing, sends nothing):

    cd $SHUF && $SPY -m navivibe.weekly_build --users admin --dry-run

2. Run it now for the admin account only (the first start):

    cd $SHUF && $SPY -m navivibe.weekly_build --users admin

3. Everyone allowed, now or by the Monday job below (one listener at a time, 30 s between; run it in screen or tmux):

    cd $SHUF && $SPY -m navivibe.weekly_build --users all-eligible --dry-run
    cd $SHUF && $SPY -m navivibe.weekly_build --users all-eligible

One named listener (add --force to top up a list already made this week):

    cd $SHUF && $SPY -m navivibe.weekly_build --user NAME

The job that would run every Monday at 06:00 IST (turn it on with: bash install.sh --cron, then type yes):

    $CRON
EOS
if [ "$MODE" = "--cron" ]; then
  if [ -t 0 ]; then
    read -r -p "Add exactly this line to the subi crontab now? Type yes to confirm: " A
    if [ "$A" = yes ]; then
      ( crontab -l 2>/dev/null | grep -v "# navivibe-weekly-build" || true; echo "$CRON" ) | crontab -
      echo "Added. Check with: crontab -l"
    else
      echo "Not added."
    fi
  else
    echo "(not interactive, so nothing was added)"
  fi
fi
cat <<EOS

Log:                  $LOG
Remove the cron line: crontab -l | grep -v '# navivibe-weekly-build' | crontab -
Rollback the code:    $( [ "$HAD" = 1 ] && echo "cp -a $NV/weekly_build.py.bak-$STAMP $NV/weekly_build.py" || echo "rm -f $NV/weekly_build.py $NV/tests/test_weekly_build_v2.py" )
EOS
