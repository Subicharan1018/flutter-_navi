# Smart Shuffle and autoplay: what will really make it better (2026-11-23)

Research only. Nothing on the server or in the app was changed. Server access was read-only: `scp` copies of the catalog, the listening-log databases, `ai_order_log.jsonl` and the server's own `navivibe/` code. Every analysis ran on those copies on the dev PC.
This builds on `docs/smart-shuffle-eval.md` (AI order, 2026-11-08) and the unmerged `docs/smart-shuffle-data-eval.md` on branch `claude/shuffle-data-eval-f12997` (data audit, hand blend). It does not redo them.

**What is new here.** That earlier work compared re-implementations of the *ideas*. This report runs the **server's real v3 LightGBM ranker** (its own `recsys/evaluate.py` backtest code, retrained locally per window) and the **real legacy model** (`model.py`, built by `preprocess.build_model`) on identical held-out samples. Next to them it runs the planned hand blend, each planned step, a two-stage hybrid (blend picks 100 candidates, a trained re-ranker orders them) and 40+ candidate signals.

Labels: **[measured]** = computed here on held-out data; **[sourced]** = read from code, logs or the earlier reports; **[estimated]** = my reasoning, not measured.

## The answer in one table: what to build next

| # | Item | Measured lift (owner unless noted) | Effort [estimated] | Risk | Data needed |
|---|---|---|---|---|---|
| 1 | **Hand blend as the autoplay "next song" ranker** (recency + hour habit + usual-next-song; v3 stays for session openers) | **+11.7 pts HR@10 vs v3** [+9.5, +14.0], n=2,370 next-song plays. Others: +1.7 [-7.1, +9.2], n=461 | Low: every input already exists as a v3 feature column | Low | none |
| 2 | **Hybrid: blend top-100 → LightGBM re-ranker**, in `shadow` first | **+3.7 pts over the blend** [+2.2, +5.2]; +15.3 over v3 [+12.8, +17.9]. Openers: +8.6 over blend, equal to v3 (-0.2 [-3.3, +3.1]). Others: +0.9 [-1.4, +3.2] | Medium: reuse `FeatureBuilder`, one extra nightly fit (~1 min) | Low in shadow | none to train; `served_by` + holdout (1a) to judge it live |
| 3 | **Logging fixes (step 1a)**: served_by/slot/score, 10% holdout, real seconds, play source, queue edits; stop the burst rows | Retraining v3 on cleaned logs: owner -0.5 [-1.3, +0.2]; others +2.2 [-0.3, +4.6]. Its real value is that it makes every later decision measurable | Low-medium (app + server) | Low | this *is* the data step |
| 4 | **`AI_ORDER=memory`** | AI vs memory, unbiased subset: **-0.12 pairwise ordering accuracy** [-0.29, +0.03] (9 queues). 31% of `on` calls fall back; 0.72 s median latency added | One `.env` line + restart (owner does it) | None | none |
| 5 | **Opener: add 2-day rotation share** (`rot_share_2d`) to whatever opens a session | **+8.3 pts** over the blend at openers [+4.5, +12.5], n=265 | Low | Low | none |
| 6 | Cold-song guardrail (no cold opener; at most 1 cold song in positions 2-7) | HR@10: 0.0 change. Skips: at most **-0.6 pts** of a 10.1% skip rate | Low | Moves 64% of cold plays later (less discovery up front) | none |
| 7 | Discovery for light listeners | Not solved by anything tested. **45.6%** of other listeners' test plays are songs they had never played. The blend finds 0% of those, v3 8.1% | Medium-high | Medium | exposure logging (1a), queue edits |
| 8 | Energy/valence recalibration + 40-song mood check (step 1d) | **No ranking lift**: every audio/mood signal is within ±1 pt. Matters for Flow, mood chips and "Describe a mix" only | Low | Low | owner's 40 mood corrections |
| — | Do not build: real weather in the ranker, weekday features, audio/mood features in the ranker, the Groq AI order in the request path | Real weather (Apple history, 3,222 test plays): rain -0.2 [-0.6, +0.2], temperature +0.0 | — | — | — |

## Setup and sample sizes [measured]

