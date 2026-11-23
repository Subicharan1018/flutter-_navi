# Hybrid ranker: reusable code and held-out evaluation

Read-only, offline. Nothing here connects to the server. Spec for the live build: `docs/hybrid-shadow-spec.md`. Results: `docs/smart-shuffle-bakeoff.md`.

| file | what it is |
|---|---|
| `hybrid.py` | the reusable part: blend weights, top-100 candidates, feature matrix, LightGBM parameters, training and scoring. Imports `navivibe.recsys` only; no I/O |
| `evaluate.py` | trains v3 and the hybrid on everything before a cutoff, then ranks each kept play of the next 30 days |
| `report.py` | HR@10 with session-cluster bootstrap intervals, paired differences, plays needed to see +3 points |

This is the cleaned-up core of the bake-off (v3, blend, hybrid, router). The discovery generators, legacy model and Spotify cross-check were one-off code and are not included.

## Rerun on a copied snapshot

Needs Python 3.10+, numpy, scipy, lightgbm, rapidfuzz. About 4 minutes per window with two threads.

1. Copy into one folder outside the repo (it holds listening history, so never commit it): `navivibe/` (server code), `catalog.db`, `logs/*_listening_log.db`, and optionally `mood_tags.json` and `mood_admin.json`. Copy; never open the live databases read-write.
2. Run one window at a time:

   ```
   python evaluate.py --snapshot DIR --end-days-ago 0 --audio-mood --out DIR/w0.jsonl
   ```

   Repeat with 30 and 60.
3. `python report.py DIR/w0.jsonl DIR/w30.jsonl DIR/w60.jsonl`

## What to expect

On the 2026-11-23 snapshot (owner next song, n=2,370): v3 14.9, blend 27.4, hybrid without audio/mood 29.9, with 30.6. The bake-off document says v3 15.6, blend 27.4, hybrid 30.6 / 30.4.

- The blend matches on every play.
- The learned models differ because this version fills the one song with no energy value on a copy (the bake-off changed v3's input too) and breaks candidate ties in a stable order.
- A seeded rerun on the same machine gave the same rank on every play. Without `np.random.seed`, `embeddings.names()` uses a random SVD start, and v3 moves by up to about 0.7 points.

## Blend (stage 1)

`z` = z-score over the whole catalog. Inputs are v3's own feature columns (`cnt_*` are log1p of decayed counts).

- next: `z(cnt_7d) + z(hour_affinity * cnt_180d) + 1.5 z(p_next + 0.4 p_next2) + 0.5 z(p_from_session)`
- opener: `z(cnt_7d) + z(hour_affinity * cnt_180d) + z(starter_share)`. Only used for training groups; v3 serves openers.

Candidates are the 100 highest allowed songs.

## Re-ranker features

The recommended live set is `NO_AUDIO_MOOD_COLS` (45 columns): every v3 feature except the 8 audio ones, plus the 5 non-audio extras marked below. v3's columns keep their live definitions (`navivibe/recsys/features.py`).

| group (v3 columns) | meaning | needs, live |
|---|---|---|
| cnt_2d, cnt_7d, cnt_30d, cnt_180d, plays_total | log of decayed / total kept plays | in-memory user state |
| rot_share_2d, rot_share_7d, rot_rank_7d, in_prev_session | share and rank of recent listening; heard in the previous session | user state |
| hour_affinity, hour_lift, daytype_share, starter_share | share of the song's plays near this hour, its lift, weekday/weekend share, share of this listener's session openings at this time of day | user state + clock |
| days_since, played_today, skip_rate, mean_ratio | recency and satisfaction | user state |
| p_next, n_next, p_next2, p_from_session | chance this follows the last song, its count, the last two, and earlier session songs | user state + session |
| co_last, co_session, co_hour_taste | co-listen embedding similarity | nightly artifact |
| tx_last, tx_session, tx_hour_taste | title / artist / film text similarity | nightly artifact |
| lang_session, lang_hour_share, comp_session, comp_affinity, same_film_last | language, composer, film coherence | catalog + state |
| pop_global, n_users | popularity over all listeners | global state |
| depth, hour_sin, hour_cos, is_weekend, user_log_events, is_unplayed | request context | state + clock |
| energy, valence, d_energy_last, d_bpm_last, au_last, au_session, au_hour_taste, au_last_skipped | audio features (left out of the recommended set) | catalog + audio vectors |

Extras (`EXTRA` in `hybrid.py`):

| extra | meaning | in the live set |
|---|---|---|
| hb | the blend score | yes |
| is_cold | listener has never played it | yes |
| same_artist_last | same artist string as the last kept song | yes |
| msin, mcos | month as a circle | yes |
| same_mood_last, mood_hour, mood_session | same first mood as the last song; share of this hour's plays with that mood; share of the last 5 songs | no (needs `mood_tags.json` + admin labels) |
| energy_hour_gap, valence_hour_gap | distance to the listener's average at this hour | no |
| energy_session_gap, valence_session_gap | distance to the last 5 songs' mean | no |

Nothing in the live set needs data the server does not already hold in memory. Offline only: replaying past logs to make training groups.

## Training

- Groups: every non-skipped play of the **60 days before the cutoff**, all listeners pooled, next songs and openers together, songs already heard in the session excluded. A group is the 100 candidates with the played song labelled 1. **If the played song is not among the 100, drop the group; never force it in** (that bug made the bake-off's learned-discovery row invalid).
- Newest 15% of groups stop the boosting early (patience 40, at least 20 rounds), then refit on all groups.
- 1,016 to 1,729 groups per window; 20 to 71 rounds. The fit takes about 2-3 s; the extra replay pass took about 20-40 s with two threads.
- LightGBM parameters: `LGB_PARAMS` in `hybrid.py` (lambdarank, 15 leaves, deterministic, seed 7).
