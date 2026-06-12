# Navivibe API Reference — v4.0.0

Base URL: `https://shuffle.subimusic.me`  
All protected endpoints require authentication. Public endpoints are marked 🔓.

---

## Authentication

Every protected endpoint requires either:

### Option 1 — Bearer JWT (recommended)
Get your token from the Navidrome login, then pass it as a header:
```bash
Authorization: Bearer <your-navidrome-jwt-token>
```

### Option 2 — HTTP Basic Auth
Pass your Navidrome username and password encoded in Base64:
```bash
Authorization: Basic <base64("username:password")>
```

#### Quick curl shortcut (Basic Auth):
```bash
curl -u admin:yourpassword https://shuffle.subimusic.me/next
```

> [!IMPORTANT]
> All data is **isolated per user**. Each Navidrome user gets their own SQLite database and model state. Admin gets the full Apple Music + legacy history. All other users start fresh.

---

## Endpoints

---

### 🔓 GET /health
Service health check. No auth required.

```bash
curl https://shuffle.subimusic.me/health
```

**Response:**
```json
{
  "status": "ok",
  "weather": {
    "code": 800,
    "mood": "clear",
    "temperature_c": 28.1,
    "humidity_pct": 66,
    "fetched_at": "2026-05-29T21:30:00+05:30"
  }
}
```

---

### 🔓 GET /weather
Live Erode weather used by the shuffle engine. No auth required.

```bash
curl https://shuffle.subimusic.me/weather
```

**Response:**
```json
{
  "code": 51,
  "mood": "rainy",
  "temperature_c": 26.6,
  "humidity_pct": 82,
  "fetched_at": "2026-05-29T21:30:00+05:30"
}
```

Weather moods: `clear`, `cloudy`, `rainy`, `stormy`

**Weather code → mood mapping (WMO canonical):**

| Codes | Mood |
|---|---|
| `0, 1, 2` | `clear` |
| `3, 45, 48, 600–621, 700–781, 801–804` | `cloudy` |
| `51–67, 80–82, 300–531` | `rainy` |
| `95, 96, 99, 200–299` | `stormy` |

---

### GET /next — Get a shuffle queue

Returns a dynamic shuffle queue. The engine supports four modes automatically:
1. **Smart (default)**: AI-scored shuffle across your entire library based on weather, time, season, and history.
2. **Playlist**: AI-scored shuffle restricted to songs currently inside a Navidrome playlist.
3. **All Songs**: Pure random shuffle pulling from your live Navidrome library.
4. **Candidates**: AI-scored shuffle restricted strictly to an explicit list of songs you provide.

#### 1. Smart Shuffle (Full Library)
```bash
curl -u admin:pass "https://shuffle.subimusic.me/next?count=10"
```

#### 2. Playlist Shuffle
```bash
curl -u admin:pass "https://shuffle.subimusic.me/next?playlist_id=abc1234&count=10"
```

#### 3. All Songs Random Shuffle
```bash
curl -u admin:pass "https://shuffle.subimusic.me/next?source=all_songs&count=10"
```

#### 4. Explicit Candidates Shuffle
```bash
curl -u admin:pass "https://shuffle.subimusic.me/next?candidates=Song1|Song2|Song3&count=2"
```

#### POST with full session context (recommended for Smart mode)
```bash
curl -u admin:pass -X POST https://shuffle.subimusic.me/next \
  -H "Content-Type: application/json" \
  -d '{
    "source": "smart",
    "count": 15,
    "depth": 3,
    "playlist": "kuthu",
    "genre_streak_type": "kuthu",
    "genre_streak_count": 2,
    "played_titles": "Yaanji,Rowdy Baby,Kannaana Kanney",
    "recent_listen_ratios": [0.92, 0.85, 0.78],
    "last_end_reason": "natural"
  }'
```

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `source` | string | `"smart"` | Mode: `smart`, `playlist`, `all_songs`, or `candidates` |
| `playlist_id` | string | `""` | Navidrome Playlist ID (triggers playlist mode) |
| `candidates` | string/array | `""` | Pipe or comma-separated list of explicit song titles |
| `count` | int | `15` | Number of songs to return |
| `depth` | int | `0` | How deep into the session (affects exploration) |
| `playlist_name` | string | `""` | Name of current playlist (sets genre streak) |
| `genre_streak_type` | string | `""` | Genre of current streak (e.g. `kuthu`) |
| `genre_streak_count` | int | `0` | How many consecutive songs in that genre |
| `played_titles` | string/array | `""` | Titles played this session (excluded from queue) |
| `recent_listen_ratios` | array | `[]` | Last N listen ratios (0.0–1.0) |
| `last_end_reason` | string | `""` | Why the last song ended (`natural`, `fwdbtn`, etc.) |
| `seed_title` | string | `""` | The song playing **now** — the pairing chain is ordered from it (falls back to the last `played_titles` entry). Sent by the app during smart-local refill. |

