# hybrid-shadow-v1

The Smart Shuffle hybrid (blend top-100, then a LightGBM re-ranker) running in **shadow**: it ranks the song that was really played, next to v3 and to the plain blend, and records the three ranks. Nothing the listener sees changes until you set `HYBRID_ORDER=on`.

Built to `docs/hybrid-shadow-spec.md`; reference code `tool/shuffle_eval/bakeoff/hybrid.py`; evidence `docs/smart-shuffle-bakeoff.md`. Needs **play-events-v2** installed first (`served_id`, quality tags, the play's own time).

## Same code as the harness

`navivibe/hybrid.py` on the server **is** `tool/shuffle_eval/bakeoff/hybrid.py`, byte for byte (blend weights, candidates, the 12 extra columns, the 45 `NO_AUDIO_MOOD_COLS`, LightGBM parameters, `FeatureMatrix`, `Reranker`, `training_group`). Nothing is re-implemented. The tests check it three ways:

* the file's hash equals the harness file's (and, in the repo, the two files are equal);
* the same inputs through the harness code and through the server's code give identical blend scores, identical 100 candidates and identical re-rank scores (same fitted booster);
* a play's three ranks, computed by the server path, equal the harness's rank formula (ties count half a place).

## Flag: `HYBRID_ORDER=off|shadow|on` (default `shadow`)

Independent of `AI_ORDER` (untouched). Set it in `/opt/shuffle-server/.env`, restart `navivibe`. Anything that is not `off` / `on` counts as `shadow`.

| value | `/next` response | background work |
|-------|------------------|-----------------|
| `off` | as today | none (the nightly fit is skipped too) |
| `shadow` | **byte-identical to today** | the two shadow logs below |
| `on` | next-song positions (the session already has a kept song) come in the hybrid's order, engine `v3+hybrid`; **openers stay on v3**; no model or any error: the v3 queue is served unchanged | same as shadow |

## What is recorded (in the listener's own log database)

**`hybrid_shadow_plays`: the flip data.** One row per kept next-song play, ranked when its feedback arrives and **before the state learns the play**: `rank_v3`, `rank_blend`, `rank_hybrid` of the song really played (all over the same allowed songs: not already heard, not blocked; ties half a place), `in_top100`, `depth`, `session_id`, `song_id`, `extra_ms` (blend + extras + re-rank, v3's own feature build excluded), `inline_ms`, `status`, `error`. Not scored: openers, a play under 30 %, a song already heard this session, rows tagged by the data pipeline, Navidrome-sync rows (they never reach `on_feedback`).

**`hybrid_shadow`: informational.** One row per eligible `/next` request (`smart` and `smart_candidates`, not a reshuffle): the hybrid's top 20 with scores beside the 20 ids served, `served_id` (joins to play-events-v2), position kind, latency. The listener hears v3's order, which favours v3, so this is not used for the flip.

Both are erased by `DELETE /me/history`.

## Where the work happens, and the limits

* `/next`: queued from `Response.call_on_close`, after the body is sent.
* `/feedback`: the one inline step is building the two feature matrices from the state as it is **before** the play is learned (it cannot be done later without leaking the play into its own features); about 15 ms of the `/feedback` POST, which the app sends from its background outbox. The ranking and the database write run in the worker.
* One worker thread, a 64-job queue (at most 16 jobs hold matrices, about 1 MB each), a budget per job (`HYBRID_BUDGET_MS`, default 2000): a job that waited longer is not run, one that overruns is an error row. A failure is a row with `status = 'error'`; nothing is raised into a request.
* **Server CPU/memory were not measured here.** The spec's dev-PC numbers: hybrid extra 1.1-1.3 ms p50 per ranking, 0.6 MB per ranking. Read the server's real figures from `extra_ms` after some listening. The flip criterion refuses a p95 above 10 ms.

## The model and the nightly fit

* `models/hybrid/hybrid_v1.json`: one JSON file (model, column lists, metrics, parameters, the v3 artifact version it was fitted against), replaced in a single rename, previous kept as `.prev`.
* **Used only when compatible**: its columns equal the harness's, and it was fitted against the same v3 artifacts (`models/v3/meta.json` `trained_at`), because the co-listen and name vectors must be the ones the groups were built with. Otherwise shadow stays off and the log says why. After a v3 retrain the hybrid is therefore off until its own refit.
* Fit at 03:54 IST (after v3's 03:30), a separate process, 30-minute timeout, retried after 10, 20, 40 minutes on failure, skipped while `off`. Loads v3's saved vectors the way the engine does, replays all history, one group per qualifying play of the last 60 days (all listeners): the blend's 100 candidates, label on the played song; a play outside the 100 makes no group. Deterministic. At most 6,000 groups (~110 MB at fit time); under 200 groups nothing is replaced.
* Excluded from the groups (still replayed into the state): rows tagged `suspect_burst`, `synthetic_time`, `impossible`, `clock_clamped`; `import:*` sessions; Apple/legacy history. Logs from before the data pipeline are used as they are.

## Install (owner, as `subi`; sudo only for the restart)

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

Restart (shadow is the default; the start runs `preprocess --full`, so wait):

```bash
sudo systemctl restart navivibe
```

```bash
sleep 60; curl -s http://127.0.0.1:5500/ready; echo
```

Fit the first model now instead of waiting for 03:54 (reads the logs, writes only `models/hybrid/hybrid_v1.json`; a few minutes):

```bash
cd /opt/shuffle-server && venv/bin/python -m navivibe.hybrid_train
```

Until a compatible model exists nothing is recorded (that is intended).

## See shadow rows after some listening

Per-play rows (needs a few kept plays after the model exists):

```bash
sqlite3 -readonly /DATA/AppData/navivibe/listening_logs/admin_listening_log.db "select status, count(*), round(avg(rank_v3),1), round(avg(rank_blend),1), round(avg(rank_hybrid),1), round(avg(extra_ms),2) from hybrid_shadow_plays group by 1;"
```

Per-request rows and errors:

```bash
sqlite3 -readonly /DATA/AppData/navivibe/listening_logs/admin_listening_log.db "select status, position_kind, count(*), round(avg(latency_ms)) from hybrid_shadow group by 1,2; select error, count(*) from hybrid_shadow_plays where status='error' group by 1;"
```

The flip report, on a COPY of the logs:

```bash
mkdir -p ~/shadow-copy && cp /DATA/AppData/navivibe/listening_logs/*_listening_log.db ~/shadow-copy/ && python3 ~/shuffle_eval/shadow_report.py --dir ~/shadow-copy --owner admin
```

Copy `tool/shuffle_eval` to `~/shuffle_eval` first. The report applies the spec's rule: after 400 owner plays in 60 sessions, on if the lower bound of (hybrid - v3) HR@10 is above +5 points; otherwise look again at 1,200, then keep v3; errors under 1%, p95 extra latency under 10 ms, 60% of played songs in the top 100, no NaN/column errors; hybrid-or-blend decided at 1,200.

## Switching on (only when the report says so)

Set `HYBRID_ORDER=on` in `/opt/shuffle-server/.env`, then `sudo systemctl restart navivibe`. Back to shadow or off is the same edit. After the flip the spec asks for a ~20% v3 holdout and a skip-rate tripwire (not built here: that needs the app's `holdout` flag for server-side sessions).

## Rollback

The installer prints it: restore the backup's `server.py`, `scheduler.py` and `recsys/recommender.py`, delete the `hybrid*.py` files and the test, restart. The two tables are harmless to old code.

## Tests

`navivibe/tests/test_hybrid_shadow_v1.py` (49, none skipped; the harness reference copy `harness_hybrid_reference.py` ships beside it): parity with the harness, the whole nightly fit end to end (stubbed world), model file and compatibility (an unknown v3 stamp is NOT compatible), flag, shadow queued only after the response closes, `/next` body identical in off and shadow, per-play rules (openers, skips, heard songs, quality tags, pre-update build), exact rank values, failure isolation (compute error, budget, stale job, full queue, matrix cap, write failure, garbage input), serving only for next positions and only with a model, training recipe and exclusions, deterministic fit, old logs. The installer also runs the play-events, v3, hardening and security tests. `tool/shuffle_eval/tests/test_shadow_report.py` covers the report and the criterion.
