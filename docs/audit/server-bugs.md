# Server code audit: listening data and ordering

Read on 23 Nov 2026 from the **live** code on subiserver (read-only SSH; files copied to a scratch folder, nothing opened read-write, nothing installed). File:line are the live files' lines, before any patch.

**The repo does not contain the shuffle server's source**, only install packages that patch it (`tool/server/*`). Live is the truth, so every fix here is a package with anchored edits that refuse to apply if the live text differs: `tool/server/play-events-v2/`.

Checked against a copy of `admin_listening_log.db` (8,486 `play_events` rows). Numbers below come from `tool/shuffle_eval/data_quality.py` run on that copy.

Reviewed: `/opt/shuffle-server/navivibe` (`server.py`, `feedback.py`, `scheduler.py`, `sync_navidrome.py`, `weather.py`, `session.py`, `recsys/data.py`, `recsys/recommender.py`, `recsys/state.py`), `navivibe-startcopy`, `navivibe-fakescan`, `tg-fetcher/tgfetch/history_import.py`. Not read line by line: `model.py`, `preprocess.py`, `stats.py`, `lyrics_*`, `flow.py`, the rest of tg-fetcher (no listening data on their write path, only reads of `play_events` for stats).

Status: **FIXED** = in `play-events-v2`, applied when the owner installs it. **OPEN** = reported, needs the owner's call or is outside this task.

## Ranked

| # | Sev | Problem | Status |
|---|-----|---------|--------|
| 1 | High | Nightly Navidrome sync invents plays with identical timestamps | FIXED |
| 2 | High | 97 % of app rows carry fake weather (800 / 25.0) | FIXED |
| 3 | High | Old app's "finished naturally at 0 %" rows teach the live model skips | FIXED (flagged, not learned from) |
| 4 | High | A late-delivered play is learned at the hour it arrived, not the hour it was played | FIXED |
| 5 | Med | `/next` and `/feedback`: bad input is a 500; `count` unbounded | FIXED |
| 6 | Med | `/feedback` session cache has no bound; the `/next` eviction can drop the live session | FIXED |
| 7 | Med | `record_play`: no validation, 5+ write transactions per play, leaks the connection on error | FIXED |
| 8 | Med | Impressions are counted again on every retry | FIXED (opt-in `batch_id`) |
| 9 | Med | A failing model rebuild is retried every 60 s forever; a hung one blocks every user | FIXED |
| 10 | Med | The server keeps no record of what it served | FIXED |
| 11 | Low | `DELETE /me/history` leaves the rest of the history behind (new tables) | FIXED |
| 12 | Low | Weather cache written non-atomically; weather fetched on the request path | PARTLY (atomic write fixed; fetch on request path OPEN) |
| 13 | Low | Hour-of-day is IST for every user (`ist_hour`) | OPEN (column added, readers unchanged: Part C) |
| 14 | Low | `navidrome_sync` rows are used as real plays by the legacy model | OPEN (flagged only) |
| 15 | Low | startcopy: unbounded per-IP failure map, no WAL on its state db | OPEN |
| 16 | Info | session server and fakescan | no listening-data bugs found |

## 1. Nightly sync invents plays (High)

`sync_navidrome.py:76-82` counts **every** `play_events` row per title (skips included) as "already synced"; `:115` takes `diff = navidrome_count - that`; `:148` inserts `diff` rows that all carry the **same** `played_at` / hour (Navidrome only stores the last play date) with `listen_ratio = 1.0`, `end_reason = natural`.

Failing scenario: a song with 6 skips and 1 real listen has 7 rows, so a Navidrome count of 8 adds one row. A song Navidrome says was played 5 times but the app logged once adds 4 rows stamped with one instant: a burst. In the copy, 2,226 of 8,486 rows are sync rows and 1,670 are extra rows sharing a timestamp.

