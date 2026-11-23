# Hybrid ranker in shadow: spec for the live server (2026-11-23)

Owner decision: build the hybrid in **shadow**, session openers stay on v3. Reference code: `tool/shuffle_eval/bakeoff/`. Evidence: `docs/smart-shuffle-bakeoff.md`.
Labels: **[measured]** here, **[code]** read from the server code, **[estimated]**.

## What was and was not tested

Offline, each method ranked the one song really played next, with the real session so far and state updated after every play. The live `/next` differs, and **none of this was tested** [code]:

- it builds a 15-song queue in one go, feeding its own picks back as if they had been played, so slots 2+ see a guessed session;
- it adds a chart boost, then **samples** from the top 40 (`V3_TEMPERATURE` 0.35, 0.5 at openers) instead of taking the top;
- it keeps one exploration slot, film-run limits and a listener block list.

So offline HR@10 measures the *ranker*, not the *queue a listener hears*. Shadow should measure the first cleanly; only a live holdout measures the second.

## Where to hook: at the play, not only at `/next`

Score the hybrid **when a kept play's feedback arrives, before the state update** (`V3Engine.on_feedback`, called from `play_events.handle_feedback`). That is exactly the offline protocol: real session context, pre-play state, the song as ground truth. Log one row per next-song play: v3's rank and the hybrid's rank of that song (ties count half a place), plus the blend's.

Rules:
- Use the play's **start time** for the state clock and hour where v2 provides it; offline used the logged timestamps.
- Only plays with a kept song earlier in the session (`kept` not empty). No kept song = opener = v3, do not score the hybrid.
- Skip plays with ratio < 0.3, songs already in the session's played set, refused/duplicate events, rows flagged bad quality, and Navidrome-sync rows.
- Do not let shadow work delay or fail the request: copy what is needed under the user lock, run off the request path, catch everything, count errors.
- Optionally also re-rank at `/next` and log the order beside the served one; useful for latency and structure, **not** for the flip decision, because the listener then hears v3's order.
- Never store anything a reader could not delete: keep shadow rows in the listener's own log database so `DELETE /me/history` can clear them (it must also clear this new table), and do not log other listeners' data in it.

Suggested row: time, session id, song id, depth, rank_v3, rank_blend, rank_hybrid, in_top100, model version, ms, error.

## What the server computes per request

1. `X = FeatureBuilder.build(...)`, the matrix v3 already builds [code].
2. `hb, M = FeatureMatrix.build(X, us, kept, ts, hour, month)`: blend + extras.
3. `allowed`: not in the session's played set (live also: blocked songs, candidate restriction; apply these to all three ranks).
4. `Reranker.scores(M, hb, allowed)`: top-100 by blend, LightGBM on the 45 `NO_AUDIO_MOOD_COLS`, z-score, placed above the rest.

Inputs, all held in memory by v3 today [code]: user state, global state, session context, catalog, co-listen and name embeddings. No mood file, audio vectors or weather.
Training: nightly, after v3's own training, with groups from the replay it already does (last 60 days, all listeners). Save the model with the same artifact version as v3's embeddings: **the co-listen and name vectors must be the ones the groups were built with.** If the hybrid model is missing or its feature list does not match, shadow stays off.

## Cost

Measured on the dev PC (Intel Core Ultra 5 225H), **not on the server** (Ryzen 5 6600H, 12 threads, about 9.6 GB free when checked):

| item | p50 | p95 |
|---|---|---|
| v3's feature matrix (already paid) | 12-14 ms | 13-19 ms |
| **hybrid extra per ranking** (blend, extras, re-rank 100) | **1.1-1.3 ms** | **1.5-1.8 ms** |

- Per play (the hook above): one ranking, so about 1-2 ms plus the feature build if it is not reused [estimated for the server].
- If run at `/next` for 15 slots: roughly 17-20 ms typical, 27 ms at p95 [estimated], single-threaded.
- Memory: 0.6 MB per ranking (2,486 songs x 60 float32); training matrix about 42 MB (1,729 groups x 100 x 60) plus LightGBM; model well under 1 MB [estimated from array sizes].
- Measure both on the server before turning anything on; refuse to ship if p95 extra exceeds 10 ms per ranking.

## Flip criterion (next-song positions only)

