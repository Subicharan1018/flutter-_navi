# server-fixes-v1: tg-fetcher fixes

For `/opt/tg-fetcher` on subiserver, plus one small patch to the shuffle server's `/fetch` proxy.
Built on the live code read on 16 Nov 2026 (baseline: 397 tg-fetcher tests and 22 proxy tests
passed). The proxy passes `/fetch/searches` answers through as they are and does not check links.
Its only change is forwarding `force` ("Search online anyway"), which it used to drop
(`patch_proxy.py`).

## What it fixes

| # | Problem | Fix | Where |
|---|---------|-----|-------|
| 1 | The chart song "Raga of Revenge" doesn't play and has no cover. Its `nd_song_id` (`2hfFjUHc…`) is an old file that Navidrome marks `missing`; the song was re-imported as `0RLJDGIP…`. | **Library sweep.** A chart row whose id is no longer a live song is re-matched: first by the charts' own matcher (`_owned`), then by normalised title and main artist ("(From …)", "Original Motion Picture Soundtrack" and " - subtitle" dropped, version words compared, length within 10 s). If nothing matches, the row goes back to pending (`match`/`queued`) so the charts fetch it again. The sweep runs at every snapshot and whenever Navidrome's scan time, missing count or newest change moves (checked every 2 min from the trending loop). The chart API now gives out only ids that are live songs. Dry run on a copy of the real `fetch.db`: Raga of Revenge and Manchild re-pointed, Kaadhal En Kaviye back to pending. | `tgfetch/library_sweep.py`; `trending.py` (snapshot, tick, `chart()`) |
| 2 | An online song search whose text equals a library title (or sounds like one) ends as "already in your library" whatever the artist, so the bot never searches. | `in_library` only when the text names the title **and** the artist (title first or last, every other word in that song's artist credit). A title alone runs the bot search as usual and adds `owned_hint` (see the contract). A user's newer search **supersedes** their older one that is still queued or running: switching tabs no longer waits behind a slow song search. A running search stops before its next bot request. | `tgfetch/search_owned.py`; `worker.py` `run_search`; `api.py`; `db.py` |
| 3 | The queue's failed list shows songs the user now owns ("Kannala Kannala - The Melting Point of Love" → owned as "Kannala Kannala"). | The same sweep records failed jobs whose song is now in the library (same normalised title, at least one artist in common, same version words, length within 15 s) in a new `resolved_failures` table. `failed_songs` leaves those out, with one indexed `NOT IN`, so `/queue` stays as fast as before. Dry run: 187 of 368 failures resolved; a sped-up, remix or revival cut never matches the plain song. | `library_sweep.py`; `db.py` `failed_songs` |
| 4 | YouTube / YouTube Music playlist links are refused. | Accepted, but used **only as a list of names**. `ytmusicapi` 1.12.3 (pinned, no sign-in) `get_playlist` reads titles, artists, album and length, in a thread with a 20 s timeout and a 300-song cap. Titles are cleaned by the TODO.md rules (`titles.py`, tested on 4 recorded real lists). The preview marks owned songs. The batch **never sends the link to the bot**: each song not owned is searched on the bot by name (the chart query forms of the title and its alternatives, 6 at most) and scored by title, version words, artist and length (15 s slack, a plain video may be up to 60 s longer). Nothing is ever requested from YouTube but the list. | `tgfetch/youtube_list.py`, `titles.py`, `youtube_batch.py`; `links.py`; `worker.py`; `docs/backend/SECURITY.md` |
| 5 | Songs copied straight into `/DATA/Media/Music` (Navidrome's `/music`, `LIBRARY_DIR`) skip the bot's pipeline. | **Auto-import**, run by a systemd path unit (inotify on the folder) and a 10-minute timer. Each file waits until it stops changing (30 s). It is then backed up to `/DATA/Media/.autoimport-backup/<day>/` (kept 30 days) and gets the importer's tagging (FLAC; `TGFETCH_SOURCE=dropped`), ReplayGain if missing, and synced lyrics if missing. A failed write puts the backup back. Then: Navidrome scan request (explicit only when `ND_USER`/`ND_PASS` are in `.env`; otherwise Navidrome's watcher and hourly scan find it), wait for the song id, library sweep (charts and failed downloads), and the doctor's per-song fixes once the file has been quiet for 10 min (only if the doctor is enabled; undo with `bin/doctor undo autoimport-…`). The shuffle server's own 10-minute catalog loop ingests the song (enrich, language, audio). Once it is in `catalog.db`, its mood label is asked for straight away. Nothing is moved or deleted. The bot's own `tg-fetcher/` folder, hidden files and code folders are skipped. The install records the 1,043 files already there; they are never processed. There is no Wishlist on the server yet, so there was nothing to resolve there. | `tgfetch/autoimport.py`; `systemd/*` |

## App contract (for the app sessions)

### Online search: `GET /fetch/searches/{id}` (proxied as is)

* `status`: as before, plus **`superseded`**. A search the same user replaced with a newer one
  (kinds `song`, `album`, `artist`, `playlist`, `label`; link previews and artist song lists are
  never superseded). `note` = "Replaced by a newer search". It is not an error: drop it, and search
  again if that tab is opened again with no result. (Today the app maps unknown statuses to
  `failed`; change that.)
* `status: "in_library"` now only happens when the text names the title **and** the artist
  ("pondatti anirudh", "anirudh pondatti"). Its `library.matches[0]` is the song, as before.
* New **`owned_hint`**: `null` or
  `{"song_id": "…", "title": "…", "artist": "…", "album": "…"}`. It is set on `done` / `no_results`
  searches when the library has a song with that exact title (or that title in another spelling).
  Show it as the banner "You may already have: <title> — <artist> · Play" **above** the results. It
  never replaces them.
* `library` keeps its shape. On a `done` search `library.verdict` can still be `"in_library"` (the
  title matched). Don't treat that as the full-screen "Already in your library" state; key that on
  `status == "in_library"` only.
* New per-candidate fields (all searches): `source_title` (string or null) and `unreadable` (bool).
  See below.

### "Search online anyway": `POST /fetch/searches` with `force`

* Send either `{"query": "…", "force": true}` in the body, or `?force=1` (also `true` / `yes`) on
  the URL. The shuffle server's proxy forwards either one to tg-fetcher as `"force": true`.
* It only applies to `kind: "song"` (other kinds never check the library). A forced search never
  ends as `in_library`: the bot is always asked. `owned_hint` is still set when the library has a
  song with that title, so the banner can stay.
* Use it for the button shown on an `in_library` result. A forced search supersedes the user's
  older one like any other search.

### Playlist links: `POST /fetch/searches {"link": …}`

Accepted links (the server's rules; mirror them in `playlistLinkProblem`):

| Site | Rule |
|------|------|
| Deezer | unchanged: `https://(www.)deezer.com/[xx(-yy)/]playlist/<digits>` |
| Spotify | unchanged: `https://open.spotify.com/[intl-xx/]playlist/<10-40 alnum>` |
| YouTube | scheme `https` only; host `youtube.com`, `www.youtube.com`, `m.youtube.com` or `music.youtube.com`, path `/playlist` or `/watch` (trailing `/` ok); or host `youtu.be` with path `/<video id>`. Exactly one `list` query parameter matching `^[A-Za-z0-9_-]{13,64}$`. Other parameters, `#fragment` and `user:pw@` are ignored. |

Refusals (422, `detail` is shown as is):

* `RD…`: "YouTube mixes made for you can't be read. Save it as a playlist first and share that link."
* `LL` / `LM` / `WL`: "Liked songs and Watch later are private. Copy them into a public playlist and share that link."
* `UU…`: "That's a channel's uploads, not a playlist. Open a playlist and copy its link."
* No `list`, two `list`s, or another path: "That YouTube link isn't a playlist. Open the playlist and copy its link."
* A bad id: "That YouTube playlist link doesn't look right. Copy it again from Share."
* `http://`: "Paste the playlist's https:// link."
* Apple Music: "Only Deezer, Spotify and YouTube playlist links work. The music bot doesn't take this site."
* Anything else: "Only Deezer, Spotify and YouTube playlist links work."

The stored `query` of a YouTube preview is `https://music.youtube.com/playlist?list=<id>`. Preview
candidates have `title` (cleaned: the bot's search name), `artist` (may be empty for plain uploads),
`album` (the film hint, may be empty), `duration_s`, `library` (`in_library` / `not_found`), and
`cover_url: null` (no YouTube images). They also carry `source_title`, the original YouTube title:
show it under the cleaned title so a wrong reading can be unticked. When `unreadable` is `true`,
the title could not be read: show "Couldn't read this title". It is not searched, and its job fails
with that reason.

Download as before (`POST /fetch/batches {"search_id"}`). Songs not found on the bot fail with
`error` = `not found on the music bot (YouTube: “<original title>”)`, shown in the batch items and
the queue's failed list. Speed: about 20 s per song (the bot is searched by name), so a 100-song
list takes about 35 minutes. Suggested sheet text: "Deezer, Spotify or YouTube playlist link".

## Install

From the PC:

```bash
scp -r export/server-fixes-v1 <user>@<host>:/tmp/server-fixes-v1
```

```bash
ssh <user>@<host> bash /tmp/server-fixes-v1/install.sh
```

`install.sh` copies tg-fetcher to a scratch folder, patches it, adds the new files and runs the
full suite (485 tests). It does the same for the shuffle server's `navivibe/` and its proxy tests
(29). Only if both pass does it back up the 9 tg-fetcher files it patches, `fetch_proxy.py` and
`pip freeze` to `/opt/tg-fetcher/backups/server-fixes-v1-<time>/`. Then it patches the live trees,
adds the new files, `pip install ytmusicapi==1.12.3` into tg-fetcher's venv, and runs both suites
on the live trees. If anything fails, it puts the old files back. Finally it records the files
already in the music folder for the auto-import. Re-running it is safe; patches are exact-match and
idempotent, and a file that differs from what this package was built on stops it with exit 2 before
anything is written. For a rollback, use the **first** backup folder: a re-run backs up files that
are already patched.

Then the sudo lines it prints:

```bash
sudo systemctl restart tg-fetcher navivibe
```

```bash
sudo cp /tmp/server-fixes-v1/systemd/tg-fetcher-autoimport.service /tmp/server-fixes-v1/systemd/tg-fetcher-autoimport.path /tmp/server-fixes-v1/systemd/tg-fetcher-autoimport.timer /etc/systemd/system/
```

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable --now tg-fetcher-autoimport.path tg-fetcher-autoimport.timer
```

Check: `journalctl -u tg-fetcher | grep sweep` should show the Raga of Revenge row moving within 2
minutes of the restart. `journalctl -u tg-fetcher-autoimport -f` and
`cd /opt/tg-fetcher && venv/bin/python -m tgfetch.autoimport status` show the auto-import.

## Notes

* A dropped file that Navidrome indexes before it is tagged gets a new id after tagging; the
  old row becomes `missing` (the same thing the doctor causes). The 30 s settle keeps this rare,
  and the sweep re-points anything that referred to it.
* Mood labels for dropped songs are written to the shuffle server's `mood_tags.json` by its own
  labeller (its venv and `.env`), like the nightly run does.
* `fetch_proxy.py` changes only to forward `force`; links and search answers pass through
  untouched as before. There is no Data API fallback for YouTube (no key needed so far).