Fix: only rows that stand for a listen Navidrome would count (`listen_ratio >= 0.5`, or an earlier sync row, never a suspect burst) are compared; rows get a deterministic `play_id` (`ndsync:<title hash>:<n>`) and `INSERT OR IGNORE`, so a re-run cannot double them; all but the newest of a song's invented rows are tagged `quality = 'synthetic_time'`; `origin = 'navidrome_sync'`.

## 2. Fake weather (High)

The app never set `weatherCode`/`temperatureC`, so `FeedbackRequest` sent its defaults 800 / 25.0 for every play, and `feedback.py:174-175` stored them. 6,092 of 6,260 app rows (97.3 %). Separately `sync_navidrome.py:109` reads `weather.get("weather_code")` but the cache key is `code` (`weather.py:78`), so every sync row has a NULL code and today's temperature.

Fix: the server ignores client weather and stamps its own cached reading (`play_events.weather_at`) when the cache is within 2 h of the play, else NULL. Sync rows get NULL (the cache holds now, not then). The app stops sending weather. Existing rows: `flag_bad_rows.py --null-fake-weather` (opt-in).

## 3. Fake "natural at 0 %" rows (High)

The app's mediaItem fallback read the position at the instant the song changed (already the next song's 0:00) and logged `natural`, ratio 0: 475 rows, 7.6 % of app rows. `server.py:795-816` + `recommender.py:247-262` treat ratio `< SKIP_RATIO` as a skip, so each of these taught the live model "skipped" for a song that finished.

Fix (both sides): the app measures real listening and drops a natural end with nothing heard; the server stores such a row from an old app but flags it `suspect_burst` and does **not** fold it into live state.

## 4. Late plays learned at the wrong hour (High)

`recommender.py:251` uses `datetime.now(IST)` for hour and weekday when folding a play. The app's outbox delivers plays minutes to days late (offline), so the hour-of-day statistic used for recommendations records the delivery hour. Fix: the server passes the play's own time; decay timestamps stay "now" so counters never see time go backwards. The hour is the user's local hour (`tz_offset_min`), IST when unknown.

## 5. Input crashes (Medium)

`server.py:467,469,470,528`: `int(data.get("depth"))` etc. raise `ValueError` on `"abc"`, `None` is a `TypeError`: **500** to the app. `:473-475` call `.strip()` on a value the client may send as a number or list: 500. `:463,:783,:829` use `request.json or {}`: a JSON list body raises. `:470` `count` has no upper bound (`count=10**9` makes the model score a million rows). Fix: `safe_int` / `safe_str`, `get_json(silent=True)`, `count` 1..200.

## 6. Session cache (Medium)

`server.py:802` (`/feedback`) adds to `_session_played` with no eviction at all: any caller can grow it with fresh `session_id`s. The `/next` eviction (`:509-512`) removes `next(iter(...))`, the oldest key, which can be the session being served. Fix: `bound_session_cache` (oldest first, never the live key), applied on both paths.

## 7. `record_play` (Medium)

`feedback.py:146-205`: `init_db` runs on every call (`CREATE TABLE`, `CREATE TABLE impressions`, three `ALTER TABLE` that fail and are swallowed, `CREATE INDEX`: several write transactions per play, each taking the write lock). Nothing is validated (`listen_ratio` as text or `-1` or `NaN` is stored; `title` missing is an `IntegrityError` that surfaces as a 500, the test file even pins it). The connection is not closed on any error other than the play_id one. Plays from old apps (no `play_id`) are never de-duplicated.

