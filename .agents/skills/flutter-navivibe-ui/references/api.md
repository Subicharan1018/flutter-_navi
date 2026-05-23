# NaviVibe API Reference — Flutter Integration

Base URL: `https://shuffle.subimusic.me`

## Auth

Every protected call needs either Bearer JWT or Basic Auth.
In Flutter, store credentials in `SecureStorage` — NEVER in SharedPreferences.

```dart
// _BasicAuthInterceptor (already in your codebase — use it)
// Sets: Authorization: Basic <base64(user:pass)>
```

---

## Endpoints Used by Dashboard

### GET /listening-log/stats?period={period}

Periods: `daily` | `weekly` | `monthly` | `all`

**Dart model:**
```dart
class ListeningStatsResponse {
  final String period;
  final String label;
  final int totalPlays;
  final int totalMinutes;
  final double avgListenRatio;
  final double skipRate;
  final int streakDays;
  final List<ArtistStat> topArtists;
  final List<AlbumStat> topAlbums;
  final List<TrackStat> topTracks;
  final List<RecentPlay> recentPlays;
  final List<GenreBreakdown> genreBreakdown;
  final Map<String, int> hourlyHeatmap; // "0"–"23" → count
}

class GenreBreakdown {
  final String genre;
  final int playCount;
  final double pct;
}

class TrackStat {
  final String title;
  final String artist;
  final String album;
  final int playCount;
}

class ArtistStat {
  final String artist;
  final int playCount;
}

class RecentPlay {
  final String title;
  final String artist;
  final String album;
  final String playedAtIst;  // ISO8601
  final double listenRatio;
  final String genre;
}
```

---

### GET /model/status

**Dart model:**
```dart
class ModelStatusResponse {
  final String username;
  final String builtAt;           // ISO8601
  final int totalPlaysProcessed;
  final int songsInLibrary;
  final int composersTracked;
  final int contextBuckets;
  final int unprocessedEvents;
  final double modelSizeMb;
  final int rebuildThreshold;

  // Derived: rebuild progress
  double get rebuildProgress =>
    (unprocessedEvents / rebuildThreshold).clamp(0.0, 1.0);
}
```

---

### GET /weather

```dart
class WeatherInfo {
  final int code;
  final String mood;        // clear | cloudy | rainy | stormy
  final double temperatureC;
  final int humidityPct;
  final String fetchedAt;
}
```

---

### GET /listening-log/history

```dart
class ListeningHistoryResponse {
  final int total;
  final int offset;
  final int limit;
  final List<PlayHistoryItem> items;
}

class PlayHistoryItem {
  final String title;
  final String artist;
  final String album;
  final String playedAtIst;
  final double listenRatio;
  final String endReason;   // natural | fwdbtn | backbtn | pause
  final String genre;
}
```

---

### GET /listening-log/composers

```dart
class ComposerLoyalty {
  final String composer;
  final double loyaltyRatio;
  final int totalPlays;
}
```

---

### GET /listening-log/song?title={title}

```dart
class SongDeepDive {
  final String title;
  final String composer;
  final String genreBucket;
  final AudioFeatures audioFeatures;
  final int totalPlays;
  final ContextHistory bestContext;
  final ContextHistory worstContext;
  final List<ContextHistory> contextHistory;
}

class ContextHistory {
  final String contextBucket;  // e.g. "night__summer"
  final double avgRatio;
  final int playCount;
}
```

---

## Context Buckets Reference

| Time Label | Hours IST |
|---|---|
| morning | 5–8 |
| late_morning | 9–12 |
| afternoon | 13–17 |
| evening | 18–20 |
| night | 21–23 |
| late_night | 0–4 |

| Season | Months |
|---|---|
| summer | March–May |
| southwest_monsoon | June–September |
| northeast_monsoon | October–December |
| winter | January–February |

---

## Error Handling in Flutter

```dart
// Map HTTP status codes
// 401 → show login screen (AuthException)
// 400 → show validation error
// 404 → show empty state (song not found)
// 500 → show generic error + retry

try {
  final stats = await _service.getListeningStats(period: 'weekly');
  return stats;
} on AuthException {
  ref.read(authProvider.notifier).logout();
  rethrow;
} on NetworkException {
  throw AppException('No connection. Check your network.');
} on ServerException catch (e) {
  throw AppException('Server error: ${e.message}');
}
```
