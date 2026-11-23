#!/usr/bin/env bash
# channels-primary-v1: the wishlist (Exportify) fetch asks the public Telegram channels FIRST and the
# music bot only for what no channel has (FETCH_PRIMARY=channels|race|bot, FETCH_BOT_FALLBACK=0|1).
# See README.md.
#   tg-fetcher   new tgfetch/channels_first.py; anchored patches to youtube_batch.py and exportify.py
#
# Needs channel-fallback-v1 and request-race-v1 installed (it uses channel_fallback and human_check).
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh            (tests on a scratch copy, then installs)
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
# Safe to re-run. Backs up, patches, tests the live tree, puts everything back if a test fails.
# Prints the sudo line only after "Done". Nothing is restarted here.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
PY=$TG/venv/bin/python
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/channels-primary-v1-$STAMP
NEW="tgfetch/channels_first.py tests/test_channels_primary_v1.py"
PATCHED="tgfetch/youtube_batch.py tgfetch/exportify.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
for f in $PATCHED tgfetch/channel_fallback.py tgfetch/human_check.py tgfetch/request_race.py; do
  [ -f "$TG/$f" ] || { echo "!! $TG/$f not found (install channel-fallback-v1 and request-race-v1 first)"; exit 1; }
done

copy_files() {
  mkdir -p "$1/tests"
  cp "$HERE/files/tgfetch/channels_first.py" "$1/tgfetch/"
  cp "$HERE/files/tests/test_channels_primary_v1.py" "$1/tests/"
}

echo "== 1/4 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tg"
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg"
"$PY" -I "$HERE/patch_tgfetch.py" "$T/tg" >/dev/null       # a second run changes nothing
copy_files "$T/tg"
if (cd "$T/tg" && HUMAN_CHECK_FILE="$T/flag.json" "$PY" -m pytest -q -p no:cacheprovider > "$T/.tg.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.tg.log")"
else
  tail -30 "$T/.tg.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/4 back up what runs now -> $BK"
mkdir -p "$BK/tg/tgfetch"
for f in $PATCHED; do cp -a "$TG/$f" "$BK/tg/$f"; done
: > "$BK/new-tg.txt"
for f in $NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-tg.txt"; done
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/tg/$f" "$TG/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-tg.txt"
  echo "   restored from $BK"; exit 1
}

echo "== 3/4 patch the live code, add the new files"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG" || restore
copy_files "$TG"
"$PY" -m py_compile "$TG/tgfetch/channels_first.py" $(for f in $PATCHED; do echo "$TG/$f"; done) || restore

echo "== 4/4 tests on the live tree"
if (cd "$TG" && HUMAN_CHECK_FILE="$T/flag-live.json" "$PY" -m pytest -q -p no:cacheprovider > "$T/.live.log" 2>&1); then
  echo "   tg-fetcher: $(tail -1 "$T/.live.log")"
else
  tail -30 "$T/.live.log"; restore
fi

cat <<EOS

Done. Backup: $BK

Add these lines to $TG/.env (see README.md for why), then restart (needs sudo):
    FETCH_PRIMARY=channels
    FETCH_BOT_FALLBACK=1
    EXPORTIFY_BATCH_SIZE=100
    EXPORTIFY_GB_PER_HOUR=0.77
    CHANNEL_MAX_MB=100
    CHANNEL_MIN_FREE_GB=25
(FETCH_PRIMARY=channels is also the default without a line; FETCH_BOT_FALLBACK=0 never asks the bot.)

    sudo systemctl restart tg-fetcher
    sleep 20; curl -s http://127.0.0.1:5510/health; echo

Watch it:
    journalctl -u tg-fetcher -f | grep -E "channels-first|HUMAN CHECK"
Search cache and who delivered what:
    sqlite3 $TG/data/fetch.db "select channel, count(*), sum(hits!='[]') from channel_cache group by 1"
    sqlite3 $TG/data/fetch.db "select source, count(*) from jobs where source is not null group by 1"

Rollback:
    for f in $PATCHED; do cp -a $BK/tg/\$f $TG/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-tg.txt
    sudo systemctl restart tg-fetcher
EOS