**Queue intelligence (v3.2 / v3.3):** ordering uses **second-order pairings** (`p(C | A, B)` — what you play after a *pair* of songs, falling back to the single-song pairing), follows the learned **session energy arc** (energy curve per time arc), keeps **composer diversity** in adjacent slots, **skip-** and **impression-demotes** songs you keep skipping / scrolling past, and uses **Thompson-sampled exploration** for the `explore` slot so discovery wanders across good-fit unheard songs. Pairing weight was raised (0.15 → 0.30) after an offline backtest showed it improves next-song accuracy. All of this is server-side; the client renders the queue and the `why` strings, which now note any skip/impression adjustment and the pairing `order`.

**Response:**
```json
{
  "mode": "smart",
  "source": "smart",
  "playlist_id": null,
  "session_starter": {
    "title": "Kaarkuzhal Kadavaiye",
    "time_arc": "evening",
    "sessions_started": 7,
    "share": 0.0526
  },
  "context": {
    "bucket": "night__summer__stormy",
    "base_bucket": "night__summer",
    "ist_hour": 21,
    "weather": "stormy",
    "weather_code": 95,
    "temperature_c": 26.6,
    "fallback_level": 1,
    "n_plays_in_profile": 138
  },
  "queue": [
    {
      "rank": 1,
      "title": "Missing Me",
      "file_path": "Santhosh Narayanan - Missing Me (From Mahaan).flac",
      "genre_bucket": "Melody",
      "composer": "Santhosh Narayanan; Dhruv Vikram",
      "audio": {
        "energy": 0.75,
        "valence": 0.537,
        "acousticness": 0.198,
        "danceability": 0.66
      },
      "scores": {
        "context_history": 1.0,
        "audio_fit": 0.982,
        "composer_loyalty": 1.0,
        "final": 0.984
      },
      "starter": true,
      "pairing": { "follows": "Anbil Avan", "times_followed": 9, "p": 0.1475, "order": 1 },
      "explore": false,
      "why": "Session starter — you've opened 7 evening sessions with this song (5% of starts). Played 8 times in night__summer with avg ratio 0.81. Audio fit 0.98 vs night__summer__stormy taste profile (n=138, fallback_level=1)."
    }
  ]
}
```

> **v3.1 session model** — at the start of a session (`depth = 0`, empty `played_titles`) the server pins your habitual opener for that time-of-day to rank 1 and returns it in the top-level `session_starter` object (`null` when none was applied). The queue is then re-ordered so learned song pairings sit adjacent. Per-song flags:
>
> | Field | Type | Description |
> |---|---|---|
> | `starter` | bool | This song is your pinned session opener. |
> | `explore` | bool | This is the queue's single never-played exploration pick. |
> | `pairing` | object? | Present when placed next to a song it historically follows: `{ follows, times_followed, p, order }`. `order` is `1` (unigram `p(this\|prev)`) or `2` (second-order `p(this\|prev2,prev)` — a sharper two-song-combo match, surfaced in the card as "2-song combo"). |
>
> Mid-session, send `played_titles` **in play order** — the pairing chain is seeded from the last title.

### Context Object Fields

