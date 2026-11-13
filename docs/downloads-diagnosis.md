# Downloads: missing covers + offline play recording — diagnosis (research only)

Branch `feature/search-online` @ d9de507. No code changed. Nothing was run on a device; all findings are from reading the code (so "likely" marks what I did not reproduce).

---

## 1. Bug: no cover images in Downloads

### How a download stores art today
- `OfflineService.downloadSong` (`lib/offline_service.dart:246`) saves, per song, in the downloads folder: `<id>.<ext>` (audio), `<id>.song.json` (metadata), `<id>.lyrics.json`, and **`<id>.jpg` (cover, 600px)** at `:292-306`. So covers *are* saved to disk at download time. Failure there is swallowed (`:304`), so a failed cover fetch leaves no file and no sign.
- `OfflineService.getLocalCoverArtPath(id)` (`:151`) returns that file. Hive is not involved: the downloaded-id list is in SharedPreferences (`offline_downloaded_songs`, `:60`), the rest is files next to the audio.

### Root cause A (main one): the UI never asks for the saved file
The only callers of `getLocalCoverArtPath` are lock-screen/notification art in `lib/services/navi_audio_handler.dart:476, 567, 602, 1019`. **No widget uses it.**

The Downloaded list (`SongsPage(downloadedOnly: true)`, `lib/screens/library/songs_page.dart:33`, opened from `library_screen.dart:61`) is built like this:
1. `PaginatedSongsNotifier` (`lib/providers/library_provider.dart:~829-885`) reads the Drift `songMetadata` mirror, filtered to downloaded ids, and builds `Song(... coverArt: r.songId ...)` (`:885`). The song id is used as the cover id.
2. `SongTile` (`lib/widgets/song_tile.dart:108-113`) calls `subsonicService.getCoverArtUrl(song.coverArt)` → a **network URL** `…/rest/getCoverArt.view?id=<songId>&t=…&s=…` (`subsonic_service.dart:211-221`).
3. `CoverArt` (`lib/widgets/cover_art.dart:~75-100`) loads it with `CachedNetworkImage`, appending `size=<step>` (`sizedCoverUrl`). On error it shows the note placeholder.

So the Downloaded tab is exactly as good as the network/disk cache of the HTTP image. Offline (airplane mode, server down, away from home), nothing loads. The `<id>.jpg` that was downloaded is never read.

### Root cause B: the `CachedNetworkImage` disk cache is not a reliable fallback
- The cache key is the full URL incl. `size=` (`sizedCoverUrl` rounds to 96/160/256/…). A cover first seen at size 96 in Search is a different key from size 160 in the Downloaded list; offline only the sizes you happened to view online exist, and the default cache manager evicts (~30 days / 200 objects).
- Songs fetched through the Telegram/online-fetch flow and downloaded right after import can have no Navidrome cover yet (index lag), and `downloadSong` silently ignores the failed cover request, so there is neither a cached nor a saved cover.
- After a Navidrome id change (`id_migration_provider`), `remapSongIds` renames `<id>.jpg` correctly (`offline_service.dart:562`), but the cache keys by URL with the old id are orphaned. Another reason the cache can't be the source of truth.

### Root cause C: Downloaded list depends on the library mirror, not the download folder
The list is `songMetadata WHERE songId IN downloaded`. Songs downloaded but absent from the mirror (first sync not finished, server dropped the song, fresh install with downloads moved onto the phone) never appear, so even with a perfect image path some rows would be missing. `OfflineService.getDownloadedSongsMetadata()` (`:195`, reads `<id>.song.json`) exists and has **zero callers**; it is the offline-correct source.

### Local folders (local-library feature)
This path is designed correctly and *should* show covers:
- Scanner reads embedded pictures (`readMetadata(getImage: true)`, prefers `coverFront`) and falls back to `folder.jpg`-style art (`tag_reader.dart:106-130`), saves under app-support dir `local_library_providers.dart:37`, stores `coverPath` in Drift, and `rebuildIndex()` (`local_library_service.dart:200-211`) fills `LocalLibraryIndex.coverFor`.
- `getCoverArtUrl` turns a `local:` id into a `file:` URI (`subsonic_service.dart:214-217`); `CoverArt` has an `Image.file` branch for it.

