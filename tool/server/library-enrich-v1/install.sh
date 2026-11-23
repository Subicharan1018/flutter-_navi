#!/usr/bin/env bash
# library-enrich-v1: fill EMPTY genre / label / release date / ISRC for library songs from MusicBrainz and Last.fm.
# See README.md. Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check     scratch tests only: nothing live is touched, nothing copied
#     bash install.sh             tests, then copies the code to /opt/navivibe-libenrich (the cron job stays OFF)
#     LIBENRICH_CONTACT='<your contact URL or address>' bash install.sh --cron
#                                 as above, then shows the exact nightly cron line and asks (type yes)
# Never edits catalog.db, Navidrome or any music file. The only shared file it ever writes is
# spotify_details.db (empty fields only), and only when you run `python3 -m libenrich --run` yourself or
# enable the cron job. The Last.fm key is read by NAME from the environment or /opt/shuffle-server/.env and never printed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=${DEST:-/opt/navivibe-libenrich}
PY=${PY:-python3}
STAMP=$(date +%Y%m%d-%H%M%S)
MODE=${1:-}

[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
"$PY" -c 'import sys; assert sys.version_info >= (3, 9)' 2>/dev/null || { echo "!! python 3.9+ needed"; exit 1; }

echo "== 1/3 tests on a scratch copy (recorded API fixtures, no network, nothing live touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -r "$HERE/files" "$T/files"
if (cd "$T/files" && "$PY" -W ignore -m unittest discover -s tests > "$T/test.log" 2>&1); then
  echo "   $(tail -3 "$T/test.log" | tr '\n' ' ')"
else
  tail -30 "$T/test.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
[ "$MODE" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/3 copy the code to $DEST"
if ! mkdir -p "$DEST" 2>/dev/null; then
  echo "!! cannot create $DEST. Run once:  sudo install -d -o subi -g subi $DEST   then bash install.sh again"; exit 1
fi
[ -d "$DEST/libenrich" ] && cp -a "$DEST/libenrich" "$DEST/libenrich.bak-$STAMP"
mkdir -p "$DEST/libenrich" "$DEST/tests/fixtures"
cp "$HERE"/files/libenrich/*.py "$DEST/libenrich/"
cp "$HERE"/files/tests/*.py "$DEST/tests/"
cp "$HERE"/files/tests/fixtures/*.json "$DEST/tests/fixtures/"
mkdir -p /DATA/AppData/navivibe

echo "== 3/3 read-only check on the live files (writes nothing)"
(cd "$DEST" && "$PY" -m libenrich --report) || echo "   (report failed: look at the message above)"

CRON="17 2 * * * cd $DEST && LIBENRICH_CONTACT='${LIBENRICH_CONTACT:-<set LIBENRICH_CONTACT>}' nice -n 19 ionice -c3 $PY -m libenrich --run --max-minutes 150 --end-by 06:00 >> /DATA/AppData/navivibe/library_enrich.log 2>&1 # navivibe-libenrich"
cat <<EOS

Done. The nightly job is NOT enabled. First run by hand (about 2 hours for the whole library; safe to stop and repeat):

    cd $DEST && LIBENRICH_CONTACT='<contact URL or address>' $PY -m libenrich --run --limit 50

The job that would run every night at 02:17 (server time, not on the hour, as MusicBrainz asks):

    $CRON
EOS
if [ "$MODE" = "--cron" ]; then
  [ -n "${LIBENRICH_CONTACT:-}" ] || { echo "!! set LIBENRICH_CONTACT first (the contact MusicBrainz sees in the User-Agent)"; exit 1; }
  if [ -t 0 ]; then
    read -r -p "Add exactly this line to the subi crontab now? Type yes to confirm: " A
    if [ "$A" = yes ]; then
      ( crontab -l 2>/dev/null | grep -v "# navivibe-libenrich" || true; echo "$CRON" ) | crontab -
      echo "Added. Check with: crontab -l"
    else
      echo "Not added."
    fi
  else
    echo "(not interactive, so nothing was added)"
  fi
fi
cat <<EOS

Counts only (no network, no write):  cd $DEST && $PY -m libenrich --apply-only --dry-run
Progress:                            cd $DEST && $PY -m libenrich --report
Remove the cron line:                crontab -l | grep -v '# navivibe-libenrich' | crontab -
Rollback the code:                   rm -rf $DEST/libenrich && mv $DEST/libenrich.bak-$STAMP $DEST/libenrich   (only if a backup exists)
Undo what it wrote:                  provenance table enrich_provenance in spotify_details.db lists every filled field
EOS