| Field | Description |
|---|---|
| `bucket` | Full 3-part context key: `{time}__{season}__{weather}` |
| `base_bucket` | 2-part key: `{time}__{season}` (used for play history lookup) |
| `ist_hour` | Current IST hour (0–23) |
| `weather` | Live weather mood: `clear`, `cloudy`, `rainy`, `stormy` |
| `weather_code` | Raw WMO weather code |
| `temperature_c` | Current temperature in °C (Erode) |
| `fallback_level` | 0 = exact profile used, 1 = time+season fallback, 2 = time-only, 3 = global |
| `n_plays_in_profile` | Number of plays that built the active taste profile |

### Score Fields

| Field | Description |
|---|---|
| `context_history` | How well you've historically enjoyed this song at this time+season (0–1) |
| `audio_fit` | Gaussian fit of the song's audio features against your learned taste profile for this weather+time context (0–1) |
| `composer_loyalty` | How loyal you are to this composer based on avg listen ratio (0–1) |
| `final` | Weighted final score: `0.45 × history + 0.35 × audio_fit + 0.20 × composer` |

> [!TIP]
> The `why` field explains exactly why each song was chosen — including the taste profile it was scored against and the fallback level used. Great for debugging the model.

### Fallback Level Reference

When you haven't listened to enough songs in a specific `time__season__weather` context, the model falls back gracefully:

| Level | Profile Used | Trigger |
|---|---|---|
| `0` | `night__summer__stormy` (exact) | n ≥ 10 plays in this exact context |
| `1` | `night__summer` (season fallback) | n < 10 for this weather variant |
| `2` | `night` (time-only fallback) | n < 10 for this season too |
| `3` | `__global__` (all plays) | All other cases |

---

### GET /predict/always-hear — What you always hear at this time

Returns the songs you **always hear in the current context** — ranked specifically for the current time of day, season, and weather. **(v3.1: the context now drives the ranking — earlier builds returned the same list regardless of context.)**

Loyalty formula (weights tunable via `AH_WEIGHT_*`):
1. **ContextFit (35%)**: effective plays blended across the exact / `time__season` / time-only / global context levels, normalised. A song you only play in this context outranks one you play everywhere.
2. **CompletionAvg (30%)**: average listen ratio (quality of listens).
3. **RecencyDecay (20%)**: `0.5^(days_since_last_listen / 30)` — a true recency signal.
4. **FreqNorm (15%)**: log-normalised global play count.

Songs with fewer than 3 raw plays **or** completion average below 0.4 are excluded. The `scores` block now carries `loyalty`, `completion_avg`, `freq_norm`, `context_fit`, `context_spread`, `recency_decay` (no `final`/`audio_fit`); `context_stats` adds `days_since_play`.

```bash
# Basic request (default limit = 20)
curl -u admin:pass "https://shuffle.subimusic.me/predict/always-hear"

# Limit returned results and override weather for testing
curl -u admin:pass "https://shuffle.subimusic.me/predict/always-hear?limit=10&weather_code=51"
```

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `limit` | int | `20` | Number of ranked predictions to return (max 100). |
| `weather_code` | int | — | Optional. WMO weather code override to manually force a weather condition. |

**Response Headers:**
```http
Cache-Control: max-age=900
```

**Response:**
```json
{
  "request_context": {
    "bucket": "late_morning__summer__cloudy",
    "fallback_level": 0,
    "n_in_profile": 137,
    "weather": {
      "code": 3,
      "mood": "cloudy",
      "temperature_c": 31.0
    },
    "timestamp_ist": "2026-05-30T10:17:00+05:30"
  },
  "count": 1,
  "predictions": [
    {
      "rank": 1,
      "title": "Nee Paartha Vizhigal - The Touch of Love",
      "artist": "Anirudh Ravichander;Vijay Yesudas;Shweta Mohan;Dhanush",
      "album": "3 (Original Motion Picture Soundtrack)",
      "composer": "Anirudh Ravichander",
      "audio_features": {
        "energy": 0.596,
        "valence": 0.644,
        "acousticness": 0.293,
        "danceability": 0.665,
        "tempo": 110.055,
        "tempo_norm": 0.3575,
        "genre_bucket": "Kuthu / Dance",
        "file_path": "/DATA/Media/Music/3/Nee Paartha Vizhigal.flac"
      },
      "scores": {
        "loyalty": 0.8981,
        "completion_avg": 0.86,
        "freq_norm": 0.74,
        "context_fit": 1.0,
        "context_spread": 0.6,
        "recency_decay": 0.98
      },
      "context_stats": {
        "raw_plays": 41,
        "n_contexts": 3,
        "days_since_play": 1,
        "exact_plays": 12,
        "exact_avg_ratio": 0.84,
        "exact_effective": 6.9,
        "season_effective": 4.67,
        "global_effective": 6.51,
        "fallback_level": 0
      },
      "why": "You always hear this in 'late_morning summer cloudy' — context fit 1.00 (effective plays here: 6.9), completion 0.86 over 41 plays, last heard 1 days ago."
    }
  ]
}
```