- **Data.** Owner (u00), as the v3 loader reads it: 6,232 live app plays, 7,382 resolved Apple Music history plays, 545 legacy plays. Excluded: 2,226 `navidrome_sync` rows and 714 unresolved titles. 32 other listeners; only one (u10) has more than 100 test samples.
- **Split.** Three time-ordered windows. Each trains on everything before the cutoff and tests on the next 30 days; cutoffs are 2026-08-25, 2026-09-24 and 2026-10-25. User state updates online during the test window, as in production. This is the server's own backtest protocol (`recsys/evaluate.py`) with two changes:
  - ties count as half a place, instead of in the true song's favour (the server's version flatters count-based baselines for light listeners);
  - every method is scored on the same samples.
- **Targets.** Non-skipped plays not already heard in the session. "next" = at least one kept song earlier in the session; "start" = session opener. Ranked against the whole catalog (2,486 songs).
- **Samples.** Owner next 2,370 (349 sessions), owner start 491; others next 461 (108 sessions; 392 of the 678 other-listener samples are u10), others start 217.
- **Intervals.** 95% cluster bootstrap over sessions (1,000 resamples). Deltas are paired on the same samples.
- **Numbers differ from the earlier report.** Its 24.7% blend and 18.6% "old learned model" used a different protocol (folds by event count, songs already heard in the session not excluded, a re-implemented GBM). The comparable numbers here are blend 27.4% and the real v3 15.8%.

## Question 1: the four planned steps

### Baselines on identical samples (owner, next song) [measured]

| method | HR@1 | HR@10 [95% CI] | HR@50 | MRR |
|---|---|---|---|---|
| **hybrid (blend top-100 + LightGBM re-ranker)** | 11.4 | **31.1 [28.0, 34.6]** | 59.2 | 0.182 |
| hybrid + guardrails (cold rule, artist spacing) | 11.4 | 30.9 [27.9, 34.2] | 58.4 | 0.180 |
| v3 + blend (z-score sum) | 10.9 | 28.4 [25.1, 31.8] | 53.6 | 0.171 |
| **hand blend** (step b) | 11.0 | **27.4 [24.4, 30.8]** | 53.7 | 0.169 |
| hand blend + artist spacing + cold rule (b+c) | 11.0 | 27.4 [24.3, 30.8] | 53.5 | 0.169 |
| usual-next-song only | 10.6 | 22.7 [19.8, 25.7] | 43.7 | 0.153 |
| recency + hour habit | 3.7 | 21.0 [18.6, 23.4] | 50.6 | 0.098 |
| **v3 (current server model)** | 7.7 | **15.7 [12.6, 19.2]** | 31.9 | 0.109 |
| recent 7 days | 2.4 | 13.8 [12.0, 15.9] | 37.8 | 0.067 |
| popularity (own all-time) | 0.9 | 4.6 [3.6, 5.7] | 14.5 | 0.026 |
| **legacy model (`model.py`, the "old method")** | 0.0 | **2.0 [1.4, 2.7]** | 17.3 | 0.009 |
| random | 0.0 | 0.5 | 2.2 | 0.003 |

Session openers (owner, n=491) rank differently:

| method | HR@10 |
|---|---|
| **v3** | **28.5** [24.6, 32.6] |
| hybrid without audio/mood features | 29.5 [25.5, 33.8] |
| hybrid | 28.3 [24.4, 32.2] |
| recent 7 days | 24.8 |
| hand blend | **19.8** [16.3, 23.2] |
| legacy | 1.2 |

Notes:

- **Legacy.** `model.get_queue` returns a sampled 50-song queue, so anything outside it counts as a miss; HR@50 17.3% is the fairer reading. The "old method" in the strict sense (the hand-tuned `model.py`) is far behind both v3 and the blend.
- **What the owner likes about "previous methods"** is the transition and recency logic, which is exactly the blend. That part is right.
- **Why v3 is weak for the owner.** Its top feature by gain is `pop_global`, other listeners' popularity (`models/v3/meta.json` [sourced]). One ranker serves everyone, so the owner gets a model tilted toward light listeners.

### Verdicts