The comparison is paired: both rankers scored on the same plays, cluster-bootstrapped by session. From the offline run, owner next song, 2,370 plays in 349 sessions [measured]:

| difference | effect seen | standard error at 2,370 plays | plays to detect a true +3 points (80% power, 5%) |
|---|---|---|---|
| hybrid - v3 | +15.0 [+12.2, +17.7] | 1.39 | about 4,000 |
| hybrid - blend | +2.5 [+1.1, +4.0] | 0.75 | about 1,170 |

The v3 effect is far above 3 points, so it needs few plays; detecting only +3 over v3 would need about 4,000. The hybrid-over-blend gain really is about 3, so it needs about 1,200 plays (about 1,700 if the true gain is 2.5). These assume the offline variance holds live. Owner volume offline was about 26 next-song plays a day, so 1,200 plays is **about 45 days, 4,000 about 5 months**; the other listeners together gave about 5 a day.

Proposed rule, decided now so it cannot drift:

1. **After 400 scored owner next-song plays in at least 60 sessions**, look once: turn on the hybrid for next-song positions if the 95% lower bound of (hybrid - v3) HR@10 is above **+5 points**. (At 400 plays the standard error is about 3.4, so an effect of 15 would give a lower bound near +8; an effect of 5 would not pass.)
2. If it does not pass, look again at 1,200 plays; if still not, keep v3 and stop.
3. Required either way: errors under 1% of scored plays; p95 extra latency as above; at least 60% of played songs inside the top 100 (offline recall 70%); no day with a NaN or a missing column.
4. Decide "hybrid or plain blend?" separately: keep the model only if hybrid - blend has a lower bound above 0 at 1,200 plays. If not, serve the blend: simpler and almost as good.
5. Judge the owner only. Other listeners show +3.7 [-3.2, +9.1] vs v3 (n=461) and cannot support a decision; leave them on v3 or the blend.
6. Shadow plays were chosen from v3's queue, which favours v3, so shadow understates the hybrid if anything. It does **not** show that listeners skip less.

**After the flip**, hold out about 20% of sessions on v3 (the `holdout` column exists) and watch the skip rate. Detecting a fall from 5.7% to 4.3% takes about **3,800 plays per arm** [estimated, no clustering], i.e. months. Use it as a tripwire: if the treated arm's skip rate is clearly above v3's (lower 95% bound of the difference above 0) after 500 plays per arm, switch back.

## Risks and lessons from building the harness

- **One missing value can kill a feature.** A single song with no energy made every weighted average over the catalog NaN, and a later `nan_to_num` turned that into an all-zero column with no error. Impute on a copy, and assert that no feature column is constant over a training day.
- **Do not silence NaN with `nan_to_num` without checking why.** I did exactly that once; it hid the dead columns.
- **Do not mutate v3's arrays.** Imputing the shared energy array moved v3's own HR@10 by about 0.7 points.
- **Never force the played song into the candidate group.** It makes the model learn "low stage-1 rank = positive".
- **Determinism.** `embeddings.names()` starts its SVD from a random vector. Two unseeded runs give very different vectors (cosines differ by up to about 0.7), and v3 moved by up to about 0.7 points between runs. Seed numpy before building embeddings, use the LightGBM settings in `hybrid.py`, and treat any one-model gap under about 1 point as noise.
- **Ties.** Light listeners have hundreds of equal scores. Use a stable sort for candidates and count ties as half a place, or light listeners' numbers are inflated.
- **Feature order.** The model reads columns by position in `ALL_COLS`; if `FEATURES` changes on the server, retrain and check names before use (v3 already reads its columns by name).
- **Selection bias.** Training and evaluation use plays that older algorithms chose. Retraining on the hybrid's own output later will amplify it; keep the v3 holdout.
- **Cold songs.** The hybrid almost never ranks a never-played song (0% hit rate on them for the owner). `/next`'s exploration slot must stay.
- **Burst rows.** Fake "natural, ratio 0" rows still sit in older history and reach user state; v2 refuses new ones [code] but does not delete old ones.
- **Small data.** 1,000 to 1,700 groups and early stopping at 20-71 rounds: do not add features without rerunning the held-out test.

## Not measured

Server-CPU latency and memory; multi-slot queues; interaction with the chart boost, sampling and block list; live skip outcomes; any listener but the owner with useful power.