---

### GET /predict/discovery — Discover unexplored songs matching taste

Returns unexplored or rarely-played songs from the library, ranked by how well their audio profile matches the user's learned preferences in the current context.

This endpoint helps the user discover hidden gems in their library that match their current "vibe" but have not been frequently played.

Scoring uses a two-signal model:
1. **Audio Taste Fit (80%)**: Learned audio features (Gaussian probability density) vs the context's taste profile.
2. **Composer Loyalty (20%)**: Historical loyalty score for the song's composer as a secondary tie-breaker.

```bash
# Basic discovery (default limit = 20, max_prior_plays = 2)
curl -u admin:pass "https://shuffle.subimusic.me/predict/discovery"

# Discover with custom limits and override weather
curl -u admin:pass "https://shuffle.subimusic.me/predict/discovery?limit=10&max_prior_plays=1&weather_code=3"
```

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `limit` | int | `20` | Number of discovery songs to return. |
| `max_prior_plays` | int | `2` | Filter to songs with less than or equal to this many raw play events globally. |
| `weather_code` | int | — | Optional. WMO weather code override. |

**Response Headers:**
```http
Cache-Control: max-age=900
```

**Response:**
```json
{
  "request_context": {
    "bucket": "late_morning__summer__cloudy",
    "fallback_level": 0,
    "n_in_profile": 137,
    "weather_mood": "cloudy",
    "max_prior_plays": 2,
    "timestamp_ist": "2026-05-30T10:17:00+05:30"
  },
  "count": 1,
  "discovery_pool": [
    {
      "rank": 1,
      "title": "Newyork Nagaram",
      "artist": "A.R. Rahman",
      "album": "A.R.RAHMAN VIBRATION",
      "composer": "A.R. Rahman",
      "audio_features": {
        "energy": 0.732,
        "valence": 0.577,
        "acousticness": 0.203,
        "danceability": 0.652,
        "tempo": 127.043,
        "tempo_norm": 0.4789,
        "genre_bucket": "Melody",
        "file_path": "/DATA/Media/Music/A.R. Rahman/Newyork Nagaram.flac"
      },
      "scores": {
        "audio_fit": 0.8374,
        "composer": 0.268,
        "final": 0.7235
      },
      "context_stats": {
        "raw_global_plays": 2,
        "fallback_level": 0
      },
      "why": "Audio profile matches your late_morning summer cloudy taste (energy 0.68±0.17, acousticness 0.27±0.21, n=137 plays in profile). You have never played this song."
    }
  ]
}
```

---

### POST /feedback — Record a played track

Send this after every song ends so the model learns your taste. This is how your personal model improves over time.

```bash
curl -u admin:pass -X POST https://shuffle.subimusic.me/feedback \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Missing Me",
    "file_path": "Santhosh Narayanan - Missing Me (From Mahaan).flac",
    "genre_bucket": "Melody",
    "composer": "Santhosh Narayanan",
    "listen_ratio": 0.94,
    "end_reason": "natural",
    "session_id": "sess-abc123",
    "session_depth": 3,
    "genre_streak_type": "melody",
    "genre_streak_count": 3,
    "weather_code": 51,
    "temperature_c": 26.6,
    "volume": 0.8
  }'
```

**Key fields:**

