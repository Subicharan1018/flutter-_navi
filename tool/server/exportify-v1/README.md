# exportify-v1: import a Spotify playlist from an Exportify CSV

For `/opt/tg-fetcher` and `/opt/shuffle-server` on subiserver. Needs **server-fixes-v1** installed first
(it supplies `youtube_batch.py`, `library_sweep.py` and `titles.py`, which this reuses).
Built on the live code read on 21 Nov 2026. Scratch-copy results: tg-fetcher 500 passed (43 of them new),
shuffle server 718 passed (7 new). User-facing description: `docs/exportify-import.md`.

## What it does

1. `POST /exportify/imports {name, csv}` reads the file (BOM, CRLF, cp1252 and odd quoting tolerated;
   8 MB and 20,000 rows at most; a row needs a title; control characters stripped; nothing in the file
   is ever logged or kept, only the rows it becomes).
2. Matches each unique song to the library **by ISRC first**, then by clean title + an artist in common +
   length within 5 s (`library_sweep.Index.find`: "(From …)", "- From …" and "Original Motion Picture
   Soundtrack" ignored, version words compared, so a remix / sped-up / reprise / karaoke never matches the
   plain song). A title + artist match at another length (within 25 s) stays on the wishlist and is counted
   as "maybe owned".
3. Stores, per user, in `fetch.db` (`exportify_imports`, `exportify_songs`, `exportify_plans`): every song's
   state (`owned`, `wishlist`, `queued`, `downloaded`, `failed`, `skipped_disk`), plus Spotify's audio
   features per ISRC (`exportify_features`; kept, used for nothing yet).
4. **Fetching** is a plan: order (most popular first, or the file's order), minimum popularity, songs a
   night (default 100), the disk floor (default 40 GB), night only (1–7 am, default on). `tick()` is what
   moves it, from the Start button and from a 10-minute timer:
   * **disk guard**: free space on `LIBRARY_DIR`, minus the floor, minus the estimated size of songs already
     queued (0.51 GB per hour of music, measured). Not enough room for the next song → the plan is
     `paused_disk` ("Paused: disk is low (31 GB free, floor 40 GB)."), and it resumes by itself when space
     returns. A batch is trimmed so it never goes past the floor; the song that would have crossed it is
     `skipped_disk` until there is room.
   * **cap**: songs queued in the last 20 h count against "songs a night" (and `JOBS_PER_DAY` if set).
     A cancelled batch gives its places back.
   * **one batch at a time** (25 songs, about 8 minutes of bot time), claimed with `BEGIN IMMEDIATE` so the
     service and the timer can't both queue one.
   * **the same song in two imports** is fetched once (1,518 of the user's songs are in both playlists).
   * failed songs are tried again after 3 days, twice at most, or at once with "Try them again".
5. The batch is an ordinary tg-fetcher batch (`kind songs`, link `exportify:<import id>`). The worker fetches
   it **by name, exactly like a YouTube list** (`youtube_batch.run`): each song is searched on the bot
   (up to 6 queries), every result is scored by title, version words, artist and length, and only a good
   match is taken. The bot is never sent the `exportify:` link. Owned songs are settled without the bot.
   These batches don't count against a user's cap of pasted playlist links.

## Files

| File | |
|---|---|
| `files/tgfetch/exportify.py` | parse, match, store, plan, `tick()`, `python -m tgfetch.exportify tick` |
| `files/tgfetch/exportify_api.py` | the internal `/exportify/*` routes (signed, download access needed) |
| `files/navivibe/exportify_proxy.py` | the shuffle server's `/exportify/*` proxy (same rules as `/fetch`) |
| `patch_tgfetch.py` | 3 exact, idempotent patches: `api.py` (register routes), `worker.py` (`exportify:` → by name), `db.py` (link cap) |
| `patch_proxy.py` | 3 exact patches: `server.py` (register + 12 MB body for `/exportify`), `hardening.py` (rate class) |
| `systemd/tg-fetcher-exportify.{service,timer}` | the 10-minute pass (optional) |
| `files/tests`, `files/navivibe-tests` | synthetic songs only, no network, no Telegram |

## Install (on the server, as `subi`, no sudo)

    cd ~/exportify-v1        # wherever this folder was copied to
    bash install.sh

It tests a scratch copy first (tg-fetcher's whole suite; the shuffle server's suite before and after, so a
test that already failed doesn't block it), backs up to `/opt/tg-fetcher/backups/exportify-v1-<time>`, patches,
tests the live tree, and puts everything back if a test fails. It prints the `sudo` lines (restart, the timer,
rollback). Nothing is restarted by the script.

## HTTP contract (shuffle server, signed-in, download access required)

    POST   /exportify/imports                  {name, csv}            201 summary + owned_ids
    GET    /exportify/imports                  [summary]
    GET    /exportify/imports/<id>             summary (counts by state, plan, free_gb)
    GET    /exportify/imports/<id>/songs/<state|all>/<page>   200 per page, in the file's order
    GET    /exportify/imports/<id>/owned       {ids}  Navidrome ids already owned, file order
    POST   /exportify/imports/<id>/estimate    {plan fields}  {songs, gb, hours, free_gb, floor_gb, fits, nights, bot_hours}
    PUT    /exportify/imports/<id>/plan        {priority: popularity|list, min_popularity, per_night, disk_floor_gb, night_only}
    POST   /exportify/imports/<id>/start | pause | cancel | retry-failed
    POST   /exportify/imports/<id>/playlist    {playlist_id}   the app made the user's playlist
    DELETE /exportify/imports/<id>

The playlist from the owned songs is made **by the app with the user's own login** (like Send a Playlist), so
the user owns it; the server only remembers its id.

## Not done on purpose

* Spotify history (streaming zip), Liked Songs, Last.fm: the rest of R12.
* The audio features are stored, not used.
* No new bot path: the bot is searched by name, as for YouTube lists. A Deezer ID per song would be faster
  but needs a lookup step that hasn't been built.
