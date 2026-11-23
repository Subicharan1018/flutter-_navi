# Making Flow better: diagnosis, measurements, flow-v2

Written 23 Nov 2026 from read-only copies of the live data. Server package: `tool/server/flow-v2/` (not installed by this work). Harness behind every number: `tool/server/flow-v2/eval/`.

## In one page

* The owner said only "Flow needs to be better". Flow today is **a blend of three piles with a mood filter**, not an arc: nothing in it looks at how songs sound next to each other, and the mood chip is a yes/no label filter that uses the catalog's *guessed* energy.
* Measured on replayed queues (4 listeners x 9 chip settings x 6 seeds = 216 queues of 42 songs, 9,065 songs): neighbouring songs jump about as far as in a random shuffle (energy 0.22 per step with no chip, random 0.22); the same artist plays back to back in 7.6 % of steps (random 0.8 %) and the same composer in 13.8 % (random 1.1 %); 18 % of the songs on a mood chip disagree with Spotify's real numbers (calm 37 %, sad 32 %); 71 % of a queue's songs are ones the listener never played.
* **flow-v2** fixes the first three with one new module and 13 exact-text edits in `flow.py`, behind `FLOW_V2=off|shadow|on` (default off): energy jump per step 0.166 to 0.111 (-33 %), same artist back to back 7.6 % to 0.09 %, same composer 13.8 % to 0.05 %, chip agreement 81.7 % to 86.3 % (partly circular, see below). Shadow serves the old queue song for song (216 of 216 identical).
* **Not improved, and not claimed:** skips. The predicted skip risk of a v2 queue is the same as the old one (admin 0.2097 vs 0.2096). In the owner's own 6,266 plays, bigger jumps between songs do not predict skips; what predicts them is how often the song was played before. Flow's own recorded plays are too few (272 songs served in the last 7 days, 3 listeners) to say whether Flow skips more or less than before.
* What only a live trial can show: whether people skip less, finish more, or simply prefer it. Shadow logging is in place so the owner can start collecting with no change of behaviour.

## 1. How Flow works today (live `flow.py` with flow-v1, `flow_prefs.py`)

* **Request**: the app asks `POST /flow/next` for 10 songs, then 8 more whenever 3 or fewer are left up next. It sends the mood chip, every song id Flow already queued (`seen`, oldest first, at most 500), the session id, and what the listener did with the songs (like/skip/play, at most 80, this run only).
* **Three piles** per batch: familiar (songs the listener plays, not skipped on 60 % of weight, not heard in the last 6 hours), fresh (never played, ranked by the Discover score), explore (at most one new-language song). Default 50 / 40 / 10; skips of fresh songs move the mix toward familiar and likes toward fresh, fresh stays between 30 and 70 %.
* **Blocks** (flow-v1): the last 50 to 150 distinct plays, anything served in any session in the last 5 days (relaxed when the familiar pool is small), this session's songs, the "never recommend" list, the listener's "not this mood" marks.
* **Mood chip**: a hard filter. First label equals the chip, or the second label under a table (e.g. `calm` after `romantic` with energy under 0.6), minus songs whose catalog energy plainly contradicts it (energetic under 0.5, calm over 0.75). `gym` is decided by energy >= 0.7 and tempo >= 115 (or labelled energetic/angry with energy >= 0.6). Within the chip nothing ranks songs by how well they fit.
* **Scoring** inside a pile: familiar = plays blended with time since last play; fresh = Discover; both plus likes' closeness, minus skips' closeness, a composer nudge and Gumbel noise. At most `ceil(count/3)` per composer.
* **Order**: `_spaced` interleaves the piles evenly and opens on a familiar song. **Nothing else**: no energy, tempo, key or valence anywhere in ordering, no arc, and each refill is built without knowing the song at the end of the queue.
* **Ending**: Flow never ends; it stops when no eligible song is left ("No more calm songs for Flow right now") or after four failed refills.
* **In the app**: `lib/features/flow/` (a Home section with chips, a pill, a settings sheet). The app shows the blend and nothing about why a song was chosen; the server's `why` text exists per song.

## 2. What the data can and cannot say