| Field | Type | Description |
|---|---|---|
| `title` | string | **Required.** Song title (must match FLAC metadata) |
| `listen_ratio` | float (0–1) | How much of the song was listened to |
| `end_reason` | string | `natural` / `fwdbtn` / `backbtn` / `pause` |
| `session_id` | string | Unique session identifier |
| `session_depth` | int | Position in session (1st song = 1) |
| `genre_streak_type` | string | Genre being streaked |
| `genre_streak_count` | int | Number of songs in current streak |
| `weather_code` | int | WMO weather code at time of listening |
| `temperature_c` | float | Temperature in °C at time of listening |

**Response:**
```json
{ "ok": true }
```

> [!TIP]
> The model automatically rebuilds when you accumulate 50 new unprocessed plays. The scheduler checks every 60 seconds.

---

### POST /feedback/impressions — Record shown-vs-played

Reports which recommended titles were **surfaced** (`shown`) and which were actually **played**. Songs shown repeatedly but never played are demoted on the next rebuild. The app sends this when a shuffle session ends (on `clearQueue`). Best-effort — failures never affect playback.

```bash
curl -u admin:pass -X POST https://shuffle.subimusic.me/feedback/impressions \
  -H "Content-Type: application/json" \
  -d '{ "shown": ["Naani Koni","Azhage","Idhu Varai"], "played": ["Naani Koni"] }'
```

| Field | Type | Description |
|---|---|---|
| `shown` | array/string | **Required.** Titles surfaced this session |
| `played` | array/string | Subset of `shown` the user actually played |

**Response:** `{ "ok": true, "recorded": 3 }`

---

### GET /model/status — Your model's current state

```bash
curl -u admin:pass https://shuffle.subimusic.me/model/status
```

**Response:**
```json
{
  "username": "admin",
  "built_at": "2026-05-29T16:09:58+00:00",
  "total_plays_processed": 12139,
  "songs_in_library": 466,
  "composers_tracked": 187,
  "context_buckets": 12,
  "songs_with_pairings": 242,
  "starter_contexts": 6,
  "unprocessed_events": 1,
  "model_size_mb": 14.2,
  "rebuild_threshold": 50
}
```

> `songs_with_pairings` and `starter_contexts` (v3.1) report the size of the learned session model — how many songs have at least one learned follow-on pairing, and how many time-of-day contexts have habitual session starters.

---

### GET /listening-log/stats — Listening statistics

```bash
# Weekly stats (default)
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/stats?period=weekly"

# Daily / monthly / all time
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/stats?period=daily"
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/stats?period=monthly"
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/stats?period=all"
```

**Periods:** `daily` | `weekly` | `monthly` | `all`

> [!IMPORTANT]
> For the **admin** user, `period=all` includes the full Apple Music history (~19k plays) merged with live Navivibe plays. Top tracks and artists reflect all-time listening across both sources.

**Response:**
```json
{
  "period": "all",
  "label": "All time",
  "total_plays": 12139,
  "total_minutes": 36893,
  "avg_listen_ratio": 0.711,
  "skip_rate": 0.291,
  "streak_days": 1,
  "top_artists": [
    { "artist": "Anirudh Ravichander", "play_count": 2151 }
  ],
  "top_albums": [
    { "album": "Kaththi (Original Motion Picture Soundtrack)", "artist": "Anirudh Ravichander", "play_count": 212 }
  ],
  "top_tracks": [
    { "title": "Monica (From \"Coolie\") (Tamil)", "artist": "Unknown Artist", "album": "", "play_count": 126 }
  ],
  "recent_plays": [
    {
      "title": "Missing Me",
      "artist": "Santhosh Narayanan; Dhruv Vikram",
      "album": "Mahaan",
      "played_at_ist": "2026-05-29T21:30:00+05:30",
      "listen_ratio": 0.94,
      "genre": "Melody"
    }
  ],
  "genre_breakdown": [
    { "genre": "Melody", "play_count": 3904, "pct": 32.2 },
    { "genre": "Kuthu / Dance", "play_count": 1477, "pct": 12.2 }
  ],
  "hourly_heatmap": {
    "7": 1396, "8": 1063, "14": 578, "16": 723, "17": 2259, "21": 653
  }
}
```

---

### GET /listening-log/contribution-graph — Daily play counts

