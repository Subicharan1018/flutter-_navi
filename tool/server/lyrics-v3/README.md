# lyrics-v3

Why "Life of Pazham" showed no lyrics, and every edge case around it. Needs lyrics-v2 (installed) and
the matching app update.

## What was wrong

lyrics-v2 finds the song: `resolve` returns lrc.red lyrics for it. The phone never asked, because:

1. The first try, on an older build, got "nothing" and the app wrote that down as "no lyrics" for 12
   hours without asking anyone again.
2. The same code wrote "no lyrics" when the request merely **failed** (timeout, 429, 5xx, bad JSON),
   and the server did the same: `resolve` returned `None` both for "nobody has it" and for "the source
   did not answer", and `None` was cached as a miss. One flaky request hid a song.

## What this package does (server)

| | |
|---|---|
| **Found / not found / failed** | Every source reports one of three. Only *found* and *not found* count. A timeout, 429, 5xx, connection error or bad JSON is *failed*. BetterLyrics' 401 stays a normal "not found" (it answers 401 for every song it has no key for). |
| **A failure is never a miss** | If any source failed and none found the song, the server answers `404 {"error": "...", "retry": true}` and writes no miss, only a 5-minute `transient` note (so one song can't hammer the sources). A miss is written only when every source answered. |
| **Old misses are retried** | The cache version is now 3. A miss written by lyrics-v1 or v2 (no `v`, or `v` 2) is asked about again at once; hits are kept. |
| **`refresh=1`** | `GET /lyrics/fetch?...&refresh=1` ignores a remembered miss, a 5-minute failure note and a due recheck; it never deletes a hit. 10 an hour per user on top of the 40 a minute; the 429 says so. |
| **Budget** | One request to one source times out at 5 s; the whole `/lyrics/fetch` is cut at 12 s (a source that has no time left counts as *failed*, not as "no"). The prefetch has no per-song budget. |
| **One ask per song** | A per-song lock: two phones (or one phone twice) opening the same song at once ask the sources once; the second takes the first's answer. Per process. |
| **Plain text can't hide synced** | A plain-text answer (YouTube Music, LRCLIB-style) is looked at again after a day; so is an answer that was given while another source was failing (after 10 minutes). The recheck never loses what was cached. |
| **Matcher** | See below. |
| **ISRC** | Read from `catalog.db`, then from `spotify_details.isrc_of` (the Exportify package) when the catalog has none, and looked up directly. The ISRC is trusted only while the lrc.red record it names is within 12 s of the song and the title is the same or the length agrees to 4 s. |
| **Prefetch** | `lyrics_prefetch` uses the same `lookup_ex`: it never records a failure as a miss, picks up songs whose only entry is a v1/v2 miss, counts `failed` separately, and stops for the night after 15 failures in a row (the sources are down). |
| **YouTube Music helper** | Now also requires one of the song's artists to be on the result and the same kind of version (a Reprise is not the original). It receives the full title for that. |

## The matcher, from data

Run over a 300-song stratified sample of the library (multi-artist, "(From …)", " - …" titles, other
scripts, feat., very long or short songs, songs without an ISRC, and a random rest) against the real
lrc.red, **search path only** (the ISRC shortcut turned off, so every miss shows what the search can
and can't do):

| | found of 300 |
|---|---|
| lyrics-v2 matcher | 198 (66%) |
| lyrics-v3 matcher | 217 (72%) |

The 83 songs still missed, by cause: **52** have no similar title anywhere in lrc.red's results (it simply
doesn't have them: Spotify film scores, background-score cues, instrumentals, a few big pop songs, which
a direct search by title confirms); **15** have a same-titled song by another artist (some of those are
now accepted when the album and a 2 s length agree, the rest are different songs); **9** have the title
but a length more than 12 s away (a different recording); **6** exist only as a remix, cover, sped-up or
reprise (correctly refused); **1** is 4-12 s off with weak evidence. In production most songs go through the
ISRC from the catalog (2,226 of 2,437 have one), which skips the search, so the real hit rate is at least
this. The causes found and what was done for each:

| cause | fix |
|---|---|
| Title written differently: `(From "…")`, `- From …`, `[Remastered]`, `feat.`, `Pt. 2` / `Part 2`, accents, `&` / `and`, apostrophes, a colon or dash subtitle | titles are compared as plain word strings without those tails; a subtitle match needs the artist and a ≤4 s length |
| Transliteration of Indian names in titles and artists (`Kadhal`/`Kaadhal`, `Yuvan`/`Yuvaan`, `Ravichander`/`Ravichandran`, `Thanjavoor`/`Tanjavur`) | a spelling-insensitive fold plus a similarity ratio, accepted only with a ≤3 s length and a strong artist |
| Several artists in any order, `•` `;` `,` `&` ` x ` `feat.`, one in another script | any listed artist may match any artist on the hit; a name in another script can't be compared, so title + a ≤4 s length decide |
| Length differs from lrc.red's | 0–4 s accepted; 4–12 s only with an exact title and a strong artist (or the same album); **more than 12 s never** |
| lrc.red's search is picky about punctuation: `Somebody's Watching Me` finds nothing, `Somebodys Watching Me` finds it | the title without apostrophes, and with other punctuation as spaces, is the third and fourth query |
| Only the first page of results was read | up to 3 pages are followed (`after=`), at most 8 search requests per song |
| Found only with another query | the other artists, the film or album name, the title before a subtitle, and the title without punctuation are tried after the first two |
| Album as evidence | the same album (ignoring "Original Motion Picture Soundtrack") can stand in for a differently-spelled artist, with an exact title and ≤4 s |

### The false-positive guard (showing a different song is worse than showing none)

A hit is rejected when its **version tags** differ from the song's: remix, sped up, slowed, reverb, live,
acoustic, unplugged, instrumental, karaoke, revival, reprise, cover, lofi, nightcore, extended, duet,
male/female, "Tamil/Hindi/… version" and similar, read from a bracket or dash tail. "Remastered" is not a
version; a film called `(From "Live Aid")` is not a live version. Different numbers (`Part 1` / `Part 2`)
never match. Same title by a different artist never matches. The regression tests in
`tests/test_lyrics_v3.py` cover these pairs.

## Install (on the server, as subi; no sudo)

```
cd tool/server/lyrics-v3 && bash install.sh
```

It refuses to run on a `lyrics_proxy.py` it doesn't recognise (it expects lyrics-v2's), tests a scratch
copy first (before and after), backs up, installs, tests the live tree, and restores if anything that
passed before fails. Then:

```
sudo systemctl restart navivibe
sleep 30; curl -s http://127.0.0.1:5500/ready; echo
```

Optional, to fill in the old misses now instead of tonight (gentle, resumable):

```
cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.lyrics_prefetch --max-minutes 45
```

## Rollback

The install prints the exact lines (it copies the backup under `/opt/shuffle-server/backups/lyrics-v3-…`
back and removes the one new test file), then `sudo systemctl restart navivibe`.

## What isn't touched

`lyrics_sidecar.py`, the timer and service units, the venvs, the music folder, `catalog.db` (read-only).
No lyrics text is stored in the package, its tests or this file.
