#!/usr/bin/env bash
# film-credits-v1: film, year, music director, lyricist and singers per song (see README.md).
#   job          new /opt/navivibe-filmcredits (python module `filmcredits`, standard library only); writes ONLY its own
#                /opt/shuffle-server/film_credits.db; reads catalog.db read-only; Wikidata + MusicBrainz, cached
#   shuffle srv  new navivibe/film_credits.py + test; 2 anchored patches: server.py (GET /credits/films), catalog/api.py
#                (extra keys in GET /catalog/songs, ETag follows film_credits.db)
#
# Run on the server as subi (no sudo), from the folder this file is in:
#     bash install.sh --check    (only the scratch tests: nothing live is touched)
#     bash install.sh            (tests on a scratch copy, then installs; backs up; puts everything back if a live test fails)
# Needs exportify-v1 installed (its catalog/api.py hook). Safe to re-run. Nothing is restarted here, no sudo is used,
# .env and the live databases are never touched. The job makes NO network call until you run it yourself.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHUF=${SHUF:-/opt/shuffle-server}
NV=$SHUF/navivibe
SPY=$SHUF/venv/bin/python
JOB=${JOB:-/opt/navivibe-filmcredits}
PY=${PY:-python3}
STAMP=$(date +%Y%m%d-%H%M%S)
BK=$SHUF/backups/film-credits-v1-$STAMP
NV_NEW="film_credits.py tests/test_film_credits_v1.py"
NV_PATCHED="server.py catalog/api.py"
NV_SUITE="navivibe/tests/test_film_credits_v1.py navivibe/tests/test_catalog_meta.py navivibe/tests/test_exportify_v1_details.py navivibe/tests/test_fetch_proxy.py navivibe/tests/test_security.py"

