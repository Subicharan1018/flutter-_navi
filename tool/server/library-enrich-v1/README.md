# library-enrich-v1

Fills the **empty** genre, label, release date and ISRC of library songs that Exportify did not cover, from
MusicBrainz and Last.fm. Written for `/opt/shuffle-server` on subiserver; installs to its own folder
`/opt/navivibe-libenrich` and touches no existing server code. Python 3.9+, standard library only (no pip).

## Install (owner, on the server, as `subi`)

    bash install.sh --check        # scratch tests only
    bash install.sh                # tests + copy the code; the nightly job stays OFF
    LIBENRICH_CONTACT='<contact>' bash install.sh --cron   # also shows the cron line and asks (type yes)

**You must choose the MusicBrainz contact.** MusicBrainz's [rate-limiting page](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)
says every request needs a User-Agent with enough information to contact the maintainer ("a contact URL or
address"). The job sends `NaviVibe-LibraryEnrich/1.0 ( <LIBENRICH_CONTACT> )` and refuses to run without it.
The existing server enrich code already uses a project URL (`NAVIVIBE_USER_AGENT`); a URL like that, not a
personal address, is allowed by the policy. No default is baked in on purpose. The owner chose
`https://shuffle.subimusic.me` (23 Nov 2026), so use `LIBENRICH_CONTACT='https://shuffle.subimusic.me'`.

## What it reads, what it writes

| | |
|---|---|
| Reads | `/opt/shuffle-server/catalog.db` (read-only: songs + the Last.fm / MusicBrainz payloads the catalog pipeline already stored), `spotify_details.db`, the Last.fm key |
| Writes | its own cache `/DATA/AppData/navivibe/library_enrich.db`; `spotify_details.db` **empty fields only** |
| Never | overwrites a filled field, edits `catalog.db`, Navidrome, music files, or exportify's tables |

It writes into **the same table and columns exportify-v1 writes** (`spotify_details`: `isrc`, `genres` JSON list,
`label`, `release_date`; a new row has `matched_by='libenrich'` and empty audio features), so
`navivibe/spotify_details.py`, the `/catalog/songs` extras (`label`, `released`, `sp_genres`, `year` where missing),
the lyrics proxy's ISRC lookup and the mood second opinion read it unchanged (a row without energy/valence is
ignored by the mood rules). If exportify later imports a CSV it replaces the row with Spotify's values; the next
run refills only what is then empty, from the cache, with no network.

**Provenance:** table `enrich_provenance` in `spotify_details.db`: `song_id, field, value, source, source_date,
applied_at`. Source is `musicbrainz`, `lastfm`, `lastfm+musicbrainz`, or `musicbrainz(catalog)` for a value taken
from the catalog's earlier stored lookup. A row is dropped when the field's value changes (an admin or exportify
replaced it), so provenance only lists values this job still owns.

## How it decides

For each song it works out which fields are empty (ISRC counts as empty only when `catalog.db` has none either).
Offline first: the catalog's stored MusicBrainz `first_release_date` (match ≥ 0.9) and stored Last.fm tags are used
before any request. Then:

* **MusicBrainz** (only if isrc / label / release date still empty; max 1 request per 1.1 s): the catalog's mbid
  when it has one, else a recording search. A search hit is accepted only when its score ≥ 90, the title is ≥ 0.88
  similar (remix / live words stay part of the title), an artist is in common, and the length is within 6 s. Then
  `recording/<mbid>?inc=isrcs+genres+releases` (ISRC, earliest release date, genres) and, for the label,
  `release?recording=<mbid>&inc=labels` (label of the earliest dated release that has a real label; "[no label]" ignored).
* **Last.fm** (only when genres are still empty and the song has no stored Last.fm payload): `track.getTopTags`
  and `artist.getTopTags`.
