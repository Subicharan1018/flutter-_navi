# Peak moments — design note (2026-11-22)

Three features, one data model: **saved moments** (mark "the best part"),
the **highlight reel** (play only the marked parts), and **best listening
moments** (what history says were your peaks).

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Where do marks live? | Hive `prefs` box, one JSON string `peakMarks_v1`, song id → list of marks. | Same pattern as `songTrims_v1` (R9). The data is tiny (tens to hundreds of marks), read once at start and written on change. Drift would need a schema bump + codegen for no query we need. Never touches `SubsonicService`. |
| Shape of a mark | `{id (uuid-ish), startMs, lengthMs (default 20 000), createdAt, updatedAt, deletedAt?}` | Stable `id` + `updatedAt` + tombstone `deletedAt` = last-writer-wins per mark, so a later sync can merge two devices without a schema change. Tombstones are pruned after 90 days. |
| Tap behaviour | Tap = mark at the current second. Tap again while inside a mark = unmark it. Long-press = unmark the mark under the playhead (or the nearest). | The owner's spec; one control. A tap in the first 2 s of an existing mark still unmarks (second tap), so double-tapping never stacks marks. |
| Overlap | Marks on one song may not overlap: a new mark that would overlap is clamped to start where the previous ends; marks shorter than 5 s or past the song are dropped by `normalized`. Min length 5 s, max 90 s, default 20 s (shortened to fit the song). | Back-to-back playback needs disjoint segments. |
| Adjusting length | Marks draw as bands on the Now Playing scrubber; each band has an end handle you drag. Start is moved by unmarking and re-marking. | Dragging both edges on a 6 pt track is fiddly on a phone; the end handle covers "how long is the best part". |
| Reel playback | Uses the existing player: the queue becomes one entry per segment (a song with two marks appears twice, in order). A pure `SegmentGuard` (modelled on `TrimGuard`) watches the position stream: on a segment's song start it seeks to the start; at the end it advances with `skipToNext`. A one-shot timer fires for the last 250 ms so the cut lands on the end ms, not the next 200 ms tick. | No new audio path, no change to `NaviAudioHandler`, queue/shuffle/history code unchanged. The reel is an overlay: any queue edit that moves entries (index no longer holds the segment's song), or starting another queue, ends reel mode and normal behaviour resumes. Song trims are ignored while a reel is active. |
| Gapless? | "Where possible": next segment's song is pre-buffered by the existing source, but the seek to its start happens after it starts, so a segment that starts mid-song can leak up to ~one position tick (≈0.2 s) of the song's intro. Truly gapless would need `ClippingAudioSource` per segment inside `NaviAudioHandler` (and a different path on the Windows single-source bridge); judged too invasive for this change. Reported, not hidden. | |
| Reel scopes | A song, a playlist, an album, all songs with marks. Order: the source's order (album/playlist order; all-marks screen: most recently marked first). Shuffle available on the all-marks screen. | |
| Auto-suggested peaks | **Loudest stretch: left out** — it needs decoding audio or a server waveform, neither exists here, and a guess would be dishonest. **Most-replayed stretch: included, opt-in** — it is the seek log below, already collected for feature 3; a song without marks gets a suggested segment only if ≥ 2 scrub-backs landed in the same 20 s window. Off by default. | Cheap and honest: it is the user's own behaviour, not an invented signal. |
| Where does "replayed / scrubbed back" come from? | Nothing records seeks today (`play_events` has only a loop count). New: a device-local **seek log** in Hive (`seekLog_v1`), capped at 1 000 newest entries: `{songId, toMs, fromMs, at}` for backward seeks > 3 s made by the user on the Now Playing scrubber, plus loop restarts are not counted (already in `repeat_count`). Hotspots = seeks bucketed to 10 s. | The only honest source. History before this build has no seek data, so the first weeks are empty — the screen says so. |
| Most-played days, longest sessions | Computed from the local `play_events` table with two `GROUP BY` queries (day via `ts_start`, session via `session_id`). | Data already exists; no server. |
| Where is it in the UI? | Home: "Highlights" feature card (Top Picks). Highlights screen (all songs with marks, Play / Shuffle, suggested-peaks switch, link to Best moments). Song options menu and Now Playing: mark button (`PeakMarkButton`, sits beside the scrubber). Album and playlist pages: "Play highlights" in the overflow sheet. Best moments screen reached from Highlights. | Phone, Windows share the same widgets; the Windows layout is the wide `ArtworkPage`. |
| States | Both screens: loading skeleton / error with retry / empty invitation / data. | Four-state rule. |

## Files

`lib/features/peak_moments/`: `data/peak_mark.dart` (model, JSON, normalise,
merge), `data/peak_store.dart` (backend + notifiers), `logic/reel.dart`
(segments, builders, `SegmentGuard`), `logic/best_moments.dart` (hotspots,
days, sessions), `ui/…` (button, scrubber overlay, Highlights screen, Best
moments screen, Home card art).

## Not verified on a device

Audio behaviour of the reel (cut accuracy, the seek leak at segment start),
haptics, and the drag handle on a real touchscreen. Unit tests cover the
guard and segment logic with simulated position ticks; goldens cover layout.
