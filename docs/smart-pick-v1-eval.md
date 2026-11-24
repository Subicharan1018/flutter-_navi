# smart-pick-v1: offline before/after (2026-11-24)

Reproduce: `python tool/shuffle_eval/smart_pick_eval.py --snapshot DIR [--filler weighted]` on a read-only copy (same snapshot as `tool/shuffle_eval/bakeoff`). v3 trained on everything before the last 30 days, 113 owner sessions replayed, 3 pool seeds each, a synthetic 196-song pool (the session's songs + filler; 25% never played). OLD = random seed + random 16 sent, v3 samples; NEW = smart-pick-v1. Not simulated: the memory re-order and artist spacing (same for both). Results depend on the pool: the real playlist's make-up is unknown.

| first batch of 17 | uniform filler (pool 73% cold) OLD / NEW | play-weighted filler (pool 60% cold) OLD / NEW |
|---|---|---|
| cold in positions 1-7 | 67.0% / 0% | 57.9% / 0% |
| first song cold | 74.4% / 0% | 55.9% / 0% |
| cold in the whole batch | 72.7% / 5.9% | 60.0% / 5.9% |
| cold in positions 2-7 (count) | 3.9 / 0 | 3.5 / 0 |
| expected skip, slots 1-7 (owner's native familiar/cold rates 10.9% / 25.1%) | 20.4% / 10.9% | 19.6% / 14.4%* |
| expected skip, first song | 22.7% / 10.4% | 19.5% / 14.4%* |

*second run used rates from the script's own history (familiar 14.4%, cold 23.5%).

Real held-out first songs (n=121): skipped 15.7% overall; familiar 9.6% (n=83), cold 28.9% (n=38).

HR@10 of the song really played, inside the pool (590 kept plays; start n=112, next n=478):

| | OLD random 16 | whole pool, v3 plain | whole pool + familiar-first |
|---|---|---|---|
| uniform filler | 0.081 | 0.361 | 0.346 |
| weighted filler | 0.079 | 0.417 | 0.339 |

Familiar-first costs 1.5 points (uniform) to 7.8 points (weighted) of in-pool HR@10 against plain v3 on the whole pool, because 33% of the songs the owner really played next were cold by this definition. It is the owner's rule, bought with that hit rate; both are far above a random 16.

Server time (local copy, v3 + memory order, 600 candidates): ~510-540 ms per request against ~460 ms for the old 16-song request. Payload for 196 songs: titles 4.8 KB, ids 5.2 KB, playlist id 117 B (+17 queued ids: 576 B).
