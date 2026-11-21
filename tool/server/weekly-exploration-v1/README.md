# weekly-exploration-v1: Weekly Exploration

For `/opt/tg-fetcher` and `/opt/shuffle-server` on subiserver. **Needs exportify-v1** (and so server-fixes-v1, moods-v1/v2).
Built on the live code read on 21 Nov 2026. User-facing description and the picking rule: `docs/weekly-exploration.md`.

About twenty songs a week the listener does not own, from their own taste; a 30 s preview each (Apple's clip), Keep
(fetched at night) or Not for me, untouched picks expire after 2 weeks.

## What it adds

| Where | What |
|---|---|
| tg-fetcher, new | `tgfetch/weekly_exploration.py` (sources, picking, Keep / skip / expiry / weekly cap, tables `weekly_picks`, `weekly_tombstones`, `weekly_prefs`, `weekly_builds` in fetch.db), `tgfetch/weekly_exploration_api.py` (`/weekly/*`) |
| tg-fetcher, 2 anchored patches | `api.py` registers the routes; `exportify.py` `main()` (the 10-minute timer pass) first expires old picks and releases Keeps that were over the weekly cap |
| shuffle server, new | `navivibe/weekly_exploration.py`: taste "seeds" from the listener's plays, optional ListenBrainz hints, the `/weekly/exploration*` routes |
| shuffle server, 2 anchored patches | `server.py` registers the routes; `hardening.py` gives them the `/fetch` rate class |
| Fetching | **Not new.** A Keep adds a song to a per-listener Exportify import named "Weekly Exploration", so `exportify.tick()` fetches it: same night window (1–7 am), per-night cap, disk floor (40 GB) and one batch at a time. No second scheduler, and **no new timer**: the exportify timer must be on |

## Install (on the server, as `subi`, no sudo)

    cd ~/weekly-exploration-v1        # wherever this folder was copied to
    bash install.sh

Tests a scratch copy first (tg-fetcher's whole suite; the shuffle server's suite before and after the patch, so a test
that already failed does not block it), backs up to `/opt/tg-fetcher/backups/weekly-exploration-v1-<time>`, patches, tests
the live tree and puts everything back if a test fails. After "Done" it prints the restart (`sudo systemctl restart tg-fetcher navivibe`)
and the rollback. Nothing is restarted by the script. Safe to re-run.

## HTTP contract (shuffle server, signed-in, download access required; 403 without a call to tg-fetcher otherwise)

    GET  /weekly/exploration                   the page: enabled, cap, week, kept_this_week, building, picks[], night
                                               (the first open of a week also sends the seeds: the list is built in the background)
    POST /weekly/exploration/<id>/keep         {state, download:{state: waiting|queued|ready|failed, song_id}}
    POST /weekly/exploration/<id>/skip         Not for me
    POST /weekly/exploration/<id>/restore      undo a Not for me
    PUT  /weekly/exploration/prefs             {enabled?: bool, cap?: 0..25}

A pick: `id, title, artist, album, year, duration_s, cover_url, preview_url, reason, kind (near|far), state
(pending|kept), week, expires_at, download`. Both URLs are https links on Apple's CDN or they are null.

## Tests

Scratch copy of the live code on Windows (so the platform failures below also fail without these patches):

- tg-fetcher: **526 passed**, 1 failed (`test_concurrency`: the importer on Windows), 27 skipped; 27 of the passes are new
  (`tests/test_weekly_exploration_v1.py`: a fixed history and fake Deezer / iTunes, picking rules, filters, Keep through
  `exportify.tick()` at night and at noon, the disk floor, the weekly cap, Not for me / Undo / artist rest, expiry and
  tombstones, throttling and call budget, the routes, a failing build). `tests/test_sfv1_autoimport.py` needs `fcntl` and was left out.
- shuffle server: **906 passed**, 9 failed (ffmpeg / recognize, v3 replay, a flow state-file path: Windows), 7 skipped; 14 of the
  passes are new (`navivibe/tests/test_weekly_exploration_v1.py`: seeds from a fixed history, ListenBrainz hints with a fake
  service, the routes, the rate class). `test_reshuffle_v1.py` needs scipy models and was left out.

## Not done on purpose

See `docs/weekly-exploration.md` ("Not built"). Not verified live: real Deezer / iTunes answers through a full build, the
ListenBrainz hints, a real Keep and night fetch.
