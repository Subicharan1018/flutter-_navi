# lyrics-v1: synced lyrics proxy for the shuffle server

For the shuffle server (`/opt/shuffle-server/navivibe`, systemd `navivibe`) on subiserver. Built
from the server's documented shape and the moods-v2 / server-fixes-v1 packages. **The live server
was unreachable (SSH timed out) while this was written, so it has never been run against the live
tree: `install.sh` tests a scratch copy of the live code first and installs nothing if that fails.**
Not installed: the user runs `install.sh` and the sudo line.

## What it adds

`GET /lyrics/fetch` (signed in), query `title`, `artist`, `album`, `duration` (s), `song_id`,
`sources` (`lrcred,betterlyrics,paxsenix`, in the order to try), `spotify_id` (22 chars, paxsenix
only) answers `{source, sync: word|line|plain, lrc, cached}` or 404. `lrc` is enhanced LRC
(`[mm:ss.xx]<mm:ss.xx>word <mm:ss.xx>word`), which the app already parses.

| source | request | result | cost / risk |
|---|---|---|---|
| lrc.red | `GET https://lrc.red/search.json?q=<title artist>` → pick the hit with the same title, an overlapping artist and a duration within 4 s → `GET /s/{isrc}.json` (`sync`: `word`/`line`) → `/s/{isrc}.ttml` (word) or `.lrc` (line) | word or line synced | free; **terms**: send a User-Agent naming the app with a link and a contact address (`NAVIVIBE_LYRICS_CONTACT`), credit lrc.red wherever its data shows (the app's source chip does), rate-limited per IP (api@lrc.red lifts it). Their site said its uptime was unstable in Oct 2026. |
| BetterLyrics | `GET https://api.betterlyrics.org/getLyrics?s=&a=&al=&d=` → `{ttml, score}` (word spans) | word synced | free but **API keys are not being issued**: a song nobody has played in their extension answers 401 on a cache miss, and the server counts that as "no result". Two rate tiers per IP; a link back is requested. Content comes from several upstream providers whose licences it does not state. |
| Paxsenix / Spotify-Lyrics-API | `GET {NAVIVIBE_PAXSENIX_URL}/api/lyrics?url=https://open.spotify.com/track/<id>&format=lrc` → `{syncType, lines:[{timeTag, words}]}` | line synced | **Off unless `NAVIVIBE_PAXSENIX_URL` is set.** The project is self-hosted (the README documents no public host) and needs a Spotify `sp_dc` cookie on that instance; it uses undocumented Spotify endpoints and says it "may violate Spotify's Terms of Service". The cookie lives on that instance only: never in this server's code or config, never in the app. It also needs a Spotify track id the app does not have for most songs, so it only answers when the app sends one. In the app it sits behind a switch that is off. |

Every song is cached on disk in `/opt/shuffle-server/lyrics_cache/` (one 0600 file per song; a miss
is remembered for six hours). Answers are `Cache-Control: private, no-store`, need a sign-in and are
never listed or served publicly. 40 requests a minute per user on top of the server's own limits.
No lyrics text is in this package, its tests or its docs.

## Install

```bash
cd /path/to/tool/server/lyrics-v1 && bash install.sh
```

then the lines it prints (set `NAVIVIBE_LYRICS_CONTACT`, `sudo systemctl restart navivibe`).
Rollback is printed too.

## Tests (no network)

```bash
cd files && PYTHONPATH=. python -m pytest navivibe/tests/test_lyrics_v1.py -q
```
