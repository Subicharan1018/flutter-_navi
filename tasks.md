# NaviVibe — Bug & Improvement Backlog

Findings from a manual review of the core playback path, shuffle/queue logic,
race-condition surface, UI layer, and the Smart Shuffle API client (audited
against `api_refernce.md` v4.0.0).

Review was logic-only — `dart analyze` was **not** run, so analyzer-level
findings may still exist. The `graphify`/`GRAPH_REPORT.md` references in
`CLAUDE.md` point to files that don't exist on disk; this review used the real
source.

Priority key: **P0** = correctness/security, fix first · **P1** = real bug, user-visible ·
**P2** = quality/perf/maintainability · **P3** = cleanup.

---

## A. Race conditions & concurrency

### [P0] RC-1 — Queue lock is advisory; mutating ops bypass it
**File:** `lib/providers/player_provider.dart`
`applyShuffleAlgorithm` (1022), `_applySmartLocalAlgorithm` (1107),
`reshuffleActiveQueue` (1371) hold `_queueOpLock` **across an HTTP await**. But
`addToQueue` (878), `addAllToQueue` (887), `removeFromQueue` (897),
`reorderQueue` (915) never acquire the lock.

During an in-flight smart-local fetch, the snapshot taken at 1123–1128
(`pastAndPresent`/`future`) goes stale: `_audioHandler.currentQueue` is mutated
underneath it, then `commitSmartLocalOrder` writes a queue rebuilt from the
stale snapshot. The `_moveBasedReorder` length-mismatch guard
(`navi_audio_handler.dart:726`) only prevents a `RangeError` — it does **not**
prevent an added/removed song from being silently dropped or duplicated.

**Fix:** route every queue mutation through the lock (e.g. a single
`Future<T> _withQueueLock<T>(...)` helper that awaits the prior completer and
installs its own). No queue-mutating method should touch `state.queue` or
`_audioHandler` without holding it.

### [P0] RC-2 — `_suppressStreamEvents` is a non-reentrant bool used reentrantly
**File:** `lib/providers/player_provider.dart`
At least 8 methods do `_suppressStreamEvents = true; ... finally { _suppressStreamEvents = false; }`.
When two overlap, the inner `finally` clears it while the outer still needs
suppression. Concretely: the shuffle guard keeps it `true` for 500 ms
(1089–1099); a `removeFromQueue` during that window runs its own `finally` and
flips it to `false` early, so the transient just-audio index events the guard
exists to swallow now leak through — the exact desync BUG-004 keeps trying to
kill.

**Fix:** replace the bool with an int depth counter
(`_suppressDepth++` / `--`); suppress while `> 0`. Audit every current
`= true`/`= false` site and convert to increment/decrement in try/finally.

### [P1] RC-3 — `_fetchAndReorderSmartLocal` double-appends the batch
**File:** `lib/providers/player_provider.dart:1626-1664`
Branch B of the `Future.wait` appends `batch` to `state.queue` (1627), while
branch A's resolved `ordered` already **contains** `batch` (built from
`fullFuture = existingFuture + batch`). After the wait, `commitSmartLocalOrder`
sets the queue to `pastAndPresent + ordered`, overwriting branch B's append. It
converges, but for one frame `state.queue` shows duplicates and the logic only
survives because the overwrite hides it.

**Fix:** drop branch B's `state` write; let `commitSmartLocalOrder` be the single
source of truth for the post-fetch queue.

### [P1] RC-4 — Linux index mutated before the mutex-guarded load (skip desync)
**File:** `lib/services/navi_audio_handler.dart`
`_linuxSkipToNext` (605), `_linuxSkipToPrevious` (621), `jumpToIndex` (649),
`skipToQueueItem` (663) all do `_linuxIndex = next` **then**
`await _precomputeOfflinePaths(...)` **then** `_linuxLoadTrack`. But
`_linuxLoadTrack` is guarded by the `_linuxLoading` mutex and *silently returns*
if a load is already running (516–519) — the index mutation is **not** guarded.

If a natural track-completion advance (`_startLinuxCompletionListener`, 569) and
a user "Next" tap overlap, both bump `_linuxIndex` but only one actually loads →
a track is skipped and `_linuxIndex` no longer matches the playing audio. The
completion listener checks `_linuxLoading` before incrementing (576);
`_linuxSkipToNext` does not.

**Fix:** capture the target into a local and only commit `_linuxIndex` *after* a
successful (non-skipped) load, or use a generation counter so a superseded load
can't leave a half-applied index.

---

## B. Shuffle logic

