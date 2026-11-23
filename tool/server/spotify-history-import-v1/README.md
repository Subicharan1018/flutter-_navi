# spotify-history-import-v1: import a Spotify "Extended Streaming History" with real skip data

For `/opt/tg-fetcher` and `/opt/shuffle-server` on subiserver. Needs **history-import-v1** installed first (it brings
exportify-v1 and server-fixes-v1). User-facing description: `docs/spotify-history-import.md`. App: `lib/features/spotify_import/`.

Built on the live code read on 23 Nov 2026 (read-only copy). Scratch results (Windows, Python 3.10): tg-fetcher 59 new tests
pass; shuffle-server proxy 6 new tests pass against the live `navivibe/` with `patch_proxy.py` applied. Whole tg-fetcher suite on a
fresh read-only copy of the live tree (24 Nov 2026): 770 pass in either install order with matcher-v2 (see below).

## Install order with matcher-v2

Either order works (both tried on a copy of the live tree, same 770 pass, no new failure). Spotify first, then matcher-v2 gives
the Spotify matcher the album too (matcher-v2 patches `spotify_history.py`); matcher-v2 first just skips that one optional
edit and Spotify matches without the album. `patch_tgfetch.py` here only touches `api.py`, which matcher-v2 does not.

## Why history-import's own routes still refuse "spotify"

`spotify_history.py` registers the source name in `history_import.SOURCES` (the Wishlist title and undo need it). That alone
would make `create_job("spotify")` valid on history-import's `/history-import/jobs` and let `/step` try a Last.fm fetch for a
Spotify job. The module therefore wraps `hi.create_job` and `hi.step` to refuse it (no file of another package is patched;
history-import-v1's `test_account_names_are_checked` passes unchanged, and its source now uses a made-up name anyway). Nothing in this folder
was installed on the server by its author; the owner runs `install.sh` (below).

## What it does

The app reads the person's ZIP **on the device** and sends, per music play, only: end time, title, artist, album, ms played,
`reason_end`, `skipped`. IP, country, platform, offline/connection fields, URIs, episodes, audiobooks, video files and
Private Session plays never leave the phone (the proxy drops unknown fields again). Pages of up to 1,000 plays go to
`POST /spotify-import/jobs/<id>/page`.

* **Validation** (like play-events-v2): a row that is not an object, has no title/artist, a time before 2006 or in the
  future, or `ms_played` negative / over 6 h is refused, counted by reason in the job (`rejected`) and reported to the app.
* **Skip rule** (`skip_decision`): under 30 s ended by `fwdbtn`/`backbtn`, or flagged `skipped` under 30 s = **skip**;
  30 s or more, or ran to its end (`trackdone`), = **listen** with listen ratio = seconds / library song length
  (a listen under half is stored as a `skip` event with `end_reason = partial`, because play-events-v2 requires a `complete`
  to be at least half heard). A short play that ended another way (logout, app closed, remote) is *unclear* and not imported.
  The basic export has no reason, so a play under 30 s is a skip there.
* **Matching** = the Exportify matcher (clean title + an artist in common, remix/sped-up/live words compared). Spotify files
  have no ISRC and no track length, so neither is used.
* **Log rows**: `session_id = import:spotify`, `origin = import`, `schema_version 2`, real `seconds_played`,
  `play_id = imp:spotify:<hash of end time, artist, title>` (importing again adds nothing), start time = end time minus
  ms played, and the 2-minute near-duplicate rule. No weather, no genre.
* **Wishlist**: unmatched songs that were *listened to* go on the user's Wishlist ("Spotify history", popularity = listens,
  max 100, the wishlist's own caps; the plan stays `idle`, nothing is fetched until the user starts it). Songs only skipped
  are not wished for.
* **Undo** = the existing "Remove Imported History" (`/history-import/jobs/<id>/undo`).
* Per user only: every route filters on the signed-in user; the log is the user's own `<user>_listening_log.db`.

## Files

| File | |
|---|---|
| `files/tgfetch/spotify_history.py` | validation, skip rule, matching, log writer, jobs (reuses `history_import.py`) |
| `files/tgfetch/spotify_history_api.py` | routes `/spotify-import/jobs[/<id>[/page or /finish]]` |
| `files/navivibe/spotify_import_proxy.py` | the shuffle server's signed proxy (shape and size checked, unknown fields dropped) |
| `patch_tgfetch.py` | 1 anchored patch: `api.py` registers the routes after history-import's |
| `patch_proxy.py` | 4 anchored patches: `server.py` (register, and a 1 MB body cap for `/spotify-import`), `hardening.py` (rate class `spotify_import`: burst 20, 1/s; the default `fetch_write` is 12/min and a 50 MB export is ~300 pages) |
| `files/tests`, `files/navivibe-tests` | 58 + 6 tests, made-up songs |
| `files/tools/dryrun.py` | the whole pipeline on a real export into a scratch DB; prints counts only |

## Install (owner, on the server as `subi`, no sudo)

    cd ~/spotify-history-import-v1     # wherever this folder was copied to
    bash install.sh --check            # scratch-copy tests only: nothing live is touched
    bash install.sh                    # tests a scratch copy, backs up, patches, tests the live tree, restores on failure
    sudo systemctl restart tg-fetcher navivibe

## Dry run on any export (no server touched)

    scp subi@100.99.105.51:/opt/shuffle-server/catalog.db .        # read-only copy
    PYTHONPATH=<checkout of /opt/shuffle-server> python files/tools/dryrun.py "<export folder>" catalog.db --tg <copy of /opt/tg-fetcher> --out report.json

## Import for a user (when they agree)

In the app (a build with this version): Settings > Import > **Import Spotify History** > Choose Export File (the ZIP from
Spotify, or its `Streaming_History_Audio_*.json` files) > check the summary > **Import N Plays**. Closing the app is safe:
choose the same file again and it carries on; nothing is counted twice. **Remove Imported History** on the same screen takes
it all back.

## Rollback

`install.sh` prints the exact commands. By hand: restore `api.py`, `server.py`, `hardening.py` from the backup folder, delete
the new files, restart. Data: `DELETE FROM play_events WHERE play_id LIKE 'imp:spotify:%';` in the user's log; the
`spotify_jobs` table is harmless.

## Not verified

`install.sh` on the server, the real `load_library()` (Navidrome DB) instead of the catalog copy, the nightly run reading the
imported plays, Android/TV rendering, a 50 MB ZIP on a phone.