**(a) Fix in-app logging: YES, and do it first. It is a prerequisite, not a ranking gain.**
- **The glitch is still active [measured].** 186 burst rows, 3.0% of the owner's live rows, and they are increasing: 10 in August, 50 in September, 59 in October, 32 so far in November. The fallback that writes them is now at `lib/providers/player_provider.dart:1407-1427` (was ~1272) [sourced].
- **Weather and temperature are still the app defaults** (`feedback_request.dart:44-45`, 800 / 25.0 °C) [sourced]. Every play since 2026-10-01 has code 800 or empty [measured].
- **Retraining v3 on cleaned logs** (bursts dropped, 221 lost-position rows repaired):

  | listener | v3 HR@10 change | n |
  |---|---|---|
  | owner, next | -0.5 [-1.3, +0.2] | 2,370 |
  | others, next | +2.2 [-0.3, +4.6] | 461 |
  | others, start | +1.4 [-1.4, +4.1] | 217 |

  The blend does not move (±0.5). So cleaning matters a little for light listeners and not for the owner's ranking. It does matter for skip statistics: the earlier report measured the owner's skip rate at 13.0% raw vs 8.3% clean.
- **What cannot be measured offline** is the main reason for 1a. Without `served_by`/slot/score and a holdout, no live A/B is possible, which is why the AI-order question stayed open for a month.

**(b) Blend as the autoplay baseline: YES for the next song, NO for session openers.**
- **Next song:** owner +11.7 pts over v3 [+9.5, +14.0], n=2,370, consistent in all three windows (26.9 / 25.5 / 29.1% vs 14.5 / 13.4 / 18.0%). Others +1.7 [-7.1, +9.2], n=461 (no difference shown).
- **Openers:** the blend loses to v3 by -8.8 [-13.2, -4.7]. Keep v3 there, or use the hybrid.
- **The blend's opener term hurts.** Its "usual session starter" term carries the wrong sign: tuned on the oldest window, flipping it adds +4.5 [+0.8, +7.9]. Adding `rot_share_2d` (what you played in the last two days) adds +8.3 [+4.5, +12.5], which brings a blend opener to about v3's level.

**(c) Cold songs never open, at most one in positions 2-7: YES, as a free guardrail. It is not a hit-rate lever.**
- **Hit rate: 0.0 change** (owner, next and start), because the blend almost never puts a cold song in the top 10.
- **Skips** (owner, after the first 20% of history, n=5,015 plays):

  | position | cold skip rate | familiar skip rate |
  |---|---|---|
  | opener | 25.9% (n=58) | 9.1% (n=802) |
  | 2nd-7th | 17.8% (n=174) | 6.4% (n=2,329) |
  | 8th and later | 10.6% | 14.8% |

- **Effect size.** Cold songs are only 4.6% of positions 1-7. Replacing every one of them with a familiar song saves at most 30 skips, i.e. **0.6 points** of a 10.1% skip rate (about 6% fewer skips).
- **Cost.** 232 of 364 cold plays (64%) currently happen in positions 1-7, so discovery moves later.
- Observational: an older algorithm chose these positions.

**(d) Recalibrate energy/valence and check the mood table: YES for Flow and mood features, NO as a recommendation improvement.** Tested as extra signals added to the blend, with the weight chosen on the oldest window and scored on the two newer ones (owner, next, n=1,295):

| signal | change in HR@10 |
|---|---|
| energy gap to the session | +0.4 [0.0, +0.8] |
| valence gap to the session | no gain |
| mood share at this hour | -0.1 [-0.6, +0.4] |
| same mood as the previous song | -0.8 [-1.5, 0.0] |
| session mood mix | -0.4 [-1.2, +0.4] |
| raw energy / valence | -0.2 / 0.0 |

In the hybrid re-ranker, removing all audio and mood features changes next-song HR@10 by only -0.7 [-1.8, +0.4] (openers +1.2 [-0.8, +3.3]); they carry 5.6-7.6% of its gain. The earlier report's control (energy/valence given to the wrong songs: 18.6% vs 18.6%) points the same way.
The recalibration figures from the earlier report stand [sourced]: ridge on the full embedding, valence r 0.68 → 0.73, danceability 0.62 → 0.72. Do it for mood chips and "Describe a mix", and have the owner correct the 39-song table so the mood labels get their first real validation (only 1 human correction exists today).

## The hybrid ("why not machine learning in some part?")

