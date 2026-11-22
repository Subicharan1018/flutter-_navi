# Smart Shuffle (AI_ORDER=on) evaluation: 2026-11-08

**Verdict: the data cannot show that AI ordering helps. Recommend going back to `shadow` (or `memory`), not `on`.**
Server work was strictly read-only (ssh, `cat`/`sed`/`journalctl`, `sqlite3 -readonly`, a stdin Python script that opens DBs with `mode=ro`).

## What exists on the server
- `navivibe/ai_order.py`: modes off / memory / shadow / on. `on` blocks the request on one Groq call (qwen/qwen3.8-27b, `AI_ORDER_TIMEOUT` 4 s), then runs the artist-spacing and "likely-skip not in first 3" guardrails, and falls back to `memory_order` if the call fails.
- Log: `/DATA/AppData/navivibe/listening_logs/ai_order_log.jsonl` (108 rows: 101 shadow, 7 on). Each row holds v3, memory and AI orders as song ids, plus `ms`.
- Outcomes: per-user `*_listening_log.db`, table `play_events` (`file_path` = song id, `listen_ratio`, `end_reason`, `played_at`). Language, energy and valence come from `catalog.db` `songs`.
- `.env` has `AI_ORDER=on` (file changed 2026-11-05 03:52 UTC, first `on` row 2026-11-05 10:44 IST).

## Metrics
| Metric | Definition |
|---|---|
| Skip rate | share of plays with `listen_ratio` < 0.3 (the same threshold the server's eval uses; `play_events` has no seconds-played column, so "within 30 s" is approximated by ratio) |
| Completion | `listen_ratio` ≥ 0.85 |
| First kept | first played song of the queue has ratio ≥ 0.3 |
| skipped_pos | mean relative position (0..1) of skipped songs when a queue's songs are re-ordered by each candidate order (higher = better); queues with ≥4 played and ≥1 skip |
| Adjacent same artist | count per 16-song queue (catalog `artist`) |
| Language switches | share of adjacent pairs that change language |
| Mood smoothness | mean absolute energy and valence step between neighbours (lower = smoother) |

## Results (script: `docs/smart-shuffle-eval-analysis.py`)
**Sample sizes first.** AI order served to a listener (`on`): 7 queues, of which 3 were really AI-ordered and 4 fell back to memory order. Only 4 of those queues have any plays logged (27 plays, admin only). Shadow: 101 queues, of which 48 have plays (278 plays; admin 30, sandeep 14).

1. **Real-world outcome, on vs not-on.** In the 4 `on` queues with plays, skip rate was 0% and completion 100% (n=27). Admin's shadow-period queues (v3 order served, n=138 plays) were 8% skip / 92% completion. 27 plays from one listener over 3 days cannot separate those; the confidence interval is wide, admin's skip rate swings 0–60% from day to day (daily `play_events` query below), and the fallback queues hold most of the plays. **Inconclusive.**
2. **Counterfactual from shadow logs** (21 queues usable; AI 17 because it failed on some):

   | Order | queues | skipped_pos (higher better) | first song kept |
   |---|---|---|---|
   | v3 | 21 | 0.525 | 71% |
   | memory | 21 | 0.510 | 62% |
   | AI | 17 | 0.492 | 53% |

   Neither alternative moves skipped songs later than v3, and both are worse on first song kept. Differences are within noise at this n, but there is no sign of a benefit. The server's own rule (`GAIN` 0.04 and 40 queues) is not met: 21 of 40 queues.
3. **Structure.** Both memory and AI orders cut adjacent same-artist from about 1.0 to 0.41 per queue (guardrail, not the AI). Language switching is unchanged (6.6% vs 6.7%). Energy/valence smoothness is the same as v3 (energy step 0.159 AI vs 0.159 v3; valence 0.205 vs 0.216). The AI changes about 75% of positions versus v3 and agrees with the memory order's opener only 55% of the time, so it is acting, just not measurably better.
4. **Confounder:** the two users behave very differently (sandeep: 53% skip / 43% completion; admin: 8% / 92%). Any aggregate before/after comparison mostly measures who listened, so I did not use one.

## Failure modes
- `on`: **4 of 7 calls fell back (57%)**; shadow: 11 of 101 got no AI order (11%), 2 of them with `ms`=0. The journal shows `NaviVibe order: AI call skipped (HTTPError)` (13 since 2026-10-15, 4 since 2026-11-05). `llm_client` logs only the exception class, so 429 vs 4xx/5xx cannot be told apart from the logs.
- Latency: successful calls p50 723 ms, p90 924 ms, max 4679 ms (near the 4 s timeout). In `on`, Groq sits on the request path, so each Next/queue build pays about 0.7–0.9 s, up to 4 s in the worst case; failures returned in 0.18–0.8 s.
- Model drift: first rows used llama-3.3-70b-versatile, which Groq retired; now qwen3.8-27b.
- **Evaluation blind spot:** `ai_order_eval.load_log()` keeps only `mode == "shadow"` rows. Since the switch to `on`, the nightly evaluator has no new evidence, and `ai_order_eval_state.json` does not exist, so the ntfy "ready to decide" message was never sent. In `on` mode the log holds no non-AI baseline for the same queue to compare against.

## Recommendation
**Back to `shadow`** (keep logging, serve v3). If the user wants some ordering benefit today, `memory` is a good middle choice: it is free, instant and gets the artist-spacing gain, but it also showed no skip benefit yet.
Concretely:
1. Set `AI_ORDER=shadow` (or `memory`) and restart. That is a server change, which this task did not do; the user or a follow-up session needs to do it.
2. Make `llm_client` log HTTP status and Groq's `retry-after`, so 429s are separable from other errors.
3. Hold an `on` holdout: for ~20% of queues serve v3 and log it, so on-vs-off can be compared on the same listener. Without this, `on` can never be evaluated.
4. Extend `ai_order_eval.load_log()` to include `on` rows, and log what was served.
5. Collect ≥40 usable queues (the evaluator's bar), more than one listener, and record seconds played so "skip within 30 s" is measured rather than approximated.
6. If the AI stays in the picture, lower the timeout to about 1.5 s (successful calls are under 1 s) and cache by queue hash so the user rarely waits on Groq.
7. Since AI vs memory is not distinguishable and the guardrails produce the one measurable gain, consider removing the model call entirely unless a holdout shows it wins.

## Commands run
```bash
ssh -o BatchMode=yes subi@100.99.105.51 'ls /opt/shuffle-server/navivibe; wc -l /opt/shuffle-server/navivibe/*.py'
ssh ... 'grep -n "AI_ORDER" /opt/shuffle-server/.env | sed "s/KEY=.*/KEY=***/"; ls /opt/shuffle-server ...'
ssh ... 'sed -n 1,309p /opt/shuffle-server/navivibe/ai_order.py'; ssh ... 'sed -n 1,188p .../ai_order_eval.py'
ssh ... 'ls -la /DATA/AppData/navivibe/listening_logs; wc -l .../ai_order_log.jsonl; python3 - <<EOF (counts by mode/user/date)'
ssh ... 'sqlite3 -readonly .../admin_listening_log.db ".schema" "select ... from play_events"'
ssh ... 'sqlite3 -readonly /opt/shuffle-server/catalog.db ".schema songs"'
ssh ... 'journalctl -u navivibe --no-pager --since "2026-11-04" | grep -i -E "ai.order|groq|429|llm|timeout|fallback"'
ssh -o BatchMode=yes subi@100.99.105.51 'python3 -I -' < docs/smart-shuffle-eval-analysis.py
```
No server file was edited, no service restarted, no sudo used.
