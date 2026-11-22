# album-overnight-v1: Complete the album overnight

When a song you asked for lands in the library, its **film album** is looked up and the tracks you do not
have are queued to download at night. Settings › Album Overnight shows the queue and cancels it.
Full description: `docs/album-overnight.md`. Not installed until the user runs `install.sh`.

| | |
|---|---|
| Fetching | **Not new.** The tracks join one Exportify import per listener named "Album Overnight", so `exportify.tick()` fetches them: night window (1–7 am), per-night cap, disk floor (40 GB), one batch at a time, pause / cancel. No second scheduler, no new timer: the Exportify timer must be on. |
| New code | `tgfetch/album_overnight.py` (find, queue, show, cancel), `tgfetch/album_overnight_api.py` (`/album-overnight/*`), `navivibe/album_overnight_proxy.py` (`/exportify/album-overnight*` for the app). |
| Patches | `tgfetch/api.py` (register routes, inserted before exportify's line), `tgfetch/exportify.py` (the timer pass calls `run_pass` after `n = …`), shuffle `server.py` (register the proxy). Anchored, exact-match, idempotent, and in either order with weekly-exploration-v1. `hardening.py` is **not** patched: the paths are under `/exportify/`. |
| Needs | exportify-v1 (and server-fixes-v1). |

## How it decides

1. **Off until turned on**, per listener. Turning it on records the time; only songs that land after it count.
2. A song counts when it is a job `ready`/`imported` for that listener, **not** from Exportify / Weekly Exploration
   (`result_id exportify:…`) and **not** part of a batch of more than 5 songs (a playlist or chart import).
   Seen once (`album_seen`); looked at for 3 days at most.
3. The album comes from the iTunes Search API (public, no key; only a title, artist and album name are sent, never a
   user name or id): by album name first, else by song. It is accepted **only if the song that triggered it is in
   the track list** (clean title + version words), so a different album with the same name is never queued.
4. Skipped: singles, compilations (> 40 tracks), non-film albums (default "Film albums only": the name says
   soundtrack / score / motion picture / "(From …)", or iTunes' genre is Soundtrack, Bollywood, Tamil, Telugu,
   Malayalam, Kannada, Marathi, Bengali, Gujarati, Punjabi, Bhojpuri), tracks under 20 s, karaoke / instrumental
   cuts, anything already owned (same matcher as the Exportify import, a "maybe owned" length too), and an album
   already handled or cancelled.
5. At most **25 tracks an album** (5 / 10 / 15 / 25 / 40 in the app) and **150 waiting in all**; when the queue is
   full the song is looked at again later. Per night: 10 / 20 / 30 (default) / 50 / 100, the plan's `per_night`.
6. Tracks keep album order (`priority = list`).

## Cancelling

* **Cancel an album**: its tracks that are not with the bot yet are deleted from the queue (a row shared with another
  wishlist stays there), the album is never queued again. A track already in a running batch finishes ("already on
  its way").
* **Cancel all**: the same for every album. When nothing is left the plan is set to `cancelled`.
* **Turning it off** pauses the Album Overnight plan (what is queued waits) and stops looking at new songs; turning it
  on resumes.

## Tests

`bash install.sh --check` runs the whole thing on a scratch copy of `/opt/tg-fetcher` and `/opt/shuffle-server`
and installs nothing: the tg-fetcher suite with `tests/test_album_overnight_v1.py` (28 tests, no network), the
patches run twice (idempotent), and the shuffle server's suite before and after the patch, so a test that already
fails is not blamed on this package. `bash install.sh` then installs (backup, patch, test live, restore on failure).

## Not built

* Albums for songs that arrive through a playlist / chart / Exportify / Weekly Exploration import (too many; the
  user can turn those albums on one at a time by fetching one song).
* A "complete this album" button on an album page (the app can do it with one song of it; the server side would be a
  small route).
* A second source for albums iTunes does not have (MusicBrainz), and a per-album "keep it" preview.
* Seeing unreleased / regional editions: iTunes India storefront only.

## Known edges

* Exportify keeps at most 20 imports per user (`prune_old`); if the listener has many playlist imports the oldest
  import, which may be this one, is dropped with its rows. The queue then shows those tracks as waiting; the next
  album recreates the import. (Same as Weekly Exploration.)
* The album listing is the iTunes edition; a track whose title differs from the library's spelling can be fetched
  twice, but the fetcher's duplicate check turns that into "owned".