**Setup [measured]:**
- **Stage 1:** the hand blend picks the top 100 candidates (songs already heard in the session excluded).
- **Stage 2:** a re-ranker trained only on the **60 days before each cutoff**, never on the test month. Training data: 1,017-1,729 query groups × 100 candidates per window, all listeners.
- **Features:** the blend score; all 48 v3 feature columns (recency at 4 scales, rotation share, hour/weekday habit, opener share, days since, skip rate, completion, usual-next 1- and 2-back, co-listen / audio / name similarity to the last song and the session, language and composer coherence, global popularity, energy, valence, energy and tempo step); plus artist repeat, mood (same as last, session mood mix, mood share at this hour), energy/valence gap to the session and to this hour's habit, and month (season).
- **Weather is left out on purpose:** the logged values are constants (Question 2 shows real weather does not help either).
- **Models:** LightGBM LambdaRank (early stopping on the last 15% of training groups; it stopped at 20-39 rounds, so the data is small), the same without audio/mood features, and logistic regression.
- **Guardrails:** cold rule and artist spacing are applied after re-ranking. The repeat penalty is built in: songs heard in the session are excluded.

| owner | blend | v3 | hybrid LGBM | hybrid LGBM, no audio/mood | hybrid logistic | hybrid LGBM + guardrails |
|---|---|---|---|---|---|---|
| next, HR@10 (n=2,370) | 27.4 | 15.8 | **31.1 [28.0, 34.6]** | 30.5 | 30.0 | 30.9 |
| start, HR@10 (n=491) | 19.8 | 28.5 | 28.3 | **29.5** | 27.5 | 28.3 |
| stage-1 recall@100 | | | next 71.4%, start 68.4% | | | |

Paired deltas, owner next:

| comparison | HR@10 change |
|---|---|
| hybrid minus blend | **+3.7 [+2.2, +5.2]** |
| hybrid + guardrails minus blend + guardrails | +3.5 [+1.9, +5.1] |
| hybrid minus v3 | +15.3 [+12.8, +17.9] |
| LGBM minus logistic | +1.1 [0.0, +2.3] |
| with minus without audio/mood | +0.7 [-0.4, +1.8] |

The guardrails cost -0.2 pts.

Others (n=461 next / 217 start):

| comparison | HR@10 change |
|---|---|
| next, hybrid minus blend | +0.9 [-1.4, +3.2] |
| start, hybrid minus blend | -3.7 [-7.8, 0.0] |

Stage-1 recall@100 is only 48% for them, because their next song is often one they never played.

Features by LightGBM gain (all three windows agree on the top):

| feature | share of total gain (3 windows) |
|---|---|
| **blend score** | 26-35% |
| usual-next-song (`p_next`) | 15-19% |
| 2-back next-song (`p_next2`) | 4-6% |
| co-listen similarity to the session | 4-6% |
| 2-day / 7-day rotation share and rank | next tier, ~2-5% each |
| hour habit (`hour_affinity`, `co_hour_taste`) | next tier |
| total plays, days since last play | next tier |
| energy gap to the session (first audio feature) | 0.5-1.9% |

**Can the re-ranker be trained on today's logs? Yes.** Retraining on cleaned vs raw logs changes the owner's numbers by less than 1 point (see 1a), and the hybrid already beats the blend with a confidence interval clear of zero. Two limits:
1. It imitates what was played, and what was played was chosen by older algorithms (selection bias). Only `served_by` + holdout logging (1a) can show whether it wins *live*.
2. The training set is about 1,000-1,700 groups per window, so keep it small (the early stop at 20-39 rounds already does this) and retrain nightly as v3 does.