Likely failure points (not reproduced; check on device first, see tests below):
1. **Startup race.** `LocalLibraryIndex` is filled asynchronously (`local_library_providers.dart:161`, `unawaited(rebuildIndex())`). `SongTile` calls `ref.read(subsonicServiceProvider).getCoverArtUrl(...)` in `build`, a plain read, so no rebuild when the index lands. Tiles built before the index is ready get `''` → placeholder and stay that way until scrolled off and back.
2. **Matched songs lose their local cover.** `local_library_service.dart:~190` sets `serverId` and the index maps `serverId → path`, but **not `serverId → cover`** (`:208-209` only keys covers by `r.songId`). A local file that was matched to a server song is played from disk but its tile uses the server cover id → network → blank offline.
3. **Local songs are not in the Downloaded tab** at all (they aren't in `downloadStateProvider`). If "Downloads section" means that tab, local-folder songs correctly won't be there; they live in Settings → Local music (`local_songs_page.dart`). Worth confirming which screen the user means.
4. SAF (`content://`) folders: `readMetadata` runs on a copy; failures are caught and give `coverPath == null` (`tag_reader.dart:112-114`), silently. Needs a device check with a SAF folder.

### Proposed fix (offline-first cover resolution)
1. **One resolver**: `coverUrlFor(Song)` / `CoverArt.forSong(song)` that returns, in order: (a) `file:` URI of `<id>.jpg` from `OfflineService.getLocalCoverArtPath` (sync, in-memory set, no I/O), (b) local-library cover (incl. `serverId` alias), (c) network URL. Use it in `SongTile` and every list that shows songs (queue pane, album/playlist song rows). `CoverArt` already renders `file:` URLs, so no new image widget is needed. Watch `downloadStateProvider.select(m => m[id]?.status)` so the tile switches to the file once the download finishes.
2. **Make saving reliable**: retry cover fetch once, validate bytes (non-empty, image magic) before keeping `<id>.jpg`, and surface "downloaded without cover" (or re-try on next online start: a small "backfill missing covers" pass over downloaded ids lacking `.jpg`; this also fixes already-downloaded songs, which have the audio but may lack the jpg).
3. **Dedupe by album**: store `cover_<coverArtId>.jpg` instead of `<songId>.jpg` (an album of 12 tracks currently saves 12 identical 600px files). Needs a rename migration alongside `remapSongIds`; optional, lower priority.
4. **Downloaded list from disk**: build the Downloaded tab from `<id>.song.json` (`getDownloadedSongsMetadata`) when offline or when the mirror lacks the id; keeps title/artist/art available with no server.
5. **Local library**: add `serverId → cover` in `rebuildIndex`; make `getCoverArtUrl` callers watch a `localIndexRevisionProvider` (or have `CoverArt` take the song and resolve in a `Consumer`) so tiles repaint when the index finishes loading.
6. Minor: `OfflineService.setOfflineMode` is never called (`isOfflineMode` is always false; used only by `status_providers.dart:131`). Real offline detection is `isOfflineProvider` (connectivity stream). Not part of this bug, but the Status screen's "Offline mode is on" row can never show.

**Effort:** steps 1+2+5 ≈ 0.5–1 day incl. tests; step 4 ≈ +0.5 day; step 3 optional ≈ +0.5 day.

**Tests to add**
- Unit: `OfflineService` with a temp dir: after `downloadSong` (fake Dio/Subsonic) `<id>.jpg` exists; failed cover fetch → no file and backfill later creates it; `remapSongIds` moves `.jpg`.
- Unit: resolver precedence (downloaded file > local-library cover > network) and `serverId` alias for local matches.
- Widget: `SongTile` for a downloaded song with network unreachable (override `debugCoverImageOverride` / use a `file:` URL) renders the image, not the note placeholder; `SongTile` rebuilds when the local index revision bumps.
- Golden/regression: Downloaded page with 3 downloaded songs and `connectivityProvider` = none.
- Device check (per project memory "verify on device"): airplane mode on the OnePlus, open Library → Downloaded, and a local folder with embedded art + one with only `folder.jpg`.

---

## 2. Question: are plays of downloaded songs recorded, and pushed when online?

Short answer: **recorded locally yes; pushed to the server only when online at that moment; nothing is queued or retried. Offline plays are lost to Navidrome and to the shuffle server/Replay/stats.**

### What happens on a play (same code path for streamed or downloaded files)
| Sink | Where | Offline | Online, playing a downloaded file |
|---|---|---|---|
| Navidrome now-playing (`submission=false`) | `player_provider.dart:949` → `ScrobbleService.nowPlaying` (`scrobble_service.dart:41-44`) | skipped (`_isOffline()` returns early) | sent |
| Navidrome scrobble (`submission=true`), at 50% of duration or 4 min listened | `player_provider.dart:1176-1190` → `ScrobbleService.submit` (`:51-56`) | **skipped, not queued** | sent, fire-and-forget; errors swallowed (`SubsonicService.scrobble`, `subsonic_service.dart:782-793`) |
| Shuffle server `POST /feedback` (feeds Flow, Smart Shuffle, Replay, stats) | `sendShuffleFeedback` (`shuffle_providers.dart:364`) at track end / skip (`player_provider.dart:905, 1105, 1580`) | request fails, error swallowed (`shuffle_repository.dart:157-163`), **lost** | sent |
| Local Drift `play_events` (`ListeningEventCollector`) | `player_provider.dart` `onSongStarted/Ended` → `_writeEvent` | **always written** (works offline) | written |
| `local:` ids (local-folder songs) | `scrobble_service.dart:41,51` skip | no Navidrome scrobble by design; `/feedback` still posts `filePath: local:…` which the server can't match | same |

So the Drift table is the only place offline plays survive, and it is not read back for Replay/stats: Replay and the stats screen read the shuffle **server** (`navivibe_replay_provider.dart`: "sourced from the Navivibe server, not the local Drift DB"). Local Drift feeds only on-device features (smart playlists, recently played).

### The offline queue exists but is dead code
`OfflineService.queueScrobble` (`offline_service.dart:606`) and `flushPendingScrobbles` (`:633`) implement a SharedPreferences outbox (`pending_scrobbles`), and `remapSongIds` even migrates it. **Neither has any caller** (grep over `lib/` and `test/`: only the id-migration test touches the key). Nothing listens to connectivity changes to flush (`onConnectivityChanged` is used only by `isOfflineProvider`/`transcoding_service`).

### Gaps (ordered by impact)
1. Offline Navidrome scrobbles dropped (`ScrobbleService` returns instead of calling `queueScrobble`).
2. Offline (or server-unreachable-but-"online") `/feedback` dropped: no outbox at all, so Flow/Smart Shuffle/Replay/stats under-count every offline listen. Also a connectivity "online" with an unreachable server loses the scrobble because `SubsonicService.scrobble` swallows the error and the caller never knows.
3. **Timestamps not preserved.** `SubsonicService.scrobble` always sends `time = DateTime.now()` (`:787`) and has no `time` parameter. Even the dead `flushPendingScrobbles` ignores the stored `time` (`:642-645`), so a flush would stamp every play with the flush time (Navidrome history/"recently played" would show them all at reconnect). `FeedbackRequest` has **no timestamp field** (`feedback_request.dart`; server stamps on receipt), so a delayed push would land in the wrong hour/day bucket: that corrupts Replay by month and the time-of-day features.
4. No dedupe: the queue stores no play id, flush isn't atomic (a crash mid-flush re-sends already-sent entries, since the list is rewritten only at the end), and `/feedback` has no idempotency key. Navidrome does not dedupe repeated scrobbles of the same song (I believe each submission is a play; not verified against 0.64).
5. Weather/volume etc. in `/feedback` would be captured at send time, not play time, if queued naively (store them at play time).
6. now-playing is real-time only; correct not to queue it.

### Proposed design
**Outbox** (new `PlayOutbox`, replaces the dead SharedPreferences code; store in the Drift DB or a Hive box, not SharedPreferences, since entries can reach thousands and need atomic updates):
- Row: `play_id` (the existing `PlayEvent.playId` UUID, which `ListeningEventCollector` already generates, doubling as the idempotency key), `song_id`, `ts_start_ms`, `scrobble_sent`, `feedback_sent`, the full `FeedbackRequest` JSON captured at play time (incl. weather/volume/session fields), attempt count.
- **Write at the moment a play qualifies** (the same two trigger points that exist today), always, online or offline. Then immediately try to deliver: this makes "online + downloaded" push right away and "offline" queue with no separate code path.
- Deliver: Navidrome `scrobble.view?id=…&time=<ts_start_ms>&submission=true` (add a `time` parameter to `SubsonicService.scrobble`; Subsonic/Navidrome honour it) and `POST /feedback` with the original payload. Mark each leg sent only on HTTP 2xx (stop swallowing errors in the outbox path); delete the row when both legs are done; local ids and `scrobble`-ineligible songs only have the feedback leg.
- **Flush triggers**: connectivity stream going from none → any, app start/resume, successful login, plus a backoff timer while rows exist. Process oldest first, serially, cap batch (server limit for `feedback` is 60/min per `docs/backend/SECURITY.md:81`, so ≤ ~50/min with a short delay).
- **Server changes** (separate small change, in the Flask shuffle server, which is not in this repo): accept optional `played_at` (epoch ms) and `play_id` on `/feedback`; use `played_at` for the listening-log timestamp/hour bucket and make `play_id` unique (ignore repeats) so retries are safe. Until that ships, the app can still send the outbox but the server will bucket by receive time; in that case consider sending the feedback leg only for plays queued < ~1 h ago, or accept the skew.
- Cap: 5,000 rows / 90 days; drop oldest scrobble legs first. Surface count in the Status screen ("12 plays waiting to sync").
- Replay/stats are server-sourced, so they only become correct once the outbox flushes; the Drift copy lets us also show an on-device "pending" count and, optionally, merge pending plays into the stats UI.

**Effort:** outbox + `time` param + connectivity flush + tests ≈ 1–1.5 days app side; server `played_at`/`play_id` ≈ 0.5 day (backend-hardening owner). 

**Tests to add**
- `ScrobbleService`/outbox unit: offline qualifying play → row written, no HTTP; reconnect event → both legs sent with the original `time`; failure on leg 1 keeps row, leg 2 still retried; crash-resume sends no duplicate (play_id unique).
- `SubsonicService.scrobble` sends the passed `time`, default now.
- Player integration (extend `test/scrobble_test.dart` mocks): playing a downloaded song while `connectivityProvider` = none creates an outbox row; with online it delivers immediately and leaves no row.
- Server contract test for `played_at`/`play_id` idempotency.

---

## Suggested order
1. Resolver + backfill covers + local index fixes (visible bug, small).
2. Downloaded list from `<id>.song.json`.
3. Outbox + `time` param (client), then server `played_at`/`play_id`.
