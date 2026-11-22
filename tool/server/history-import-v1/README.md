# history-import-v1: import past ListenBrainz listens / Last.fm scrobbles

For `/opt/tg-fetcher` and `/opt/shuffle-server` on subiserver. Needs **exportify-v1** (the Wishlist) and
**server-fixes-v1** installed first. User-facing description and design: `docs/history-import.md`.

Built on the live code read on 22 Nov 2026 (scratch copy). Scratch results (Windows): tg-fetcher 19 new tests pass
(the rest of its suite: 558 passed, 1 existing failure that needs Linux, `test_concurrency`); shuffle server proxy 4 new
tests pass next to exportify's 6.

## Files

| File | |
|---|---|
| `files/tgfetch/history_import.py` | job table, the two readers, matching, the listening-log writer, dedupe, undo |
| `files/tgfetch/history_import_api.py` | internal routes `/history-import/jobs[/<id>/step\|cancel\|undo]` |
| `files/navivibe/history_import_proxy.py` | the shuffle server's authenticated, signed proxy to those routes |
| `patch_tgfetch.py` | 1 anchored patch: `api.py` registers the routes after exportify's |
| `patch_proxy.py` | 2 anchored patches: `server.py` registers the proxy, `hardening.py` gives `/history-import` the "fetch" rate class |
| `files/tests`, `files/navivibe-tests` | recorded-style fixtures (`files/tests/fixtures/*.json`, made-up songs), HTTP replaced, no network |

## Install (on the server, as `subi`, no sudo)

    cd ~/history-import-v1        # wherever this folder was copied to
    bash install.sh --check       # scratch-copy tests only: nothing live is touched
    bash install.sh               # tests a scratch copy, backs up, patches, tests the live tree, restores on failure

Then the printed `sudo systemctl restart tg-fetcher navivibe`. No new service, timer or environment variable.
(`NAVIVIBE_LOG_DIR` is read if set, same as the shuffle server; default `/DATA/AppData/navivibe/listening_logs`.)

## Data

* `fetch.db`: `history_jobs` (cursor, counters), `history_seen` (one row per listen id: the dedupe), `history_tracks`
  (per user + source + song: plays, first/last time, library id or null). The Wishlist rows are `exportify_songs`.
* `<user>_listening_log.db`: `play_events` rows with `session_id = import:listenbrainz|lastfm`, `play_id LIKE 'imp:%'`.
  To take back by hand: `DELETE FROM play_events WHERE play_id LIKE 'imp:%';` (the app's Remove button does it per source).

## HTTP contract (shuffle server, signed in, download access required)

    POST /history-import/jobs            {source: listenbrainz|lastfm, account, full?}   201 new / 200 the unfinished one
    GET  /history-import/jobs            [summary]
    GET  /history-import/jobs/<id>       summary
    POST /history-import/jobs/<id>/step  {secret?}  one page → summary + done + wait_s (+ fatal)
    POST /history-import/jobs/<id>/cancel | undo

`secret` is the Last.fm API key (32 hex) or a ListenBrainz token; used for that request, never stored or logged.

## Not verified

The live services (no network in tests), the real library match rate, the real listening-log files and the nightly
run picking the imported plays up, `install.sh` on the server, Android/Windows rendering of the screen.