Returns a list of daily play counts for a user. Useful for building GitHub-style contribution/activity graphs. Filters out aborted plays (skips).

```bash
curl -u admin:pass https://shuffle.subimusic.me/listening-log/contribution-graph
```

**Response:**
```json
{
  "data": [
    { "date_str": "2024-05-20", "count": 45 },
    { "date_str": "2024-05-21", "count": 12 },
    { "date_str": "2024-05-22", "count": 38 }
  ]
}
```

---

### GET /listening-log/history — Paginated play history

```bash
# Basic (last 50 plays)
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/history"

# With pagination
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/history?limit=20&offset=40"

# Filter by artist
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/history?artist=Anirudh"

# Filter by title
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/history?title=Missing+Me"

# Filter by period
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/history?period=weekly&limit=100"
```

**Parameters:**

| Parameter | Default | Description |
|---|---|---|
| `limit` | `50` | Results per page (max 500) |
| `offset` | `0` | Skip N results (for pagination) |
| `artist` | — | Case-insensitive artist name filter |
| `title` | — | Case-insensitive title filter |
| `period` | `all` | `daily` / `weekly` / `monthly` / `all` |

**Response:**
```json
{
  "total": 12139,
  "offset": 0,
  "limit": 50,
  "items": [
    {
      "title": "Missing Me",
      "artist": "Santhosh Narayanan; Dhruv Vikram",
      "album": "Mahaan",
      "played_at_ist": "2026-05-29T21:30:00+05:30",
      "listen_ratio": 0.94,
      "end_reason": "natural",
      "genre": "Melody"
    }
  ]
}
```

---

### GET /listening-log/composers — Composer loyalty table

Shows which composers you listen to most completely (high avg listen ratio = high loyalty).

```bash
curl -u admin:pass https://shuffle.subimusic.me/listening-log/composers
```

**Response:**
```json
{
  "total_composers": 187,
  "composers": [
    {
      "composer": "Anirudh Ravichander",
      "loyalty_ratio": 0.872,
      "total_plays": 4820
    },
    {
      "composer": "A.R. Rahman",
      "loyalty_ratio": 0.841,
      "total_plays": 3210
    }
  ]
}
```

---

### GET /listening-log/song — Song deep dive

Full history for a single song across all context buckets.

```bash
# URL-encode spaces with + or %20
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/song?title=Missing+Me"
curl -u admin:pass "https://shuffle.subimusic.me/listening-log/song?title=Ethir+Neechal"
```

**Response:**
```json
{
  "title": "Missing Me",
  "composer": "Santhosh Narayanan",
  "genre_bucket": "Melody",
  "audio_features": {
    "energy": 0.75,
    "valence": 0.537,
    "acousticness": 0.198,
    "danceability": 0.66,
    "tempo": 77.5
  },
  "total_plays": 130,
  "genuine_plays": 51,
  "best_context": {
    "context_bucket": "evening__summer",
    "avg_ratio": 1.0,
    "play_count": 8
  },
  "worst_context": {
    "context_bucket": "night__southwest_monsoon",
    "avg_ratio": 0.583,
    "play_count": 3
  },
  "context_history": [
    { "context_bucket": "afternoon__southwest_monsoon", "avg_ratio": 0.805, "play_count": 34 },
    { "context_bucket": "afternoon__summer",            "avg_ratio": 0.696, "play_count": 23 },
    { "context_bucket": "evening__southwest_monsoon",   "avg_ratio": 0.865, "play_count": 18 },
    { "context_bucket": "afternoon__northeast_monsoon", "avg_ratio": 0.894, "play_count": 12 },
    { "context_bucket": "evening__summer",              "avg_ratio": 1.0,   "play_count": 8  }
  ]
}
```

> [!NOTE]
> `total_plays` = all raw play events including skips. `genuine_plays` = plays with listen_ratio ≥ 0.5 (the count the model actually learns from).

---

## Error Codes

| Code | Meaning |
|---|---|
| `401` | Missing or invalid credentials |
| `400` | Bad request parameter (e.g. invalid `period`) |
| `404` | Song not found in model |
| `500` | Server error (check `sudo journalctl -u navivibe -n 50`) |