### [P1] SH-1 — Two divergent copies of all six shuffle algorithms
**Files:** `lib/services/navi_audio_handler.dart:19-181` (private `_xxxIsolate`)
vs `lib/services/shuffle_algorithms.dart` (public `xxxIsolate`, `@visibleForTesting`).
Production runs the handler's private copies; the public ones exist only for
tests. They already differ — `_standardShuffleIsolate` mutates in place (handler
line 30) while the public `standardShuffleIsolate` copies first (line 47). So
unit tests on `shuffle_algorithms.dart` don't exercise the code that ships.

**Fix:** delete the handler's private copies; have the handler import and
`compute()` the public functions from `shuffle_algorithms.dart`.

### [P2] SH-2 — Weighted-shuffle keys underflow to 0.0
**File:** `lib/services/navi_audio_handler.dart:127-137, 166-181`
(also mirrored in `shuffle_algorithms.dart`)
`exp(log(r)/w)` with `r` floored at `1e-10` and (recency-dampened) `w` as low as
`0.01` gives `exp(-2300) == 0.0`. Every low-weight / recently-played song
collapses to key `0.0` and sorts as a stable tie block in insertion order — i.e.
**not** randomized among themselves, defeating the point of recency dampening.

**Fix:** raise the `w` floor (e.g. `0.2`) or add a small random tiebreaker to the
sort.

### [P3] SH-3 — `'Unknown'` group key collides with a real genre named "Unknown"
**File:** `lib/services/navi_audio_handler.dart:50, 107` (and shuffle_algorithms.dart)
`ditheredPositionShuffleIsolate` / `mergeShuffleIsolate` bucket empty genre/composer
under the literal string `'Unknown'`, colliding with a genuine "Unknown" value.

**Fix:** use a sentinel that can't collide (e.g. a unique const token, or null-key map).

---

## C. Queue / AudioHandler

### [P1] QH-1 — Recency window is a `Set`; replays don't refresh recency
**File:** `lib/services/navi_audio_handler.dart:379`
```dart
_recentlyPlayedIds.add(songId);
if (_recentlyPlayedIds.length > _recencyWindow) {
  _recentlyPlayedIds.remove(_recentlyPlayedIds.first);
}
```
Re-playing an already-tracked song is a no-op for `add` (no reinsertion), and
`.first` evicts the oldest-**inserted**, not least-recently-**played**. The
recency-dampened shuffle then demotes the wrong songs.

**Fix:** remove-then-add into a `LinkedHashSet`, or use a bounded FIFO queue.

### [P1] QH-2 — `_linuxSkipToNext`/`Prev` use the wrong resume guard
**File:** `lib/services/navi_audio_handler.dart:618, 640, 669`
These use `if (player.playing) await player.play();`, while the completion path
uses the opposite `if (!player.playing) await player.play();` (601). Depending
on whether `setAudioSource` drops the play state, manual Next/Prev on Linux can
leave the new track loaded but paused. Confirm on-device; the asymmetry is a
smell.

**Fix:** make the resume condition consistent across all Linux load paths.

### [P2] QH-3 — Provider `addAllToQueue` ignores the handler's batch method
**File:** `lib/providers/player_provider.dart:887`
It loops `await _audioHandler.addToQueue(song)` (one `_playlist!.add` platform
call each) instead of calling the handler's `addAllToQueue`, which does a single
`_playlist!.addAll` (handler 779). N round-trips → 1.

**Fix:** call `_audioHandler.addAllToQueue(songs)` once.

### [P2] QH-4 — `NaviAudioHandler` never cancels its stream subscriptions
**File:** `lib/services/navi_audio_handler.dart` constructor (222–248) +
`_listenToPlayerEvents` (251). ~6 `.listen()` subscriptions are created but never
stored; `dispose()` (1091) only stops/disposes the player. Harmless for the
production singleton, but leaks listeners across hot-restart and in tests.

**Fix:** store subscriptions in a list and cancel them in `dispose()`.

### [P3] QH-5 — Autoplay auto-advance uses a stale length snapshot
**File:** `lib/providers/player_provider.dart:1497-1509`
`wasAtEnd`/`nextIndex` are computed from `queueLenBeforeFetch` captured before
the HTTP await; if the queue changed during the fetch, the seek can land on the
wrong index.

**Fix:** recompute the target index from current state after the await, or guard
with the queue lock (RC-1).

---

## D. Offline service

### [P1] OF-1 — `getLocalPath` does N×4 synchronous `existsSync()` on the UI thread
**File:** `lib/offline_service.dart:409`
`_precomputeOfflinePaths` (handler) calls `getLocalPath` for **every** song in
the queue, and each call does up to 4 `File(...).existsSync()` stat syscalls
(411–417). For a large queue this blocks the main isolate during
`setQueue`/reorder. (This is the documented BUG-007, still live on the hot path.)

