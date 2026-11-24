# film-credits-v1

Film, year, music director, lyricist and singers per song, for the app's Film page and credit pages
(item 4 of `docs/feature-scout-research.md`, first slice). Python 3.9+, standard library only.

## Install (owner, on the server, as `subi`)

    bash install.sh --check     # scratch tests only
    bash install.sh             # tests, backup, patch, live tests (auto-rollback), then prints the next steps

Needs exportify-v1 (its `catalog/api.py` hook). Run the install line after the others in `../INSTALL-ORDER.md`.
Nothing is restarted, no sudo, `.env` and live data are not touched. The printed steps: build the offline credits
(seconds, no network), `sudo systemctl restart navivibe`, and, when you decide, the Wikidata / MusicBrainz pass.

## What it does

| Source | Gives | Network |
|---|---|---|
| catalog tags (`film`, `composer`, `lyricist`, `artist`, `album`) | film, music director, lyricist, singers | no |
| album named "(Original Motion Picture Soundtrack)", `From "X"` in the title, the stored iTunes payload | film where the tag is empty | no |
| Wikidata (CC0), `--run` | film year, director, music director, lyricists, Q-id | yes, cached |
| MusicBrainz (CC0), `--run --tracklists` | the soundtrack's full track list (to show which songs you do not have) | yes, cached |

* Unknown stays unknown. A Wikidata film is accepted only when it is a film, has the same title, sits in the Indian
  film world (Tamil/Telugu/Hindi/Malayalam/Kannada language or India as country), and its year is within 2 of the library's;
  two candidates are settled by the composer, otherwise nothing is filled. A track list needs a title match, score >= 90,
  the composer in the artist credit and a date within 2 years.
* Singers = the artist tag's names, minus anyone credited as lyricist (the tag, or Wikidata's lyricists of a film). The artist
  tag cannot tell a singer from a featured composer: the app words it as "credited artists".
* JioSaavn is not used (unofficial API, terms risk). It can be added later behind the same cache.
* Rate: 1 request per 1.1 s, a User-Agent naming `FILMCREDITS_CONTACT`, 429/503 waited out and retried, every answer cached
  (hit: forever, miss: 60 days, error: 1 day), a busy service stops the run and the next run continues.
  A full first pass is about 3 requests per film (755 films in the library: roughly 40 minutes) and is safe to stop.

## Files

Writes only `/opt/shuffle-server/film_credits.db` (`songs`, `films`, `lookups`); reads `catalog.db` read-only. The web server reads
it read-only (`navivibe/film_credits.py`): extra keys `film` (only where the catalog has none), `fk`, `md`, `ly`, `sg` in
`GET /catalog/songs`, and `GET /credits/films` (films with year, directors, music directors, lyricists, Wikidata id, optional
`tracklist`), ETag like the catalog. No file = no extras; the app works unchanged.

## Commands

    cd /opt/navivibe-filmcredits
    python3 -m filmcredits --catalog /opt/shuffle-server/catalog.db --db /opt/shuffle-server/film_credits.db          # offline
    FILMCREDITS_CONTACT='https://shuffle.subimusic.me' python3 -m filmcredits ... --run --tracklists --limit 50
    python3 -m filmcredits ... --report

## Verified / not verified

Verified: 18 job tests (key vectors incl. Tamil, split, film cleaning, Wikidata and MusicBrainz parsing with API-shaped
fixtures, ambiguity and year mismatch = miss, throttle and busy retry, cache = zero requests on the second run, catalog file
byte-identical after a run) and 13 web-server tests (reader, route, ETag, no file, corrupt file, `/catalog/songs` extras),
run on a patched copy of a snapshot of the live server tree (107 passed with the neighbouring catalog / exportify / fetch /
security suites). Offline pass on a copy of the real `catalog.db`: see the PR description for the numbers.
Not verified: the fixtures follow the documented Wikidata / MusicBrainz shapes, not recorded live calls (no contact was
chosen, so no live request was made); real Wikidata hit rates for Tamil films; `install.sh` was run on Linux-like Git Bash
against a fake tree, not on subiserver.
