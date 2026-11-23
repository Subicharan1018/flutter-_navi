# Play-event schema (schema_version 2)

One event shape for everything the app tells the shuffle server about listening. Server side: `tool/server/play-events-v2/`. App side: `lib/features/play_outbox/logic/play_event.dart` and `lib/features/ai_shuffle/data/models/feedback_request.dart`. Endpoint: `POST /feedback`.

The old payload (no `schema_version`) is still accepted and stored as version 1.

## Event types

| `event_type` | When | Stored in |
|--------------|------|-----------|
| `complete` | the song played to its natural end (at least half heard) | `play_events` |
| `skip` | the listener moved on, or a "natural" end that was really a partial listen | `play_events` |
| `replay` | repeat-one looped the song again (one event per finished lap) | `play_events` |
| `start` | the song has been playing for 3 s (survives a crash that loses the finish) | `play_aux_events` |
| `seek` | the listener scrubbed (first 5 per play) | `play_aux_events` |
| `queue_edit` | the listener added, removed, reordered or "played next" a queue entry (not edits made by the app itself: restore, Flow, Jam, synced remote edits) | `play_aux_events` |

`play_events` stays "one row per finished play", so every existing reader (legacy model, v3 loader, stats, Replay) is unaffected. Nothing that is not a finished play is ever written there.

## Fields

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | int | 2 |
| `play_id` | string ≤ 64 | **Required for finish events** (idempotency key). For `start`/`seek` it names the play they belong to. |
| `event_id` | string ≤ 64 | **Required for `start`/`seek`/`queue_edit`** (idempotency key). The outbox row key. |
| `event_type` | enum | see above |
| `title`, `file_path`, `genre_bucket`, `composer`, `duration_s` | | the song; `file_path` is the Navidrome id |
| `listen_ratio` | 0..1 | `seconds_played / duration_s`; a `complete` must be ≥ 0.5 |
| `seconds_played` | float ≥ 0 | seconds really heard: the position moving forward while playing. Scrubs and pauses do not count. Never above `1.1 × duration + 2` |
| `end_reason` | string | legacy: `natural` / `fwdbtn` / `autoskip` |
| `played_at` | epoch ms | **when the play started**, not when it was delivered |
| `tz_offset_min` | int, ±840 | the phone's UTC offset then (IST = 330). The server computes `local_hour` from it; missing = IST |
| `session_id`, `session_depth` | | the shuffle session, if any (empty for album/search plays) |
| `play_source` | enum | `smart_shuffle`, `autoplay`, `album`, `playlist`, `search`, `jam`, `remote`, `queue`, `radio`, `library`, `download`, `other` |
| `slot` | int | zero-based position in the batch the server served |
| `score` | float | the server's final score for it |
| `served_by` | string | the engine: `v3`, `v3+ai`, `v3+memory`, `legacy`; `holdout_random` for a held-out slot |
| `served_id` | string | the `served_id` `/next` returned; joins to `served_batches` / `served_items` |
| `holdout` | bool | true for the ~5 % of slots the app placed without the AI |
| `client_version`, `platform` | string | app version, `android` / `windows` / `web` ... |
| `queue_edit` | `{kind, from_index, to_index}` | `kind`: `add`, `remove`, `reorder`, `play_next` |
| `from_ms`, `to_ms` | int | for `seek` |

**Weather is not a client field.** The server stamps its own reading (or NULL).

## What the server refuses (HTTP 422, counted)

`rejected_counts(reason, n, last_at)` per user database, with the last 2,000 samples in `rejected_events`. Reasons: `not_object`, `bad_schema_version`, `missing_title`, `title_too_long`, `bad_listen_ratio`, `listen_ratio_out_of_range`, `bad_duration`, `bad_seconds_played`, `seconds_gt_duration`, `unknown_event_type`, `missing_play_id`, `missing_event_id`, `bad_play_id`, `bad_event_id`, `missing_ratio`, `complete_with_low_ratio`, `bad_queue_edit`, `bad_seek`.

Repaired and counted as `flag:<name>`, stored with `quality` set: a `played_at` more than 5 min in the future or older than 90 days (`clock_clamped`), a bad `tz_offset_min`, an unknown `play_source`.

Old-app rows that are impossible but kept: `end_reason = natural` with ratio 0 is stored `quality = suspect_burst` and never taught to the model.

The app's outbox deletes a play on any 4xx except 401/408/425/429, so a refused event is not retried.

## Rules the app follows

* **A natural end with nothing heard is not sent.** (The old app wrote "finished naturally at 0 %" for these: 7.6 % of the owner's rows.)
* Start / seek / queue-edit events, and plays outside a shuffle session, are sent **only after `/next` has answered with a `served_id`** (a server that keeps this log). Against an older server only finish events go out, as before.
* The 5 % holdout: in Smart Local refills, about 1 in 20 places after the first is given to a song taken from later in the batch instead of the AI's choice, deterministically per `(session, ordinal)`, and flagged. The next song is never touched. Only when data collection is on.
* Nothing is sent while "Don't count this" is on.

## Server tables added to each `<user>_listening_log.db`

`play_events` gains: `schema_version`, `event_type`, `seconds_played`, `tz_offset_min`, `local_hour`, `play_source`, `slot`, `score`, `served_by`, `served_id`, `holdout`, `client_version`, `platform`, `origin` (`app` / `navidrome_sync` / `import`), `quality` (`NULL` ok, else `suspect_burst`, `synthetic_time`, `clock_clamped`, `ratio_mismatch`, `impossible`), `received_at`.

New tables: `play_aux_events`, `rejected_counts`, `rejected_events`, `served_batches`, `served_items`, `impression_batches`.

## Evaluating against the holdout

```sql
-- how often a held-out song was kept vs the AI's picks, same sessions
SELECT holdout, COUNT(*) plays, AVG(listen_ratio >= 0.5) kept
FROM play_events WHERE play_source = 'smart_shuffle' AND holdout IS NOT NULL AND quality IS NULL
GROUP BY holdout;
```