| | |
|---|---|
| Library | 2,487 songs. Real Spotify numbers for 2,109 (84.8 %): 1,781 in `spotify_details.db` plus 328 more marked `spotify` in the catalog. 377 have calibrated guesses, 1 has nothing. The catalog's own energy/valence for the 1,656 songs that have both is the guess, and it differs from the real number by more than 0.2 for 166 of them (10 %). |
| Mood labels | 2,471 of 2,487 have an effective label (admin labels > labeller minus ruled out). Only 10 admin labels. The labeller's confidence exists for 63 songs, so it cannot drive ranking; it already feeds the effective labels. 185 songs are in no chip at all (7.4 %): they can only be played by an unfiltered Flow. |
| Listening logs | 19 listener databases have plays; 4 have 150 or more (admin 6,266 live plays plus 7,927 Apple/legacy, sandeep 838, vijay 754, Roopika K 165). Plays of the other listeners are 1 to 57 each. |
| Flow plays | **Not marked.** `play_events.play_source` has no `flow` value (the enum is smart_shuffle, autoplay, album, playlist, search, jam, remote, queue, radio, library, download, other), and the Flow queue's name is not in the event. The only trace of what Flow served is `explore/state.db` `flow_seen`, which is **deleted after 7 days**: 272 rows, 3 listeners, 16 sessions at the time of the copy. |

Joining `flow_seen` to the listener's plays (same song, played within 6 hours after it was served):

| listener | served | played | skipped (<30 %) | completed (>=80 %) | the same listener's other plays in that window |
|---|---|---|---|---|---|
| sandeep (7 sessions) | 134 | 72 | 17 (24 %, CI 15-35 %) | 53 | 102 plays, 13 skipped (13 %, CI 8-21 %); Fisher p = 0.07 |
| admin (the owner; 6 sessions) | 84 | 13 | 13 (100 %) | 0 | 149 plays, 22 skipped (15 %) |
| vijay (3 sessions) | 54 | 7 | 6 | 0 | none |

The owner's and vijay's Flow sessions look like trying the feature (a few seconds per song, 20 plays in 9 sessions), not listening. Only sandeep's 72 plays look like real use; his Flow plays skip about twice as often as his other plays, but p = 0.07 on 72 plays is a hint, not a result. Pooled, 36 of 92 Flow plays were skipped against 35 of 251 others; that is dominated by the two test-like listeners and should not be read as "Flow skips more".

**Extra logging Flow needs** (not done here, app change): (1) a `flow` value for `play_source` (server `play-events-v2` accepts only the list above and repairs unknown values with a flag); (2) the song at the end of the queue sent with each request (see "limits" below); (3) keep `flow_seen` longer, or rely on `flow_v2/shadow.jsonl`, which flow-v2 appends one line per batch and never purges (it records who, when, which songs, in which order).

## 3. Weaknesses, ranked by how many Flow songs they touch

Replay: the live `flow.py` (with flow-v1) run per listener x chip (none, sad, romantic, happy, energetic, calm, devotional, angry, gym) x 6 seeds; each queue is one 10-song and four 8-song batches with the app's `seen`, no feedback. The engine is a stand-in built from the catalog's own effnet vectors (32 dimensions) and no word vectors, so absolute picks differ from the server's; old and new run on the same stand-in.

