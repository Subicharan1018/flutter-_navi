# rotation-v1: Rest a song, seasonal songs, Back in rotation

For `/opt/shuffle-server`. Built on the live code read on 22 Nov 2026 (needs nothing else installed; it does not touch
`flow.py`, so it sits beside flow-v1). Research: `docs/feature-research-2026-11.md` features R1, R2 and R8.
(R11, the plain shuffle, is app-only: see "App side" below.)

## What it does

| | |
|---|---|
| **Rest (R1)** | Snooze a song for 2 weeks / 1 month / 3 months (1–365 days over HTTP). The server also rests a song by itself when it is being worn out: 10+ plays in 14 days **and** 2 of the last 3 plays skipped. It rests for 14 days; "Bring back" on one of those keeps it safe from auto-rest for 30 days. |
| **Seasons (R8)** | Deepavali, Pongal, Christmas, Navaratri, Ayyappa season, Vinayagar Chaturthi. A tagged song is left out of every recommender outside its window and comes back in it. A song is seasonal by the listener's tag, by a title word ("Christmas", "Diwali", "Pongal"…), or because 85 %+ of its 5+ plays fall in one window (narrowest window wins: Christmas inside Ayyappa). The listener's tag beats the guess; `none` means never seasonal. |
| **Back in rotation (R2)** | Songs with 4+ full plays (≥ 80 %) older than 90 days, not played for 60 days, skipped under 30 % of the time. A seeded draw from the best 3× the limit, weighted by plays, so the shelf changes each day. |

"Left out" is **one patch**: `taste_exclusions.blocked_ids()` also returns `rotation.hidden_ids()`. Discover, the Weekly
mix (also the stored one), Flow and Smart Shuffle (`recsys/recommender.py`) all already ask `blocked_ids`, so none of
their code changes. Playing a song yourself is never blocked.

Windows are wide because festival dates move: Deepavali 5 Oct–18 Nov, Navaratri 15 Sep–25 Oct, Vinayagar 15 Aug–20 Sep,
Ayyappa 10 Nov–20 Jan, Christmas 1 Dec–2 Jan, Pongal 5–20 Jan. Edit `SEASONS` in `rotation.py` to change them.

## Install (on the server, as `subi`, no sudo)

    cd ~/rotation-v1        # wherever this folder was copied to
    bash install.sh --check # scratch tests only: nothing live is touched
    bash install.sh

Tests a scratch copy first (the whole shuffle-server suite before and after the patch, so a test that already failed
does not block it), backs up to `/opt/shuffle-server/backups/rotation-v1-<time>`, patches, tests the live tree and puts
everything back if a test fails. After "Done" it prints the restart (`sudo systemctl restart navivibe`) and the rollback.
Nothing is restarted by the script. Safe to re-run.

## What it patches (exact-text anchors; a different version stops the run before anything is written)

| File | Change |
|---|---|
| `taste_exclusions.py` | `blocked_ids()` = `_excluded_ids()` (the old body) + `rotation.hidden_ids()`; a rotation fault is logged and ignored |
| `discover.py` | `user_context()` calls `rotation.refresh()` (at most every 6 h per listener: auto-rest, seasonal guesses) |
| `server.py` | registers the routes, after `register_pair_routes(app, require_auth)` |

New: `navivibe/rotation.py`, `navivibe/tests/test_rotation_v1.py`. Per-listener state: `<log dir>/taste/..` is untouched;
rotation writes `<log dir>/rotation/<user>.json`.

## HTTP contract (shuffle server, signed-in)

    GET    /rotation                  {resting:[{song_id,title,artist,until,since,auto}], seasonal:[{song_id,title,artist,season,label,in_season,manual}],
                                       seasons:[{key,label,in_season,from,to}], prefs:{auto_rest,seasons,back}}   (also runs the 6-hourly look at plays)
    POST   /rotation/rest             {song_id, days 1..365, label?}      → {song_id, until, days}
    DELETE /rotation/rest             {song_id}                            → {song_id, removed}
    PUT    /rotation/season           {song_id, season: key|"none"|null}   (null forgets the listener's tag)
    PUT    /rotation/prefs            {auto_rest?, seasons?, back?}  booleans → {prefs}
    GET    /rotation/back?limit=20    {count, items:[discovery-shaped + kind:"back", plays, full_plays, last_played, why]}

503 while the recommender starts (`/rotation`, `/rotation/back`); `rest`, `season` and `prefs` need no engine.

## App side (same commit series)

- Song menu: **Rest This Song…** (2 weeks / 1 month / 3 months, Undo) or **Bring Back**; **Seasonal…** (6 seasons, Not seasonal, Clear my tag).
- Settings › Taste: *Resting* (with "back on 12 Dec", "rested for you"), *Seasonal*, and three switches (auto-rest, seasons, Back in rotation).
- Home: **Back in Rotation** shelf (hidden when empty). Smart Reshuffle blends up to 3 old favourites into the recommender's picks (one slot in about 6, never the first two), only songs from the list being shuffled.
- **True Shuffle (R11)**, a shuffle style next to Random: pure uniform random, no recommender and no history; every song plays once before any plays twice, across sessions. The "bag" (which songs of a list have played) is kept on the device per list.

## Tests

Scratch copy of the live code (Windows, Python 3.10 with the server's requirements), `bash install.sh --check`:
the shuffle-server suite before the patch, then after: only `test_recognize.py` (ffmpeg), `test_flow.py::test_a_missing_state_file…`
and `test_moods_v2.py::test_the_page_is_public_html…` fail, and they fail without the patch too (Windows paths / ffmpeg).
`test_rotation_v1.py`: **42 passed** (windows and wrap over New Year, titles and plays, tag beats guess, snooze and expiry,
auto-rest and its grace, other listeners' plays, throttle, damaged file, back-in-rotation rules and daily stability,
`blocked_ids` with and without a fault, Discover and the stored weekly mix, `user_context`, every route with and without login,
bad bodies, 503).

## Not done on purpose / not verified live

- Flow's "comfort picks" from Back in rotation (R2) is **not** built: it would patch `flow.py`, which flow-v1 also patches.
  Flow already favours songs unheard for a while; the bias exists in Smart Reshuffle (app side) and the shelf.
- True Shuffle's bag is **per device**, not synced across devices (the research suggested session sync; that needs a change to
  the session server and the other session's queue work).
- Seasonal guesses from plays need a year of history to be strong; titles and the manual tag work from day one. The title words
  are a short list (see `KEYWORDS`); a wrong guess is undone with "Not seasonal".
- Not run against the live server: real `/rotation` answers, the 6-hourly refresh on a real library, auto-rest on real plays.