---

## Context Buckets Reference

The model scores songs differently for each time + season + weather combination.

### Time Slots (IST)

| Time | Hours (IST) |
|---|---|
| `morning` | 5–8 |
| `late_morning` | 9–12 |
| `afternoon` | 13–17 |
| `evening` | 18–20 |
| `night` | 21–23 |
| `late_night` | 0–4 |

### Seasons

| Season | Months |
|---|---|
| `summer` | March–May |
| `southwest_monsoon` | June–September |
| `northeast_monsoon` | October–December |
| `winter` | January–February |

### Weather Moods

| Mood | When |
|---|---|
| `clear` | WMO codes 0, 1, 2, 800 |
| `cloudy` | WMO codes 3, 45, 48, 801–804 |
| `rainy` | WMO codes 51–67, 80–82 |
| `stormy` | WMO codes 95, 96, 99 |

**Example full context bucket:** `night__summer__rainy` = listening at 10 PM in April while it's raining.

---

## How the Taste Profile Model Works

The shuffle engine learns your **audio feature preferences per context** from your listening history.

For each `time__season__weather` context it tracks:
- The mean and standard deviation of `energy`, `valence`, `acousticness`, `danceability`, and `tempo` across all songs you genuinely listened to (listen_ratio ≥ 0.5) in that context.

At shuffle time, every song in your library is scored via a **Gaussian fit** against your current context's learned profile:
```
audio_fit = avg(exp(-0.5 * ((song_feature - your_mean) / your_std)²))
            across energy, valence, acousticness, danceability
```

This means:
- A song perfectly matching your taste profile scores 1.0.
- A song 1 std-dev away scores ~0.61 (not zero — it might still play).
- Songs you've **never heard** are scored the same way — solving the cold-start problem.

**Data sources for taste profiles (admin):**

| Source | Plays | Weight |
|---|---|---|
| Live play_events (Navivibe) | ~40 | 1.0× |
| Apple Music history (backfilled with Erode weather) | 8,053 | 1.0× |
| Legacy Navivibe DB (backfilled with Erode weather) | 560 | 0.6× |

---

## Trigger a Manual Model Rebuild

If you want to rebuild your model immediately (without waiting for 50 plays):

```bash
# On the server
cd /opt/shuffle-server
venv/bin/python -m navivibe.preprocess --full --username admin
venv/bin/python -m navivibe.preprocess --full --username pradeep

sudo systemctl restart navivibe
```

## Inspect Taste Profiles

```bash
cd /opt/shuffle-server

# Coverage table — all 66 full context buckets with n and fallback level
venv/bin/python -m navivibe.taste_profile_inspector --coverage

# Show profile for a specific context
venv/bin/python -m navivibe.taste_profile_inspector --context evening__summer__rainy

# Show how a song fits against all contexts it's been played in
venv/bin/python -m navivibe.taste_profile_inspector --song "Missing Me"

# Dump all profiles
venv/bin/python -m navivibe.taste_profile_inspector --all
```

## Backfill Historical Weather

To re-run the Apple Music + legacy DB weather enrichment (e.g. after adding new plays):

```bash
cd /opt/shuffle-server

# Full backfill (Apple Music + legacy DB)
venv/bin/python -m navivibe.backfill_weather

# Apple Music only
venv/bin/python -m navivibe.backfill_weather --apple

# Sanity check: verify UTC→IST conversion on 10 sample plays
venv/bin/python -m navivibe.backfill_weather --sanity
```

## Tune Scoring Weights

Weights can be adjusted in `.env` without redeploying:

```bash
# .env
SCORE_WEIGHT_HISTORY=0.45     # how much play history matters
SCORE_WEIGHT_AUDIO=0.35       # how much learned audio taste profile matters
SCORE_WEIGHT_COMPOSER=0.20    # how much composer loyalty matters
```

Restart after changing: `sudo systemctl restart navivibe`

## Run the Multi-User Test

```bash
cd /opt/shuffle-server
venv/bin/python test_multiuser.py \
  --user1 admin   --pass1 <adminpass> \
  --user2 pradeep --pass2 <pradeeppass>
```
