# data-queue-v1

The admin's **hidden weekly data queue**: songs that reach the library *without* real Spotify audio features wait in a
database table (never a Navidrome playlist, never visible to a non-admin). Once a week the admin takes the next 200,
moves them to Spotify with a free transfer service, exports that playlist with Exportify and uploads the CSV on one
page of the app. Spotify's real numbers are stored for what matched; what Spotify does not have gets predicted numbers,
stored apart and marked `feature_source = 'predicted'`. Separate from the Exportify direct import (exportify-v1).
Built on the live code read on 23 Nov 2026. Needs exportify-v1 installed.

## The flow
1. **Arrival.** `tgfetch/db.py update_job` hands every job that becomes `ready` (a song is in the library with its
   Navidrome id) to `tgfetch/data_queue_hook.py`. That is the single place every path ends in: requests, pasted
   playlist links, YouTube lists, Exportify wishlist batches, import retries. The hook adds the song to the queue
   unless `spotify_details.db` already holds a row with **both energy and valence**. It is wrapped twice (in `db.py` and
   in the hook) so a queue error can never fail an import; `DATA_QUEUE_OFF=1` in tg-fetcher's `.env` switches it off.
   A wishlist song whose Exportify features land a moment later is dropped before it reaches a batch.
2. **Batch.** `POST /data-queue/batches` (the app's "Make this week's batch"). At most **200**; ISRC songs first, then by
   score = 2 x plays by everyone (listening logs) + 1 x recently added + 1 x coverage gap (distance in the audio
   embedding from every Spotify-labelled song); the same recording (ISRC or clean title + artist) counts once; songs
   in an open batch are never picked again; a song that left the library is skipped; tags/ISRC/length are refreshed
   from the catalog. A batch open for **30 days** is released (its songs wait again).
3. **Files.** `GET /data-queue/batches/<id>/file.csv|txt` write exactly what `tool/exportify/library_export.py` writes
   (UTF-8 with BOM, CRLF, columns `title, artist, album, album artist, duration, isrc`; TXT `Artist - Title`). A test
   compares both byte for byte.
4. **Upload.** `POST /data-queue/batches/<id>/upload` takes the Exportify CSV (JSON `{name, csv}` or raw text).
   Limits **8 MB / 20,000 rows**. Rows are matched to the batch's songs by the exportify-v1 rules (ISRC, else clean title
   + same version words + an artist in common + length within 5 s; `data_queue_tools/spotify_match.py`). Matched rows
   with energy and valence go to `spotify_details.db` (real). The rest (not on Spotify, or on Spotify without
   features) get energy / valence / danceability / acousticness from a ridge regression on the effnet_discogs
   embedding (`data_queue_model.py`, the functions of `calibrate_audio_features.py`), kept in `data_queue.db` table
   `predicted` (a CHECK constraint allows only `feature_source = 'predicted'`). Songs without an embedding, or fewer
   than 50 labelled songs for a feature, get no prediction (their note says `no_prediction`).
   **The same file twice changes nothing** (SHA-256 recorded; the answer says `repeated: true`); a different file for a
   closed batch is refused (409). The CSV is never kept or logged; "Added By" is never read.
5. **Audit.** Every batch has a trail (created, each download, uploaded with counts, repeated upload, released).

## Who can see it
Every route needs the server's sign-in (`require_auth`) and the user to be in `NAVIVIBE_ADMIN_USERS` (the same
`ADMIN_USERS` the mood editor uses). A signed-in non-admin gets the **same 404 as for a route that does not exist** and
nothing is read; no sign-in gives the usual 401. The app finds out who is admin with the existing `GET /moods/me`.

| Route | Does |
|---|---|
| `GET /data-queue/status` | counts, next batch preview (<= 200), open batch, coverage (real / predicted / none), quality summary, links, limits |
| `POST /data-queue/batches` | the open batch, or a new one (`{"new": true}` makes another from what still waits) |
| `GET /data-queue/batches` | history, newest first, with each batch's summary |
| `GET /data-queue/batches/<id>` | its songs with state/note and the audit trail |
| `GET .../file.csv`, `.../file.txt` | the transfer file |
| `POST .../upload`, `POST .../release` | apply an Exportify CSV / put the songs back |

States of a song: `waiting`, `in_batch`, `done` (real features), `not_on_spotify` (predicted), `skipped` (left the
library, or on Spotify but exported without features).

## Install (owner commands)
From the repo checkout on your PC:
```
scp -r tool/server/data-queue-v1 subi@100.99.105.51:~/
```
On the server (as `subi`, no sudo):
```
cd ~/data-queue-v1
bash install.sh --check      # scratch tests only, nothing live is touched
bash install.sh              # tests, back up, patch, test again; puts everything back if a test fails
sudo systemctl restart navivibe tg-fetcher
```
Seed the queue with the library songs that still lack real Spotify features (the same selection as
`tool/exportify/library_sample.py --fill-gaps`; `--exclude` takes your earlier batch files and Exportify CSVs so
songs already exported or covered are skipped; remixes, sped-up, live, very short songs are not queued, Spotify would
not match them):
```
cd /opt/shuffle-server && venv/bin/python -m navivibe.data_queue backfill --dry-run
cd /opt/shuffle-server && venv/bin/python -m navivibe.data_queue backfill --exclude ~/batch1.csv --exclude ~/my_playlist.csv
```
Re-running adds nothing already queued. Rollback is printed by `install.sh`.

## Tests
`files/navivibe-tests/test_data_queue_v1.py` (store, ranking, batches, release, files, upload, idempotency, prediction,
caps, routes incl. non-admin 404, backfill, plus repo-only checks that the copies in `data_queue_tools/` are
byte-identical to `tool/exportify/` and the ridge functions give the same numbers as `calibrate_audio_features.py`) and
`files/tests/test_data_queue_v1_hook.py` (arrival, sources, features present, failure isolation, kill switch).

## Not verified / limits
- Not installed or run on the server; the tests ran locally against a read-only snapshot of the live code, and the two
  patches applied cleanly to it. `install.sh --check` repeats that on the server.
- No real Exportify CSV was used (privacy); the CSV in the tests follows Exportify's published column names.
- The match code is `tool/exportify/spotify_match.py` (same rules as exportify-v1, no server imports) rather than
  importing `tgfetch.library_sweep` into the web server's process.
- Predicted values are stored and shown as coverage; **Flow / Smart Shuffle do not read them yet** (they read the
  catalog's own estimates). Wiring them in is a separate step.
- A prediction fit takes a few seconds inside the upload request (four features, cross-validated ridge).
- Soundiiz's free tier (200 tracks per playlist) and the match rate on Spotify were not tested.