[ -x "$SPY" ] || { echo "!! $SPY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
"$PY" -c 'import sys; assert sys.version_info >= (3, 9)' 2>/dev/null || { echo "!! python 3.9+ needed for the job"; exit 1; }
for f in $NV_PATCHED; do [ -f "$NV/$f" ] || { echo "!! $NV/$f not found"; exit 1; }; done
[ -f "$NV/spotify_details.py" ] || { echo "!! exportify-v1 is not installed (navivibe/spotify_details.py is missing): install it first"; exit 1; }

echo "== 1/5 tests on a scratch copy first (nothing live is touched)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export NAVIVIBE_FILM_CREDITS_DB="$T/none.db"                   # no test ever reads or writes the real one
export NAVIVIBE_SPOTIFY_DETAILS_DB="$T/spotify_details.test.db"
cp -r "$HERE/files" "$T/job"
if (cd "$T/job" && "$PY" -W ignore -m unittest discover -s tests > "$T/.job.log" 2>&1); then
  echo "   job:            $(grep -E "^(Ran|OK|FAILED)" "$T/.job.log" | tr '\n' ' ')"
else
  tail -30 "$T/.job.log"; echo "!! scratch tests failed (job): nothing installed"; exit 1
fi
mkdir -p "$T/shuf"
(cd "$SHUF" && tar cf - --exclude=./venv --exclude=./venv-audio --exclude='*/__pycache__' \
   --exclude=./backups --exclude=./_archive --exclude=./models --exclude=./lyrics_cache --exclude='*.bak*' \
   navivibe) | tar xf - -C "$T/shuf"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe"
"$SPY" -I "$HERE/patch_proxy.py" "$T/shuf/navivibe" >/dev/null     # a second run changes nothing
cp "$HERE/files/navivibe/film_credits.py" "$T/shuf/navivibe/"
mkdir -p "$T/shuf/navivibe/tests"; cp "$HERE/files/navivibe-tests/test_film_credits_v1.py" "$T/shuf/navivibe/tests/"
if (cd "$T/shuf" && PYTHONPATH="$T/shuf" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv.log")"
else
  tail -30 "$T/.nv.log"; echo "!! scratch tests failed (shuffle server): nothing installed"; exit 1
fi
[ "${1:-}" = "--check" ] && { echo "Check passed; nothing installed."; exit 0; }

echo "== 2/5 back up what runs now -> $BK"
mkdir -p "$BK/nv/catalog"
for f in $NV_PATCHED; do cp -a "$NV/$f" "$BK/nv/$f"; done
: > "$BK/new-nv.txt"
for f in $NV_NEW; do [ -e "$NV/$f" ] || echo "$f" >> "$BK/new-nv.txt"; done
[ -d "$JOB/filmcredits" ] && cp -a "$JOB/filmcredits" "$BK/filmcredits.old"
restore() {
  echo "!! a test failed on the live tree: putting the old files back"
  for f in $NV_PATCHED; do cp -a "$BK/nv/$f" "$NV/$f"; done
  while read -r f; do [ -n "$f" ] && rm -f "$NV/$f"; done < "$BK/new-nv.txt"
  echo "   restored from $BK"; exit 1
}

echo "== 3/5 patch the live web server, add the new files, copy the job to $JOB"
mkdir -p "$NV/tests"
cp "$HERE/files/navivibe/film_credits.py" "$NV/"
cp "$HERE/files/navivibe-tests/test_film_credits_v1.py" "$NV/tests/"
"$SPY" -I "$HERE/patch_proxy.py" "$NV" || restore
"$SPY" -m py_compile "$NV/film_credits.py" "$NV/server.py" "$NV/catalog/api.py" || restore
if ! mkdir -p "$JOB" 2>/dev/null; then
  echo "!! cannot create $JOB. Run once:  sudo install -d -o subi -g subi $JOB   then bash install.sh again (web patch put back)"; restore
fi
rm -rf "$JOB/filmcredits"; mkdir -p "$JOB/filmcredits" "$JOB/tests"
cp "$HERE"/files/filmcredits/*.py "$JOB/filmcredits/"
cp "$HERE"/files/tests/*.py "$JOB/tests/"

echo "== 4/5 tests on the live tree"
if (cd "$SHUF" && PYTHONPATH="$SHUF" "$SPY" -m pytest $NV_SUITE -q -p no:cacheprovider > "$T/.nv-live.log" 2>&1); then
  echo "   shuffle server: $(tail -1 "$T/.nv-live.log")"
else
  tail -30 "$T/.nv-live.log"; restore
fi
if (cd "$JOB" && "$PY" -W ignore -m unittest discover -s tests > "$T/.job-live.log" 2>&1); then
  echo "   job:            $(grep -E "^(Ran|OK|FAILED)" "$T/.job-live.log" | tr '\n' ' ')"
else
  tail -30 "$T/.job-live.log"; restore
fi

cat <<EOS

== 5/5 Done. Backup: $BK

1) Build the offline credits (tags and album names only; no network; writes only $SHUF/film_credits.db; seconds):
    cd $JOB && $PY -m filmcredits --catalog $SHUF/catalog.db --db $SHUF/film_credits.db

2) Restart the web server so /catalog/songs and /credits/films serve them (needs sudo; the app works with or without):
    sudo systemctl restart navivibe
    sleep 20; systemctl is-active navivibe; curl -s http://127.0.0.1:5500/health; echo

3) Optional, when you decide: ask Wikidata (and MusicBrainz for soundtrack track lists) about each film once; cached, about
   1 request per second, safe to stop and repeat. Choose the contact they see in the User-Agent (a project URL is fine):
    cd $JOB && FILMCREDITS_CONTACT='https://shuffle.subimusic.me' nice -n 19 $PY -m filmcredits --catalog $SHUF/catalog.db --db $SHUF/film_credits.db --run --tracklists --max-minutes 120
   Re-running step 1 or 3 is how new songs get their credits; a nightly line is NOT installed.

Counts only:     cd $JOB && $PY -m filmcredits --catalog $SHUF/catalog.db --db $SHUF/film_credits.db --report

Rollback:
    for f in $NV_PATCHED; do cp -a $BK/nv/\$f $NV/\$f; done
    xargs -r -I{} rm -f $NV/{} < $BK/new-nv.txt
    rm -rf $JOB/filmcredits && { [ -d $BK/filmcredits.old ] && cp -a $BK/filmcredits.old $JOB/filmcredits || true; }
    sudo systemctl restart navivibe
(film_credits.db stays; it is harmless and re-usable. Delete it to start over.)
EOS