**Fix:** list the offline dir once into an in-memory `Set<String>` of basenames
and look up there, instead of 4 stat calls per song. Refresh the set on
download/delete.

### [P2] OF-2 — Downloads are always saved as `.mp3` regardless of real format
**File:** `lib/offline_service.dart:70, 189`
`_getSongPath` hardcodes `.mp3`, so `downloadSong` writes FLAC/OGG/transcoded
streams into a `.mp3` filename. Then `getLocalPath` (409) probes
`flac/mp3/m4a/ogg` — those branches can never match a freshly downloaded file,
and `isSongDownloaded` (113) only checks `.mp3`. Playback usually survives
(content sniffing), but the extension lies and the two code paths disagree about
what "downloaded" means.

**Fix:** derive the extension from the stream's content-type / server suffix and
store the real format; make `isSongDownloaded` and `getLocalPath` agree.

---

## E. UI

### [P2] UI-1 — Mini player re-runs `PaletteGenerator` on every track, ignoring `PaletteCache`
**File:** `lib/widgets/mini_player.dart:19-35, 84-91`
`now_playing_screen` already extracts and stores palettes in
`PaletteCache.instance`, but the mini player decodes the artwork **again**
through `PaletteGenerator` for its own `_themeColor`. That's a redundant image
decode (and `CachedNetworkImageProvider` resolve) on every song change, on the
most omnipresent widget in the app.

**Fix:** read `PaletteCache.instance.getColorsFor(song.id)` first; fall back to
extraction only on a miss, and write the result back so both screens share one
extraction.

### [P2] UI-2 — `use_build_context_synchronously` in the palette helper
**File:** `lib/widgets/mini_player.dart:32-33`
`_extractMiniPalette` captures `context`, `await`s the generator, then reads
`ThemeTokens.of(context)` in the `catch`/fallback with no `mounted` check inside
the function. If the widget is disposed during the await, this touches a dead
context.

**Fix:** pass the resolved `accent` color in as a plain argument instead of the
`BuildContext`.

### [P3] UI-3 — Orphaned Hero
**File:** `lib/widgets/mini_player.dart:523`
`Hero(tag: 'now_playing_artwork')` has no counterpart on `NowPlayingScreen`
(grep finds only this one occurrence), so the tag does nothing and the slide-up
transition animates a lone Hero pointlessly.

**Fix:** either wire the destination artwork to the same tag for a real
shared-element transition, or drop the `Hero`.

---

## F. Smart Shuffle API client (audited vs `api_refernce.md` v4.0.0)

All 12 documented endpoints are wired. `/weather`, `/model/status`, the five
`/listening-log/*`, both `/predict/*`, and the `/feedback` body all match the
spec. Problems below.

### [P0] API-1 — Login accepts ANY credentials
**Files:** `lib/features/ai_shuffle/ui/smart_shuffle_login_screen.dart:59`,
`lib/features/ai_shuffle/data/services/shuffle_api_service.dart:362`
`_connect()` validates credentials by calling `getHealth()`. But
`_BasicAuthInterceptor.onRequest` deliberately skips the `Authorization` header
for `/health` (and `/weather`), and `/health` is a public no-auth endpoint that
returns `200` regardless of credentials. So a wrong username/password
"connects" successfully and gets persisted; the user only finds out later when
`/next` or `/model/status` 401s. The `getHealth()` docstring claims it sends
credentials to validate the connection — the interceptor makes that false.

**Fix:** validate against an authenticated endpoint — `getModelStatus()` is
ideal (per-user, 401s on bad creds). Keep `/health` for the no-auth liveness
check only.

### [P0] API-2 — `reshuffle` & `excluded_titles` aren't in the v4.0.0 spec
**File:** `lib/features/ai_shuffle/data/services/shuffle_api_service.dart:141-142`
The `/next` parameter table documents 11 params; neither `reshuffle` nor
`excluded_titles` is among them. The reshuffle feature
(`reshuffleActiveQueue` → `ShuffleQueueNotifier.reshuffle` →
`getNext(reshuffle:true, excludedTitles:...)`) depends entirely on the server
honoring `excluded_titles` to avoid repeating the current queue. If the deployed
server is the documented v4.0.0, both fields are silently ignored and reshuffle
can return songs already in the queue. `played_titles` only covers *played*
songs, not the upcoming-but-unplayed ones reshuffle also bans.

**Action:** confirm the server build actually supports these two fields. If not,
the feature is a no-op and needs a server-side change (or a different exclusion
mechanism). If it does, the reference is stale — update `api_refernce.md`.

