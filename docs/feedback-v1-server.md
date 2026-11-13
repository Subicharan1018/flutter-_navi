# `/feedback` v1: what the app now sends, and what the server must do

Status: **server package not built yet.** Reading the live server over SSH was
refused by the permission classifier in the session that wrote this, and the
`/feedback` handler (`navivibe/feedback.py`, `record_play`) is not in this repo.
Nothing here was guessed against code that was not seen.

## What the app sends (already shipped in this branch)

`POST /feedback` keeps every existing field. Two optional fields are added, only
when the play went through the outbox:

| Field | Type | Meaning |
|---|---|---|
| `play_id` | string (UUID) | Unique per play. The same id is also the `play_id` of the app's local `play_events` row. A retried delivery repeats it. |
| `played_at` | int, epoch **milliseconds** | When the play **started** on the device. Present on every outbox delivery, including ones sent immediately. |

An old server ignores both fields (extra JSON keys), so the app works unchanged
against it; a play delivered late is then bucketed by receive time.

The app treats any 2xx as delivered and removes the play. It retries 5xx,
network errors, 401, 408, 425 and 429 with backoff, and **drops** other 4xx as
permanent. So the server must answer **2xx for a repeated `play_id`** (ignore
it quietly), never 409, or the app would drop the play it already delivered.

## What the server change must do

1. Read optional `played_at` (epoch ms). Use it, instead of "now", for the
   listening-log row timestamp and the hour/day bucket (time-of-day features,
   Replay by month). Sanity-clamp: if it is missing, not a number, in the
   future (allow ~5 min of clock skew), or older than 90 days, use "now".
2. Read optional `play_id`. Keep it unique per user (a `play_id` column with a
   unique index in each `<user>_listening_log.db`, added with
   `ALTER TABLE ... ADD COLUMN` guarded by a `PRAGMA table_info` check). A
   repeat is ignored and answered `200`/`204` exactly like a first delivery.
   Rows with no `play_id` (old clients) are never treated as duplicates.
3. Keep the existing limit (`feedback`: 60/min). The app paces itself at about
   50/min when flushing a backlog.

## Package layout to build (`export/feedback-v1/`)

- the patched `feedback.py` (and the route in `server.py` if it parses fields)
- `test_feedback_played_at.py` (pytest): `played_at` sets the timestamp and
  hour bucket; future / ancient / garbage values fall back to now; same
  `play_id` twice stores one row and answers 2xx both times; no `play_id`
  stores every time; old payloads without either field behave as before
- `install.sh`: back up replaced files with a timestamp, run pytest, print
  `sudo systemctl restart navivibe` for the user to run (never run sudo)

## Navidrome

The scrobble leg now sends `time=<start ms>` (Subsonic's `time` parameter), so
Navidrome's history shows the real play time. Nothing to change on that server.