**Ship the hybrid in `shadow` first? YES**, for the owner's next song. Log its top 16 next to the served order. Promote it after 1a's holdout has at least 40 queues (the server's own bar, `ai_order_eval`) showing fewer skips than the blend. For light listeners it shows no gain, so serve them the blend (plus the cold-start work in item 7). Leave audio/mood features out of the first version: they add no measurable lift and are the noisiest inputs.

## Question 2: what the model can learn from data we already have

Lift over the hand blend on held-out windows. The weight is picked on the oldest window and scored on the two newer ones [measured]. Owner, next song, n=1,295 unless noted.

| rank | signal (data already held) | lift HR@10 [95% CI] | verdict |
|---|---|---|---|
| 1 | **Short-term rotation at the opener** (`rot_share_2d`, `rot_share_7d`, `cnt_2d`: plays in the last 2-7 days), openers n=265 | **+8.3 [+4.5, +12.5]**, +6.4 [+3.0, +10.2], +6.0 [+2.3, +9.8] | build (opener) |
| 2 | **Trained combination of all of them** (the hybrid) | +3.7 [+2.2, +5.2] | build, shadow |
| 3 | Rotation share, next song | +1.1 [+0.1, +2.1] | include via hybrid |
| 4 | Co-listen hour taste (negative weight: avoid the "usual at this hour" cluster mid-session) | +0.9 [+0.1, +1.7]; openers +2.6 [+0.4, +4.9] | via hybrid |
| 5 | Name/film similarity to the session (`tx_session`) | +0.8 [-0.1, +1.7] | weak |
| 6 | Composer coherence | +0.4; others +3.0 [-0.2, +8.0] (n=396) | weak; maybe for light listeners |
| 7 | Energy gap to the session | +0.4 [0.0, +0.8] | negligible |
| 8 | Language at this hour / in the session | +0.2 [0.0, +0.5] | negligible (owner is 88-96% Tamil) |
| — | Skip rate, completion, days since, global popularity, valence, mood (any form), same artist/film, weekday | -0.8 to +0.1, all CIs cover 0 or are negative | do not add |
| — | Weekday/weekend (`daytype_share`) | owner -0.1; others **-2.0 [-4.2, -0.2]** | drop |
| — | **Apple Music + legacy history (`apple_plays`, `legacy_plays`)** | Retrain without it. Owner: v3 -1.6 [-3.2, -0.1], blend +1.0 [+0.1, +1.9]. **Others: v3 -6.3 [-10.2, -3.1]** (the owner's history feeds global popularity) | keep for v3 and the global prior; it does not help the owner's own next-song blend |
| — | **Real weather** (Apple history has backfilled WMO codes, 12.8% rainy plays, temperature sd 4.3 °C; 8,053 plays, test = last 40%, 3,222 plays over 125 days) | rain -0.2 [-0.6, +0.2], temperature +0.0 [-0.4, +0.5], both -0.0 [-0.4, +0.5] | **no signal even when real** |
| — | Season (month), same Apple data | +0.5 [+0.1, +0.9] | tiny; one year of data |

From the earlier report, still valid [sourced]:
- **Skip timing:** a <5 s skip means "not now" (61.5% kept next time), not dislike.
- **Rediscovery:** songs untouched for 60+ days are kept only 64.9% of the time. Use them as a low-weight slot.
- **Hour habit:** helps skip prediction (AUC +0.023).
- **Sessions:** median 3 songs, 31% single-song.

Not evaluable from what exists:
- **`impressions`:** it holds running totals per title with no per-show timestamp (509 rows), so it cannot be split by time without leakage.
- **Device:** never logged (`volume` is 1.0 or empty in every row).
- **Queue edits and play source:** never logged.

## Question 3: data to start collecting

Cheapest first.

| data | cheapest way | what it unlocks | privacy cost [estimated] |
|---|---|---|---|
| `served_by`, slot, score per queued song + a 10% holdout queue | server: write one row per `/next` response to a new table; the app already sends `session_id` | the only way to compare any two rankers (hybrid vs blend, AI order) on the same listener; promotion decisions | none new (server-internal) |
| real `seconds_played` (and stop the burst rows) | app: send `positionAtSwitch` seconds, log only the song that was actually playing | correct skip labels; the 13.0% → 8.3% owner skip-rate error goes away | none |
| play source (shuffle slot / autoplay / album / playlist / search / Flow) | app: one enum on `FeedbackRequest`; `_nextSourceContext` already exists in `player_provider.dart` | separate "chosen" from "served" plays; less selection bias in training | low |
| queue edits (remove, move up, play next, skip-to) | app: one event per edit | the strongest explicit negative/positive signal available, and labels for discovery | low |
| search query → chosen result rank | app | intent signal; what users want that shuffle does not offer | medium (queries are personal; hash or keep server-side only) |
| device class (phone / desktop / TV / car) + output (speaker / headphones / BT car) | app: platform + audio route | context the logs lack entirely; untested | low-medium |
| server-side weather at play time | server: stamp the cached Open-Meteo value on the row | **low priority**: real weather shows no ranking signal in 8,053 plays | low (one fixed city); high if per-user location is added, so do not add GPS |
| owner mood corrections (39-song table, then the mood editor) | owner, ~15 minutes | first real accuracy figure for moods; Flow quality | none |
| exposure for new songs (shown, played, skipped, per day) | server: part of `served_by` | discovery for light listeners: 45.6% of their plays are songs new to them | none |

## Question 4: `AI_ORDER`

**Recommendation: `memory`. Not `on`, and `shadow` only if you still want AI evidence.**

Measured on the copy of `ai_order_log.jsonl`: 168 queues, 67 of them in `on` since 2026-11-05.

- **The deciding number: in shadow mode, AI ordering was not better than the free memory order.** Pairwise "kept before skipped" accuracy, AI minus memory: **-0.12 [-0.29, +0.03]**, 9 usable queues. In shadow mode v3 order is served, so neither AI nor memory benefits from position bias.
  - Over all 15 usable queues: AI minus memory -0.02 [-0.14, +0.10]; memory minus v3 +0.12 [-0.03, +0.28].
  - In `on` mode AI looks better (+0.14 vs memory), but there the AI order *is* the play order, so that comparison is biased toward AI and cannot be used.
- **Reliability:** 21 of 67 `on` calls (31%) fell back to memory.
- **Latency:** successful calls p50 717 ms, p90 899 ms, max 4.7 s, all on the request path.
- **Live outcome, owner:** skips per queue 20.4% [8.7, 34.2] in `on` (28 queues with plays) vs 14.2% [1.0, 31.9] in shadow (16 queues). No sign of benefit; the point estimate is worse.
- **Sample size:** 15 usable queues against the evaluator's own bar of 40. In `on` mode the nightly evaluator still reads only `shadow` rows [sourced, earlier report], so the evidence never accumulates.

`memory` keeps the one measurable gain (artist spacing guardrail), costs nothing, and removes 0.7 s from every queue build. Switching is a server change the owner makes: set `AI_ORDER=memory` in `/opt/shuffle-server/.env` and restart `navivibe.service`.

## What I could not verify

- **No live test of anything.** All numbers are offline imitation of past plays, which older algorithms chose (selection bias). Discovery of songs never played is barely measured.
- **Other listeners are mostly one person.** 392 of 678 other-listener samples are u10; no other listener has more than 87. Every "others" figure has wide intervals and should not be generalised.
- **v3 was retrained locally** from copied code and data with the server's settings (LightGBM 4.7.0 here; the server's version not checked). It reproduces the server's protocol, but the production model trained on 2026-11-22 was not loaded.
- **Legacy model only ranks within its 50-song sampled queue,** so its HR@10 understates it; HR@50 (17.3%) is the fairer figure. `navidrome.db` was not copied, so its star/playlist inputs were skipped.
- **The hybrid is untuned:** one blend for stage 1, fixed LightGBM parameters, 100 candidates. Better settings may do more. The mood labels it uses are raw `mood_tags.json` + admin labels without the moods-v2 evidence rules.
- **Weather was tested only on the Apple history:** backfilled values, title-level, no sessions, no skips recorded (every Apple row has ratio ≥ 0.3). It shows there is no song-choice signal; it does not test skips.
- **The AI-order verdict rests on 15 queues.** The decision is driven by reliability and cost, with no evidence of benefit, not by a proven loss.
- **The cold-song rule is observational,** and familiarity is keyed by title (the three id generations break ids).
- **Not attempted:** session-length prediction, device effects, queue-edit signals (none logged).

## Top 3 findings

1. **For "what plays next", the simple blend beats the server's learned v3 by 11.7 points** (27.4% vs 15.7% HR@10, n=2,370). A **hybrid** (blend picks 100, small LightGBM re-ranks) adds another **+3.7** (31.1%). The ML helps as a re-ranker on top of the blend, not as a replacement for it. Ship the blend now and the hybrid in shadow.
2. **Mood, energy, valence and weather are not what holds recommendations back.** Every such signal moves HR@10 by less than 1 point, even real weather from 8,053 Apple plays. The levers are short-term rotation (+8.3 at openers), usual-next-song, and the hour habit. Fix moods for Flow, not for the shuffle.
3. **The logs, not the models, block progress.** No log says which algorithm served a song, so nothing can be compared live. Burst rows are still being written (59 in October). **`AI_ORDER=memory`**: AI never beat the free memory order where the comparison is fair (-0.12 [-0.29, +0.03]), and 31% of its calls fail.