### [P1] API-3 — Comma-joining `played_titles` / `candidates` corrupts titles with commas
**File:** `lib/features/ai_shuffle/data/services/shuffle_api_service.dart:135, 139`
`playedTitles.join(',')` and `candidates.join(',')`. Song titles can contain
commas, and the pipeline resolves server responses back to local songs by exact
title (`player_provider.dart:683-690`). A candidate title with a comma is split
server-side into two non-existent titles → that song is silently dropped. The
reference shows candidates with a **pipe** separator (`Song1|Song2|Song3`)
precisely because commas are unsafe. The param type is `string/array` and
`recent_listen_ratios` is already sent as a raw JSON array (line 137), so the
server accepts arrays in the POST body.

**Fix:** send `played_titles` and `candidates` as JSON arrays — no delimiter, no
corruption. Add a test for the array encoding.

### [P1] API-4 — Playlist mode never sends `playlist_id`
**File:** `lib/providers/player_provider.dart:1147-1148, 1595-1596`
The smart-local path calls `fetchNext(source: 'playlist', playlistName: ...)`
with no `playlist_id`. Per the reference, true playlist mode (server-side
restriction to a Navidrome playlist) is triggered by `playlist_id`;
`playlist_name` only "sets genre streak." So `source:'playlist'` with an empty
`playlist_id` isn't real playlist mode — it relies entirely on `candidates` to
constrain the song set, and the server may apply smart behavior for the rest of
the scoring.

**Fix:** either pass the real `playlist_id` and use server playlist mode, or use
`source:'smart'` + `candidates` and drop the pseudo-playlist branch.

### [P2] API-5 — `genre_streak_type` / `genre_streak_count` never populated on `/next`
**File:** `lib/providers/player_provider.dart` (all `fetchNext`/`reshuffle` calls)
Every call from the player omits these, so they always default to `''`/`0`. The
reference treats genre streak as a core smart-mode scoring signal (it's in the
POST example). It's sent on `/feedback` but never on `/next`, so the engine
can't use streak context when choosing the next batch.

**Fix:** track the current genre streak in `ShuffleQueueNotifier` and pass it
through to `getNext`.

### [P3] API-6 — Stale docstrings in the API client
**File:** `lib/features/ai_shuffle/data/services/shuffle_api_service.dart:7-17, 99`
The endpoint list comment (7–17) omits `/predict/*` and
`/listening-log/contribution-graph`, which are implemented right below. The
`getNext` docstring (99) lists `all_songs` but omits `candidates` — backwards
from actual usage. (`source:'all_songs'` and `source:'candidates'` are unused
capabilities; fine to leave, but document accurately.)

---

## G. Code-quality cleanups

### [P3] CQ-1 — Dead ternary
**File:** `lib/providers/player_provider.dart:1426`
`final newCurrentIndex = currentSong != null ? 0 : 0;` — both branches are `0`
(half-finished refactor). Replace with `= 0`.

### [P3] CQ-2 — Dead / no-op methods
**File:** `lib/providers/player_provider.dart:764` (`refreshShuffleUrl()` empty
body); `lib/services/navi_audio_handler.dart:882` (`spotifyDitherShuffle` is a
one-line alias for `ditheredPositionShuffle`). Remove or document intent.

### [P3] CQ-3 — Per-song debug loops run in release
**File:** `lib/services/navi_audio_handler.dart:440-442, 994-997` (and similar
loops in `player_provider.dart`). `debugPrint` is stripped in release, but the
`for` loop and string interpolation still execute on every `setQueue`/commit.

**Fix:** wrap the loops in `if (kDebugMode) { ... }`.

### [P3] CQ-4 — `PlayerState` index getters not bounds-symmetric
**File:** `lib/providers/player_provider.dart:72-77`
`currentSong`/`upNext` guard `currentIndex < queue.length` but not `>= 0`.
Defensive only, but cheap to make symmetric.

---

## Suggested order of attack

1. **API-1** (accepts wrong credentials — security/UX, ~5-line fix) and
   **API-2** (verify server, or reshuffle is broken).
2. **RC-1 + RC-2** (root cause of the recurring shuffle/queue desyncs that keep
   getting patched symptomatically). Convert suppression to a depth counter and
   put all mutations behind one lock helper.
3. **SH-1** (delete duplicate algorithms so tests cover shipping code).
4. **API-3** (arrays instead of comma-join — kills a class of title-match
   failures), **OF-1** (sync stat calls off the UI thread), **RC-4 / QH-1**
   (Linux desync + recency Set).
5. Remaining P2/P3 as cleanup.

> Process note: write a failing test first where practical (RC-2 suppression
> counter, SH-1 algorithm parity, API-3 array encoding, API-1 auth validation).