Fix: `play_events.ingest`: schema once per process, one `BEGIN IMMEDIATE` transaction, `finally: close`, validation with reasons counted in `rejected_counts` (422, which the app's outbox treats as final), soft de-duplication of id-less plays in the same second.

## 8. Impressions (Medium)

`feedback.py:208-238` adds 1 to `shown_count` per title per call. A re-sent request (proxy retry, impatient client) counts again, so "shown but never played" demotion inflates. Lists were unbounded. Fix: optional `batch_id` (the app now sends one); a repeat is counted once; lists capped at 200.

## 9. Rebuild loop (Medium)

`scheduler.py:57-87`: `subprocess.run([... preprocess.py --update ...], check=True)` has no timeout and its failure is caught per user, then retried after 60 s forever. A user whose rebuild always fails costs a full preprocess run every minute; one that hangs stops rebuilds for every user. Fix: 30-minute timeout, per-user exponential backoff up to 1 h.

## 10. No record of what was served (Medium)

`/next` returns a queue and keeps nothing, so no evaluation can know what the AI offered. Fix: `served_batches` / `served_items` (rank, title, id, score, engine) and a `served_id` in the response, echoed by the app in each play event.

## 11. History erase (Low)

`server.py:996-1015` deletes only `play_events`. The v2 tables hold the same history (aux events, served items, refused samples, impressions). Fix: `erase_extra_tables`.

## 12. Weather cache (Low)

`weather.py:80-110`: the cache is written with `open(path, "w")` while `/next` (every request, `server.py:460`) and `/ready` (`:865`) read it, so a reader can see half a file (it then refetches). `get_cached_weather` fetches over the network (5 s timeout) **on the request path** when the cache is older than 30 min; the scheduler's loop (30 min) means this mostly races. When Open-Meteo fails and there is no cache it returns an invented clear/28 °C without saying so. Fix applied: atomic write. Not changed: fetch on the request path and the invented default (needs a decision on what `/next` should do without weather).

## 13. Local hour (Low, Part C)

`ist_hour`, `day_of_week`, `month` are computed in IST for every user (`feedback.py:158-160`, `sync_navidrome.py:144`, `recommender.py:251`). Right for the owner, wrong for anyone elsewhere. New rows carry `tz_offset_min` and `local_hour`; the readers (`preprocess.py:131`, `recsys/data.py:174`, `model.py:312`) still use IST and are ranking logic, so they are left for Part C.

## 14. Sync rows in the legacy model (Low)

`recsys/data.py:178` correctly skips `navidrome_sync` rows; `preprocess.py` (legacy model, still the fallback) does not. They now carry `origin`/`quality` so it can.

## 15. startcopy (Low)

`startcopy/server.py`: `_fail` (per-IP login failures) is never pruned; `_auth_cache.clear()` at 512 entries is a cliff, not an LRU; the state database is opened without WAL, so the worker's writes and the server's reads share a rollback journal (30 s timeout, so no failure seen). Path traversal is guarded (`core._resolve`); ids are validated; ranges are validated. No listening data.

## 16. Reviewed, nothing found

* `session.py` keeps queue/position state in memory only (no listening data on disk). Rate-limits, size checks and auth failure paths are present. Messages over the rate limit are dropped silently by design.
* `fakescan` only reads music files and writes its own table.
* `tg-fetcher/history_import.py` writes `play_events` with `INSERT OR IGNORE` on a `play_id` (idempotent) and `session_id = import:<source>`; the data-quality script reports them as origin `import`.

## What the data looks like today (copy of `admin`, 8,486 rows)

| Check | Result |
|-------|--------|
| Rows by origin | 6,260 app, 2,226 navidrome_sync |
| Extra rows sharing one song and one second | 1,766 (1,670 from the sync) |
| Fake burst rows (natural, ratio 0) | 475 = 7.6 % of app rows |
| Constant 800 / 25.0 weather | 6,092 = 97.3 % of app rows |
| Rows with a `play_id` | 3 % of app rows (old builds) |
| Rows with `seconds_played`, `tz_offset_min`, `play_source`, `slot`, `score`, `served_by`, `holdout` | none (columns did not exist) |
| Skipped at 100 % ("fwdbtn" with ratio 1.0) | 34 |

Re-run it any time: `python3 tool/shuffle_eval/data_quality.py --dir /DATA/AppData/navivibe/listening_logs`.