| # | weakness | measured | touches |
|---|---|---|---|
| 1 | No sound-aware ordering | mean energy step 0.166 (0.219 with no chip; a random queue: 0.218), valence 0.227, tempo gap 0.252, key distance 2.94 of 6 (random 2.95); each refill ignores the song before it (seam step 0.158 vs 0.167 inside batches) | every step of every queue |
| 2 | Mostly songs the listener never played | familiar share 29 % of songs (blend target 50 %): 45 % admin, 38 % sandeep, 34 % vijay, 0 % Roopika K; by chip 7 % devotional, 20 % angry, 27 % calm, about 30-38 % others. The owner skips never-played songs 27.9 % of the time (n=581) against 15.6 % for songs played 3+ times (n=4,805). | 71 % of songs (by design: fresh is Flow's purpose; not changed) |
| 3 | Chip songs that do not sound like the chip | 81.7 % agree with Spotify's real numbers (6,727 judged songs): calm 62.9 %, sad 68.4 %, gym 75.8 %, romantic 80.4 %, angry 82.1 %, happy 86.6 %, energetic 98.3 %, devotional 100 % | 18 % of chip songs (89 % of the replayed queues use a chip; in the app a chip is optional) |
| 4 | Same artist / composer back to back | artist 7.6 % of steps (random queue 0.8 %), composer 13.8 % (1.1 %); with no chip 8.1 % and 21.4 % | 1 in 13 steps and 1 in 7 |
| 5 | Silent fallbacks | an unreadable Flow state file turns off the cooldown and per-session memory with no log line; an unreadable cooldown returns "nothing rests" with no log line | none seen in the copies; invisible if it happens |
| 6 | Flow outcomes cannot be measured beyond 7 days | `flow_seen` purge, no `play_source=flow` | all analysis |
| 7 | Short songs under 2 minutes | 10.9 % of songs (19 % with no chip) against 11.8 % of the library | **not a weakness**: the owner skips short songs less (11.4 % vs 19.1 %, n=1,144), so no short-song rule was added |
| 8 | Other languages, instrumentals, very long songs | off-language 4.7 % (about the exploration share), instrumental 1.9 % (library 6.4 %), over 7 minutes 1.4 % | negligible |

Coverage: no song is unreachable in an unfiltered Flow. Chip sizes (songs that can play): happy 944, energetic 874, gym 700, sad 668, romantic 411, angry 265, calm 191, devotional 77. Calm and devotional are small enough that a few sessions exhaust them.

## 4. What changed (flow-v2)

All of it is `navivibe/flow_v2.py` plus exact-text hooks in `flow.py`; `FLOW_V2` unset or `off` gives the old answer song for song (a test compares with answers recorded from the unpatched file).

1. **Real numbers.** Spotify's energy, valence, tempo, key and mode replace the guesses where they exist; every other song keeps its guess and is marked `predicted` in the per-song `flow` block.
2. **Chip fit.** For each chip the library's own labelled songs with real numbers give a profile (mean and spread of energy and valence; gym: the songs `gym_fit` accepts). Songs whose real numbers are over 2.5 spreads away are dropped; the rest are scored by closeness (weight 0.7 on a z-score). If that would leave fewer than three batches of songs the rule relaxes and the answer says so.
3. **Artist cap and spacing.** No artist fills more than a quarter of a batch (two of eight); when sequencing, the same artist next to itself costs 3.0, within two songs 1.0, same film 1.0, same composer 0.7.
4. **Sequencing.** Each batch is ordered by a beam search (48 partial orders) minimising the cost of each step: energy 1.0, valence 0.6, tempo (half and double time folded) 0.5, key distance on the circle of fifths 0.3, sound-of-the-track distance 0.4; the first step is from the song at the end of the queue (`seen[-1]`); a never-played song early in the batch costs 0.6 (3x as the opener), which pushes new songs later.
5. **Skip history.** A familiar song whose weighted share of skips is high is scored down by that share.
6. **Why.** Every song carries `flow: {step, energy, valence, bpm, sound, fit}`; the answer carries `flow_v2: {mode, chip_profile, relaxed, error?}`.
7. **Two silent fallbacks now log the reason.**
8. **Shadow.** `FLOW_V2=shadow` serves the old queue and appends `{old, new, cost_old, cost_new, ...}` per batch.

Weights were set by hand and adjusted twice after looking at this same replay (artist 1.5 to 3.0, cold-song cost 0.35 to 0.6); nothing was held out, so treat the exact figures as slightly optimistic.

**Tried and left out.** An energy arc (warm-up for energetic/gym/angry, wind-down for calm/sad/romantic/devotional) moved the late-minus-early mean energy by +0.017 and -0.042 against -0.027 and -0.006 for the old queues: inside the noise, because a chip's songs sit in a narrow energy band. Removed. Confidence-weighted labels (63 songs have a confidence). A short-song rule (data says it is not a problem).

## 5. Before and after (216 queues each, 9,065 and 9,048 songs, same seeds)

| measure | old | v2 | change |
|---|---|---|---|
| mean energy step | 0.166 | 0.111 | -33 % |
| mean valence step | 0.227 | 0.156 | -31 % |
| mean tempo gap (octaves, folded) | 0.252 | 0.195 | -23 % |
| mean key distance (0-6) | 2.94 | 2.24 | -24 % |
| sound-of-track similarity of neighbours (cosine) | 0.204 | 0.260 | +0.056 |
| energy step at the batch seams | 0.158 | 0.124 | -22 % |
| same artist back to back | 7.55 % | 0.09 % | |
| same composer back to back | 13.81 % | 0.05 % | |
| same film back to back | 1.04 % | 0 % | |
| chip songs agreeing with real numbers | 81.7 % | 86.3 % | +4.6 points (circularity below) |
| of which sad / calm / romantic / happy / angry / gym | 68.4 / 62.9 / 80.4 / 86.6 / 82.1 / 75.8 | 73.1 / 63.4 / 90.6 / 96.2 / 88.1 / 80.7 | calm barely moves |
| songs under 2 minutes | 10.9 % | 7.7 % | a side effect of the chip fit |
| never-played songs (fresh + explore) | 70.8 % | 70.8 % | unchanged on purpose |
| cold songs' mean place in a batch (0 first, 1 last) | 0.536 | 0.571 | small |
| queues that start on a familiar song | 60.6 % of batches | 59.0 % | not improved |
| distinct songs over all 216 queues | 884 | 829 | v2 repeats itself a bit more |
| overlap of two runs of the same listener and chip | 69.4 % | 72.2 % | |
| queues shorter than 42 | 7 | 18 | 1 or 2 songs short in thin pools (sandeep gym/energetic, vijay devotional) |
| mean cost of a batch in shadow (v2 order of the same songs vs the old order) | 17.99 | 11.13 | -38 % |

**Predicted skip risk.** A logistic model on song-level features only (log plays before, skip rate before, log days since last play, language share, short) fitted per listener on 70 % of their plays and tested on the last 30 %: admin AUC 0.82 (6,266 plays), vijay 0.80 (754), sandeep 0.54 (838, no skill). Mean predicted skip risk of the queues: admin 0.2097 old vs 0.2096 v2, vijay 0.3505 vs 0.3613, sandeep 0.5086 vs 0.5070. **No change.** Transition features were left out of this model on purpose: with them in, the energy/valence/tempo jump coefficients are negative (a bigger jump, slightly fewer skips) and the owner's smallest-jump quartile has the highest skip rate (27.8 % against 16 %), which looks like skip bursts landing on near-identical songs rather than a real effect. In short: the data does not show that smooth queues skip less, so v2 does not claim it.

**Circularity of the chip numbers.** The agreement check uses plain rules on real numbers (energetic: energy >= 0.55; calm: <= 0.55; happy: valence >= 0.40; sad: <= 0.55; romantic: energy <= 0.80 and valence 0.15-0.85; angry: energy >= 0.55 and valence <= 0.65; gym: energy >= 0.60 and tempo >= 100; devotional: always true), and v2 ranks by distance from each chip's own profile, so the two are correlated. Independent of the rules: the average real energy and valence of a sad queue fell from 0.56 / 0.47 to 0.53 / 0.44 and happy's valence rose 0.66 to 0.69. Calm barely moves (62.9 % to 63.4 %): the library's songs labelled calm average a real energy of 0.53, so many "calm" labels are not quiet songs. That is a labelling problem for the mood editor, not something ranking can fix. The 54-song reference set cannot judge queues (8 songs per mood).

## 6. Limits and what is not measured

* **Skip, completion and liking are not measured for v2.** Only a live trial can; sandeep is the only listener with enough real Flow use to learn from, and the other two have used it as a test.
* Replay uses a stand-in engine (no word vectors, 32-dimension sound vectors), no feedback loop, and a frozen clock.
* The seam uses the last id the app sent in `seen`. After a mood change the app removes the queued songs but keeps them in `seen`, so the "song at the end of the queue" is then a removed one: the first step after a chip change is not smoothed. Fix needs the app to send the song actually at the end (not done: no `lib/` change was needed for anything else).
* Songs without Spotify numbers (377) are placed by the guess; the chip drop rule never drops a predicted-only song.
* In thin pools (calm, devotional, a listener who plays little) a batch can be one or two songs short; the app asks again on the next refill.
* Parameters were tuned on the replay itself (section 4).
* Local runs of the old Flow tests on Windows leave `C:\proc\definitely\not\writable\state.db` behind (`test_a_missing_state_file_does_not_break_flow` treats `/proc/...` as unwritable, which is true on Linux only); it does not affect the server.

## 7. A live trial

1. Install (see the README), then `FLOW_V2=shadow` for a week or two. Nothing changes for listeners; `flow_v2/shadow.jsonl` records every batch, the order v2 would use and how much smoother it is (`cost_old` vs `cost_new`; the replay says about 0.62).
2. Switch to `FLOW_V2=on` for a stretch and compare, per listener, skip and completion of Flow plays before and after. Flow plays are found by joining the log's `served` songs to the listener's plays (same song, within a few hours), because the plays themselves are not marked. To compare at the same time, a per-session switch (odd session id: v2) is a small addition if wanted.
3. Add `play_source=flow` and the real queue-end song in the app so later analysis stops depending on a join.

## 8. Reproduce

`tool/server/flow-v2/eval/README.md` lists the commands (read-only copies of the databases, a patched copy of the server tree, then `replay.py`, `final.py`, `risk.py`, `coverage.py`, `familiarity.py`, `skipmodel.py`). Unit tests for the package: `tool/server/flow-v2/tests/test_flow_v2.py` (18 tests; `install.sh --check` runs them with `FLOW_V2` off, shadow and on).
