# lyrics-v2: a lookup fix, YouTube Music, a prefetch, and an opt-in .lrc writer

For the shuffle server (`/opt/shuffle-server/navivibe`). Needs lyrics-v1 (installed 21 Nov 2026,
`lyrics_proxy.py` sha256 `454060f2…`). `install.sh` refuses to run on any other version of that
file. Not installed: the user runs `install.sh` and the sudo lines. No lyrics text is in this package.

## 1. The bug: songs with several artists were not found

"Life of Pazham" (library artist `Anirudh Ravichander • Vivek`, 236 s, no ISRC) came back empty.
lrc.red lists it as `Anirudh Ravichander, 維瓦克` (2nd artist in Chinese, 234.5 s). The old code sent
`title + the whole artist string` as the search, which returns 0 hits.

- **Query**: the title without its `(From "…")` tail + the **primary artist** only (artists split on
  `•` `·` `;` `,` `&` `/` `feat` `ft` `with` `x` `and`); if that finds nothing, **the title alone**.
- **Matching**: the title must match; any one of the song's artists may be the listed one. If the
  listing's artist is in another script and no name matches, a **duration within 4 s** is the proof
  (no duration, no match; a Latin-script mismatch is still a mismatch).
- **ISRC**: read from `catalog.db` (`songs.isrc`; also `spotify_details` when that table exists:
  `isrc` / `spotify_id`, keyed by `song_id` or `id`). With an ISRC lrc.red is asked for
  `/s/{isrc}.json` directly, with no search; a wrong ISRC falls back to the search.
- **BetterLyrics** gets `a=<primary artist>`; the Paxsenix call gets the catalog's Spotify id.
- **Cache version**: entries carry `"v": 2`. A miss written by lyrics-v1 (no `v`) is asked again at
  once, as is a miss recorded for fewer sources than are now asked. Hits never expire.

Checked against the real lrc.red from a laptop (not through the server): the exact song is found both by
the search and by its ISRC (line-synced, 49 lines).

## 2. Prefetch the library's lyrics

`python -m navivibe.lyrics_prefetch`. It walks `catalog.db` (songs not missing), skips songs that
already have a cache entry, and stores results in `lyrics_cache` (0600, never served without a
sign-in, the same files `GET /lyrics/fetch` reads, so a played song is an instant cache hit).

- **Gentle**: one request at a time, at most `--rate` a minute across all sources (default 30, hard
  cap 60; YouTube Music calls take a slot from the same budget). A 429 or 403 waits (60 s, doubling to
  15 min) and retries; a host that keeps refusing is left out for 20 minutes.
- **Resumable**: the cache is the state. `--max-minutes` (default 45) ends a run; the next run carries
  on. A song nobody had is asked again after `--retry-misses` days (default 14).
- **Never breaks the service**: its own process; every song's error is logged and counted; exit 0
  unless catalog.db can't be read.
- `--sample N --seed S --cache-dir DIR` for a dry run into a scratch cache.
- The summary line is logged and printed as JSON: found by source, not found, skipped, requests, backoffs.

Timer: `systemd/navivibe-lyrics-prefetch.{service,timer}` (03:40 daily, ±20 min, `Nice=15`, idle I/O).
`install.sh` copies nothing into systemd; it prints the sudo lines.

### Sample run (dry run; 21 Nov 2026, 150 random songs, seed 7, scratch cache, then deleted)

| | songs |
|---|---|
| found | **124 of 150 (83 %)** |
| from lrc.red, word timed | 50 |
| from lrc.red, line timed | 62 |
| from YouTube Music, line timed | 10 |
| from YouTube Music, plain text | 2 |
| from BetterLyrics | 0 |
| not found | 26 |

422 requests in 14 minutes, 0 back-offs, 0 errors. Counts are "first source to answer" in the order
lrc.red, BetterLyrics, YouTube Music, so YouTube Music's 12 are songs the first two did not have;
what it would find in addition to songs lrc.red has was not measured. BetterLyrics found nothing: it
answers a cache miss with 401 while keys are not issued.

At that rate a full pass over the library's 2,433 songs is about four hours, in 45-minute nightly runs.

## 3. YouTube Music as a source

Last in the default order. `NAVIVIBE_YTMUSIC_LYRICS=0` turns it off. The app has a matching switch
(on) and the chip says "YouTube Music".

- **Choice**: not a pip install into the shuffle server's venv, and no change to tg-fetcher.
  `ytmusic_lyrics_helper.py` is run as a subprocess by tg-fetcher's own Python
  (`/opt/tg-fetcher/venv/bin/python`, `ytmusicapi` 1.12.3, override with `NAVIVIBE_YTMUSIC_PYTHON`)
  with a 40 s timeout, an empty environment, `-I`. Neither venv changes; if the helper or that Python
  is missing, the source is quietly silent.
- **Flow**: search songs, accept only a result with the same title and a duration within 4 s, read
  that video's lyrics page text (timestamps when YouTube has them: line sync; else plain). No audio or
  video is requested, no account is used.
- **Risk**: unofficial. `ytmusicapi` drives YouTube Music's web interface, which is not a licensed
  API; YouTube's terms of service do not allow it, and Google can block or change it at any time. It
  is read-only and low-volume (one search and one lyrics page per uncached song, inside the 30 a minute
  budget). Lyrics text on YouTube Music comes from third-party providers. Works today: checked on the
  server (a timed result for a song from the library).

## 4. Writing `.lrc` files next to the audio (opt-in)

`python -m navivibe.lyrics_sidecar` is a **dry run** and says how many files it *would* add. `--apply`
writes them. Rules: never overwrites or touches an existing `.lrc` (yours, or tg-fetcher's), only
writes inside the music root (`/DATA/Media/Music`, `--music-root`), the name is the audio file's with
`.lrc`, the same as tg-fetcher's. Timed lyrics only (`--plain` adds untimed), line timing (`--words`
keeps word tags, which most readers don't understand). Afterwards rescan the library in Navidrome.

On the 150-song sample: it would add 67 files, 55 songs already have one, 2 are plain text.

**tg-fetcher-autoimport**: `/opt/tg-fetcher/tgfetch/autoimport.py` only imports files whose suffix is
in `AUDIO` (`.flac .mp3 .m4a .wav .ogg .opus .aiff .aif .wv .ape`), so a `.lrc` is never imported;
for a FLAC it checks `path.with_suffix(".lrc").exists()` and then does not write its own, so a sidecar
written first is kept. Its directory watch only triggers a scan that skips non-audio files.

## 5. The lrc.red contact address (your choice)

lrc.red's terms ask for a contact address in the User-Agent (`NAVIVIBE_LYRICS_CONTACT`). It is not
set, and the proxy works without it (the User-Agent is `NaviVibe-LyricsProxy/1 (+https://subimusic.me)`).
**You choose what to put there**: an address you are willing to have lrc.red see, such as one made for
this server. Nothing in this package sets or invents one. Set it with `sudo systemctl edit navivibe`
(`Environment=NAVIVIBE_LYRICS_CONTACT=...`), and for the prefetch in the service file or `.env`.

## Install, tests, rollback

```bash
cd tool/server/lyrics-v2 && bash install.sh
```
Scratch-tests a copy of the live code before and after (a dry run of this package on a scratch copy of
the live tree: 723 passed before, 756 after, 2 skipped, 0 failures), backs up, installs, tests the live
tree, restores on failure. Then the printed `sudo systemctl restart navivibe`. Rollback is printed.
Tests (no network): `cd files && PYTHONPATH=. python -m pytest navivibe/tests -q`.
