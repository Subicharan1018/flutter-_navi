# hybrid-shadow-v1

The Smart Shuffle hybrid (blend top-100, then a LightGBM re-ranker) running in **shadow**: it ranks every eligible `/next` request next to the real answer and records what it would have said. Nothing the listener sees changes until you set `HYBRID_ORDER=on`.

Background and numbers: `docs/smart-shuffle-bakeoff.md`, `docs/smart-shuffle-research-opus.md`. Needs **play-events-v2** installed first (it provides `served_id`).

## Flag: `HYBRID_ORDER=off|shadow|on` (default `shadow`)

Independent of `AI_ORDER` (which keeps ordering the v3 queue, untouched). Set it in `/opt/shuffle-server/.env`, restart `navivibe`. Anything that is not `off` / `on` counts as `shadow`.

| value | `/next` response | background work |
|-------|------------------|-----------------|
| `off` | as today | none (the nightly fit is skipped too) |
| `shadow` | **byte-identical to today** | after the response is sent, one worker computes the hybrid ranking and writes a row |
| `on` | next-song positions (the session already has a kept song) come in the hybrid's order, engine `v3+hybrid`; **openers stay on v3**; no model or any error: the v3 queue is served unchanged | same rows as shadow |

Eligible = `mode` is `smart` or `smart_candidates` (the app's Smart Local pool), not a reshuffle. Playlist, trending and random modes are not shadowed.

## What a shadow row holds (`hybrid_shadow`, in the listener's own log database)

`created_at, served_id` (joins to play-events-v2's `served_batches` / `served_items` and to `play_events.served_id`), `user, session_id, position_kind` (`opener` / `next`), `mode, model_version` (`blend-only` before the first fit), `blend_version, status` (`ok` / `error`), `error` (`budget`, `stale`, an exception name), `top_ids` (20 Navidrome ids, best first), `top_scores`, `n_allowed`, `served_ids` (the first 20 of what v3 returned), `latency_ms, queue_wait_ms`.

The ranking excludes the songs already heard in the session and the user's blocked songs, and respects the app's candidate pool, exactly as `V3Engine.recommend` does.

## Hard rules and how they are kept

* **No listener latency.** The job is queued from `Response.call_on_close` (after the body is sent). `submit` never blocks or raises; a full queue (64) drops the job and counts it.
* **Bounded.** One worker thread, one job at a time, a time budget per job (`HYBRID_BUDGET_MS`, default 2000): a job that waited longer than that is not run, one that overruns is recorded as an error. A failure is a row with `status = 'error'`; nothing reaches the request. The model is ~100 KB; a ranking is ~1 ms of numpy and LightGBM on top of v3's own feature build (take `latency_ms` from the table on the real server: that number was not measurable off-server).
* **Deterministic fit.** Fixed seeds, `deterministic=True`, fixed thread count, ties go to the lower song index; the same data gives the same model file (tested).
* **Nightly fit** at 03:54 IST (`HYBRID_FIT_HOUR_IST`), after the v3 retrain, in a separate process with a 30-minute timeout; a failure is retried after 10, 20, 40 minutes and then left until the next night. Skipped while `off`.
* **Training data.** The last 60 days of plays of all listeners, one group per play (blend top-100, label = the song played; a play outside the blend's top 100 makes no group, it is not added by hand). Excluded from the groups, but still replayed into the listener's state: rows tagged `suspect_burst`, `synthetic_time`, `impossible`, `clock_clamped`; Navidrome-sync rows; `import:*` sessions; Apple / legacy history. Logs from before the data pipeline (no `quality` column) are used as they are. At most 6,000 groups (about 120 MB at fit time).
* **Atomic model file.** `models/hybrid/hybrid_v1.json` is one JSON file (model, blend weights, version, training metrics, parameters) replaced in a single rename; the previous one stays as `.prev`. The server re-reads it when its mtime changes. Training metrics are printed by the fit and kept inside the file.

## Placeholder to replace

The blend weights (`DEFAULT_BLEND`, `BLEND_VERSION = "placeholder-1"` in `hybrid_core.py`) are placeholders until the research harness (`tool/shuffle_eval/bakeoff/`, `docs/hybrid-shadow-spec.md`) is merged. They are saved in every model and in every row's `blend_version`, so rows made with other weights are never pooled by mistake. Changing them is one dict and a refit; no code path changes.

## Install (owner, as `subi`, no sudo except the restart)

Copy the folder to the server:

```powershell
scp -r tool/server/hybrid-shadow-v1 subi@100.99.105.51:~/
```

Check on a scratch copy (installs nothing):

```bash
cd ~/hybrid-shadow-v1 && bash install.sh --check
```

Install (backs up, patches, tests the live tree, restores if a test fails, does not restart):

```bash
bash install.sh
```

Restart (shadow is the default):

```bash
sudo systemctl restart navivibe
```

```bash
sleep 60; curl -s http://127.0.0.1:5500/ready; echo
```

Fit the first model now instead of waiting for 03:54 (reads the logs, writes only `models/hybrid/hybrid_v1.json`):

```bash
cd /opt/shuffle-server && venv/bin/python -m navivibe.hybrid_train
```

## Check that it works after some listening

Shadow rows exist (make a few `/next` requests from the app first):

```bash
sqlite3 -readonly /DATA/AppData/navivibe/listening_logs/admin_listening_log.db "select status, position_kind, model_version, count(*), round(avg(latency_ms)) from hybrid_shadow group by 1,2,3;"
```

Errors, if any:

```bash
sqlite3 -readonly /DATA/AppData/navivibe/listening_logs/admin_listening_log.db "select error, count(*) from hybrid_shadow where status='error' group by 1;"
```

Score it (on a copy of the logs, not the live files):

```bash
mkdir -p ~/shadow-copy && cp /DATA/AppData/navivibe/listening_logs/*_listening_log.db ~/shadow-copy/ && python3 ~/shuffle_eval/shadow_report.py --dir ~/shadow-copy --owner admin
```

`shadow_report.py` is in `tool/shuffle_eval/` (copy that folder to `~/shuffle_eval`).

## Switching on (later, only after the report says the criterion is met)

Set `HYBRID_ORDER=on` in `/opt/shuffle-server/.env`, then `sudo systemctl restart navivibe`. Back to shadow or off is the same edit. `AI_ORDER` is not involved.

## Rollback

The installer prints it. In short: restore the backup folder's `server.py` and `scheduler.py`, delete the three `hybrid_*.py` files and the test, restart. The `hybrid_shadow` table in each log is harmless to old code.

## Tests

`navivibe/tests/test_hybrid_shadow_v1.py` (39 tests): determinism, flag behaviour, heard songs and candidate pool respected, `/next` body identical in off and shadow, failure isolation (compute error, budget, stale job, full queue, database write failure, garbage input), serving only for next positions and only with a model, old logs without the new columns, training exclusions. The installer also runs the play-events and hardening tests.
