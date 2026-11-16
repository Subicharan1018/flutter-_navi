#!/usr/bin/env bash
# server-fixes-v1: tg-fetcher fixes (see README.md)
#   1 chart songs whose library id went missing are re-matched (Raga of Revenge)
#   2 online song search: "in library" only when title AND artist are typed;
#     otherwise the bot is asked and the owned song comes back as owned_hint;
#     a newer search supersedes the user's older one
#   3 the queue's failed list leaves out songs that are in the library now
#   4 YouTube / YouTube Music playlist links (names only, via ytmusicapi)
#   5 auto-import of songs dropped into /DATA/Media/Music (systemd path + timer)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh
# Safe to re-run. Tests on a scratch copy first, backs up, patches, tests the
# live tree and puts everything back if a test fails. Prints the sudo lines.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TG=${TG:-/opt/tg-fetcher}
PY=$TG/venv/bin/python
YTMUSICAPI=ytmusicapi==1.12.3
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$TG/backups/server-fixes-v1-$STAMP
NEW="tgfetch/library_sweep.py tgfetch/search_owned.py tgfetch/titles.py tgfetch/youtube_list.py
     tgfetch/youtube_batch.py tgfetch/autoimport.py
     tests/test_sfv1_charts.py tests/test_sfv1_search.py tests/test_sfv1_failures.py
     tests/test_sfv1_youtube.py tests/test_sfv1_autoimport.py tests/fixtures/yt_get_playlist.json"
PATCHED="tgfetch/links.py tgfetch/worker.py tgfetch/api.py tgfetch/db.py tgfetch/trending.py
         tests/test_links.py tests/test_api_batches.py tests/test_trending.py tests/test_worker.py"

[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
for f in $PATCHED; do [ -f "$TG/$f" ] || { echo "!! $TG/$f not found"; exit 1; }; done
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }

copy_new() {   # $1 = tg-fetcher root
  mkdir -p "$1/tests/fixtures"
  for f in $NEW; do cp "$HERE/files/$f" "$1/$f"; done
}

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$TG" && tar cf - --exclude=./venv --exclude=./session --exclude=./data --exclude=./.git \
   --exclude=./backups --exclude='*/__pycache__' --exclude=./.pytest_cache --exclude='./.env*' \
   --exclude=./spike-out .) | tar xf - -C "$T"
"$PY" -I "$HERE/patch_tgfetch.py" "$T"
copy_new "$T"
if (cd "$T" && "$PY" -m pytest -q -p no:cacheprovider > "$T/.tests.log" 2>&1); then
  tail -1 "$T/.tests.log"
else
  tail -30 "$T/.tests.log"; echo "!! scratch tests failed: nothing installed"; exit 1
fi

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK"
for f in $PATCHED; do mkdir -p "$BK/$(dirname "$f")"; cp -a "$TG/$f" "$BK/$f"; done
: > "$BK/new-files.txt"
for f in $NEW; do [ -e "$TG/$f" ] || echo "$f" >> "$BK/new-files.txt"; done
"$TG/venv/bin/pip" freeze > "$BK/pip-freeze.txt"

restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $PATCHED; do cp -a "$BK/$f" "$TG/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$TG/$f"; done < "$BK/new-files.txt"
  echo "   restored from $BK (ytmusicapi, if it was installed, stays in the venv: harmless)"
  exit 1
}

echo "== 3/5 patch the live code, add the new files, install $YTMUSICAPI"
"$PY" -I "$HERE/patch_tgfetch.py" "$TG"
copy_new "$TG"
"$PY" -m py_compile "$TG"/tgfetch/*.py || restore
if "$PY" -c "import ytmusicapi, sys; sys.exit(0 if ytmusicapi.__version__ == '${YTMUSICAPI#*==}' else 1)" 2>/dev/null; then
  echo "   $YTMUSICAPI already installed"
else
  "$TG/venv/bin/pip" install -q "$YTMUSICAPI" || echo "   !! pip install failed: YouTube links will answer 'not set up yet' until it is installed"
fi

echo "== 4/5 tests on the live tree"
if (cd "$TG" && "$PY" -m pytest -q -p no:cacheprovider > "$T/.live.log" 2>&1); then
  tail -1 "$T/.live.log"
else
  tail -30 "$T/.live.log"; restore
fi

echo "== 5/5 auto-import: record the files already in the library (they are never re-imported)"
(cd "$TG" && "$PY" -m tgfetch.autoimport seed)

cat <<EOS

Done. Backup: $BK

Restart tg-fetcher so it loads the fixes (needs sudo):
    sudo systemctl restart tg-fetcher
    sleep 15; curl -s http://127.0.0.1:5510/health; echo

Turn on the auto-import (needs sudo):
    sudo cp $HERE/systemd/tg-fetcher-autoimport.service $HERE/systemd/tg-fetcher-autoimport.path $HERE/systemd/tg-fetcher-autoimport.timer /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now tg-fetcher-autoimport.path tg-fetcher-autoimport.timer

Watch it:
    journalctl -u tg-fetcher-autoimport -f
    cd $TG && venv/bin/python -m tgfetch.autoimport status
    journalctl -u tg-fetcher | grep -E "sweep|youtube"

Rollback:
    sudo systemctl disable --now tg-fetcher-autoimport.path tg-fetcher-autoimport.timer
    for f in $(echo $PATCHED); do cp -a $BK/\$f $TG/\$f; done
    xargs -r -I{} rm -f $TG/{} < $BK/new-files.txt
    sudo systemctl restart tg-fetcher
EOS