* **Genre vocabulary** (`libenrich/genres.py`, about 50 names): tags are mapped through a synonym whitelist
  (`hip-hop`/`rap` → `hip hop`, `rnb` → `r&b`, `kollywood`/`ost` → `soundtrack` ...). Anything not in the map is
  dropped: "seen live", "favorites", decades, places, languages, and artist / composer names (also checked against the
  song's own artists). Mood words (sad, chill, romantic) are dropped on purpose: moods stay with the mood labeller.
  Track tags weigh 1.0, artist tags 0.6, MusicBrainz genres 0.8; at most 3 genres, each ≥ 20 of 100 and ≥ 25 % of the best.
* **Cache:** every lookup, misses and errors included, in `lookups(song_id, source, status, result, fetched_at, retry_after)`.
  A miss is retried after 30 days, an error after 1 day, a hit never. Rate limit (HTTP 429/503, Last.fm error 29):
  is **not** a stop signal: the client waits max(`Retry-After`, 2/4/8/16 s) and retries the SAME request up to 4
  times. Only if it is still refused is that song left (nothing cached, so it is tried again next run), and after 3
  songs in a row refused that one service is paused for the rest of the run while the other carries on. The log line
  names the service and the signal, e.g. `musicbrainz is busy (HTTP 503 zone=search who=search-shed retry-after=1)`.
  A miss is never a failure; 5 network failures (timeouts, 5xx, bad JSON) in a row stop the run.
  Seen live on 23 Nov 2026: MusicBrainz's gateway answered a *search* with 503 + `Retry-After: 1` +
  `X-RateLimit-Zone: search` / `X-RateLimit-Who: search-shed` ("currently busy"): load shedding for the whole search
  zone, not our own rate (its `X-RateLimit-Limit` was 400). Lookups by mbid are a different zone.
* **Size of the job** (`--report` prints it): a full first pass is about 5,800 MusicBrainz requests (2 per song with a
  catalog mbid: recording + releases for the label; 3 without: search first), about 2.3 h at 1.1 s spacing plus
  retry waits, plus about 2 Last.fm requests for each song with no stored tags. The nightly job runs 02:17 for at most
  150 min (ends by 06:00), so the first pass finishes in 1 to 3 nights; afterwards it finds nothing due and exits at once.
* **Resumable / bounded:** `--limit N`, `--max-minutes M`, `--end-by HH:MM`. An interrupted run loses at most the current song.

## Commands

    cd /opt/navivibe-libenrich
    python3 -m libenrich --report                      # fields filled / empty, cache counts
    python3 -m libenrich --apply-only --dry-run        # what the offline data alone would write (no network, no write)
    LIBENRICH_CONTACT='<contact>' python3 -m libenrich --run --limit 50
    python3 -m libenrich --run --no-lastfm             # MusicBrainz only
    python3 -m libenrich --apply-only                  # write from cache + catalog only

Environment (all optional except the contact for `--run`): `LIBENRICH_CONTACT`, `LIBENRICH_CATALOG_DB`,
`NAVIVIBE_SPOTIFY_DETAILS_DB` (same variable exportify-v1 uses), `LIBENRICH_CACHE_DB`, `LIBENRICH_ENV_FILE`
(default `/opt/shuffle-server/.env`; only the `LASTFM_API_KEY=` line is read), `LASTFM_API_KEY`.
The key is referenced by name only. It is sent to Last.fm in the request and appears nowhere else: not in logs,
errors, the cache or this repo.

## Nightly option (off by default)

`install.sh --cron` prints and, only if you type `yes`, installs `17 2 * * *` (low priority, stops by 06:00 or
after 150 min, resumes next night). 02:17 rather than a round hour, as MusicBrainz asks.

## Verified / not verified

Verified: 33 unit tests with API-shaped fixtures (no network): genre normalisation incl. junk and artist-name tags,
MusicBrainz / Last.fm parsing, strict same-song matching (incl. Tamil titles), 1 request/s throttling, rate-limit stop,
cache and retry dates, resume with zero repeat requests, fill-only-empty, provenance, exportify's table columns unchanged,
dry run. On a copy of the live `catalog.db` the offline pass alone would give 1,510 release dates and 1,253 genre lists.
Not verified: the fixtures are written from the documented API shapes, not recorded from live calls (no contact
address was chosen, so no live MusicBrainz or Last.fm request was made); real hit rates for label / ISRC;
install.sh was not run on Linux (bash syntax checked only).
