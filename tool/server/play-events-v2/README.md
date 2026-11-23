# play-events-v2

Makes the listening data trustworthy: one validated, idempotent door for every play event, server-side weather, a log of what `/next` served, and the server bugs in `docs/audit/server-bugs.md`.

Built on the live code read on 23 Nov 2026. Field list: `docs/play-event-schema.md`.

## What it changes on the server

| File | Change |
|------|--------|
| `navivibe/play_events.py` | **new.** `ingest` (validate, count refusals, store once), `handle_feedback` (the whole `/feedback` body), `log_served`, `record_impressions_once`, `weather_at`, `safe_int` / `safe_str`, `bound_session_cache`, `erase_extra_tables` |
| `navivibe/server.py` | `/feedback` calls `handle_feedback`; `/next` parses input safely (`count` 1..200), logs the served batch and returns `served_id`; `/feedback/impressions` takes `batch_id`; the session cache is bounded; `DELETE /me/history` also clears the v2 tables |
| `navivibe/recsys/recommender.py` | `on_feedback` learns a play at the hour it was played (local hour), not the hour it arrived |
| `navivibe/scheduler.py` | a failing model rebuild backs off (up to 1 h) and has a 30-minute timeout |
| `navivibe/sync_navidrome.py` | no more invented same-timestamp plays; idempotent ids; no fake weather; rows tagged `origin` / `quality` |
| `navivibe/weather.py` | the cache file is written atomically |

The edits are exact-text replacements (`patch.py`): if the live text differs, nothing is written and it says which edit did not match. Re-running changes nothing.

Old apps keep working: the old payload is accepted (stored as version 1). Schema upgrade of each listening log happens inside the service on the first event after the restart (added nullable columns and tables; the old code ignores them).

## Install (owner, as `subi`, no sudo)

Check first. This patches a **scratch copy** of the live code and runs the tests there; it installs nothing:

```bash
cd ~/play-events-v2 && bash install.sh --check
```

Then install (backs up, patches, tests the live tree, restores everything if a test fails; does not restart anything):

```bash
bash install.sh
```

Restart (the start runs `preprocess --full` first, so wait):

```bash
sudo systemctl restart navivibe
```

```bash
sleep 60; curl -s http://127.0.0.1:5500/ready; echo
```

The nightly Navidrome sync starts a fresh Python each night and picks up its fix by itself. `navivibe-session` is not touched.

Rollback: the installer prints it (restore the backup folder, delete `play_events.py`, restart).

## Tests

`navivibe/tests/test_play_events_v2.py` (38 tests, temp log folder): idempotency (repeat, concurrent, old payload), every refusal reason, timestamps and local hour, server-side weather, served log, route behaviour, session-cache bound, history erase. The installer also runs `test_feedback_played_at.py` (the existing `/feedback` route tests: old payloads must behave as before), `test_hardening.py` and `test_security.py`.

## What it does not do

* It does not change ranking. `ist_hour` stays what the models read; `local_hour` is stored beside it for Part C.
* It does not touch existing rows. Flag them with `tool/shuffle_eval/flag_bad_rows.py` (backup first, dry run by default, owner-run).
* `get_cached_weather` still fetches over the network on the request path when the cache is stale (needs a decision; see the audit, item 12).
