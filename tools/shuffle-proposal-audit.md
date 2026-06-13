# Shuffle-Engine Proposal — Code-Grounded Audit
> 2026-06-13 · Verdicts checked against `/opt/shuffle-server/navivibe/{model,preprocess,scheduler}.py`
> (not the API docs the original proposal inferred from).

## All 15 proposals vs. actual code

| # | Proposal | Verdict | Evidence |
|---|---|---|---|
| 1 | Katz bigram/unigram blend | ✅ NEW — best win | Hard threshold: bigram only if `total ≥ BIGRAM_MIN_SUPPORT=3` else hard fallback (`_followers_for`, model.py:589). |
| 2 | Listen-ratio gradient | ❌ already done | `_c_score`/`_comp_score` already bucketed (model.py:243-257). "Binary 0.5" premise false. |
| 3 | Pessimistic Thompson `Beta(α,β+10)` | ❌ wrong premise | Prior is fit-seeded `Beta(1+κ·fit,1+κ·(1−fit))`, κ=6 (model.py:561). Not count-based. |
| 4 | Opener confidence + soft pin | ✅ NEW — low risk | Pin is hard (replaces weakest, model.py:500). `share` already computed in preprocess. |
| 5 | Context-specific skip penalty | ❌ already done | `skip_rate=sc/pc` per day-type bucket, floored (model.py:346-353). "Global" premise false. |
| 6 | Skip-gram pairing (window=2) | ✅ NEW | Only direct + bigram built (preprocess.py:355-407). |
| 7 | Feature-weighted Gaussian | ✅ NEW — cheap | `_audio_fit_score` is equal-weight mean over 4 features (model.py:209-222). |
| 8 | No-repeat 48h cooldown | ✅ NEW (for /next) | `get_queue` only dedups within session; recency decay exists only for /predict/always-hear (model.py:68-76). NOTE: `last_played` is day-granular. |
| 9 | Composer streak penalty | ⚠️ partial / marginal | Fixed diversity penalty within `DIVERSITY_WINDOW=3` (model.py:619-646); escalating version is new but small gain. |
| 10 | Arc-constrained DP ordering | ❌ mostly done | Energy arc learned (`build_energy_arc`) AND applied greedily via `−W_ARC×|energy−arc_target|` (model.py:639-650). |
| 11 | Audio-fit gated exploration | ⚠️ partial | Explore already sorted by fit + fit-seeded Beta (model.py:424,561). Hard floor = tiny add. |
| 12 | New-song injection slot | ⚠️ partial | Unheard songs already get the Thompson explore slot (model.py:418-437). |
| 13 | Season-aware opener table | ✅ NEW | Openers keyed by time-arc only (model.py:488-498). |
| 14 | Closing-song detection | ✅ NEW (low value) | Not present. |
| 15 | GMM profile | ❌ don't | Single Gaussian (model.py:200-205); proposal itself says skip <50 plays/context. |

**Also already present (proposal understates the engine):** weekend/weekday day-type buckets, time-decayed pairing weights, impression penalty, tie-break jitter, 4-level fallback.
**Rebuild trigger:** flat `unprocessed ≥ 50` (scheduler.py:52) — so #10A weighted counting is also genuinely new.

## Corrected priority

**Tier 1 (real gap, low effort/risk) — IMPLEMENTED 2026-06-13:**
1. #1 Katz-smoothed bigram blend — replaces the hard support-3 cliff.
2. #8 day-based cross-session replay cooldown (2-day half-life).
3. #4 opener confidence gate + soft-pin.

**Tier 2 (moderate, rebuild-time):** #7 feature-weighted Gaussian · #13 season-aware openers · #6 skip-grams · #10A weighted rebuild trigger.

**Skip:** #2, #3, #5, #10 (done/wrong premise); #9, #11, #12, #14, #15 (partial/marginal/risky).

All Tier-1 changes are env-var gated (see `model.py` constants) so they can be tuned or neutralised without a code revert.
