# Dead, redundant and duplicate code audit

Scope: `lib/` (488 files), `test/` (206), `tool/`, `tools/`, root docs and `pubspec.yaml`.
Read-only: nothing was edited or committed. Branch `feature/search-online`.

## How this was checked

- `flutter analyze`: 0 unused-import / unused-element hints (7 `avoid_print` infos in `tool/` and one test). The analyzer never flags unused *public* symbols, so it can't find most of what follows.
- Three throwaway scripts (kept in the scratchpad, not the repo):
  1. every top-level class / function / const / provider in `lib/`, counted as a whole word across `lib`, `test`, `tool`, `integration_test` and `web` (comments stripped, `.g.dart` included, so generated code counts as a user);
  2. every class member (method / getter / field), same count;
  3. a normalised 8-line sliding window across `lib/` to find copy-pasted blocks.
- Import graph for orphan files; `pubspec.yaml` deps against `package:` imports; asset paths against `lib/`.
- Every item in "safe to delete now" was re-grepped as a whole word over `lib test tool integration_test web windows/runner android/app/src`. The only extra hits are the declaration, its own constructor, or a comment (noted per item).
- "Safe" means no code reference. Nothing here is reached by reflection or string lookup: Dart has none, and the provider names appear in no string.

Counts: 14 dead top-level symbols, ~45 dead members, 2 dead classes' worth of widgets, 4 dead doc/config files, 7 duplicate groups in `lib/`, and a large test-fake duplication (30 copies of one class).

---

# 1. Safe to delete now

Each item was grepped and has zero uses. Approx. line count is what the deletion removes. Risk is "none" unless stated.

## 1.1 Dead top-level symbols

| # | Where | What | Evidence |
|---|---|---|---|
| 1 | [lib/widgets/art/empty_art.dart:55-101](lib/widgets/art/empty_art.dart:55) | `ArtEmptyState` widget (47 lines) | Only its declaration and constructor match. `EmptyArt` / `EmptyArtPainter` in the same file are used; keep them. The doc comment ("the replacement for the old icon + grey line empty states") is satisfied by `lib/widgets/ui/states.dart`, which every screen calls. |
| 2 | [lib/widgets/ui/dock_ground.dart:57-98](lib/widgets/ui/dock_ground.dart:57) | `GroundPane` widget and `PaneSide` enum (40 lines) | `GroundPane` has no caller; `PaneSide` is only used inside it. `DockGround` (lines 1-10 of the same file) is live in 4 files; keep it. |
| 3 | [lib/core/focus/navi_focus.dart:24-27](lib/core/focus/navi_focus.dart:24) | `NaviContextIntent` | Declaration + const constructor only. No `Actions` map, shortcut or `Shortcuts` binding mentions it. |
| 4 | [lib/features/ai_shuffle/data/repositories/shuffle_exception.dart:45-51](lib/features/ai_shuffle/data/repositories/shuffle_exception.dart:45) | `ShuffleNotConfigured` | Never thrown or caught. Check no `switch` over the sealed-ish `ShuffleException` subtypes relies on exhaustiveness (grep shows none). |
| 5 | [lib/features/everyday/history_logic.dart:108-115](lib/features/everyday/history_logic.dart:108) | `sameDayPart()` | One match: its declaration. |
| 6 | [lib/features/play_outbox/logic/play_outbox_providers.dart:106-109](lib/features/play_outbox/logic/play_outbox_providers.dart:106) | `playOutboxPendingCountProvider` | One match: its declaration. (The status screen reads the outbox through `describePendingPlays`.) |
| 7 | [lib/providers/library_provider.dart:250-255](lib/providers/library_provider.dart:250) | `frequentAlbumsProvider` | Declaration only. A stale comment at [lib/services/subsonic_service.dart:450](lib/services/subsonic_service.dart:450) ("`frequentAlbumsProvider.keepAlive()` owns it") names it; delete or reword that comment in the same change. |
| 8 | [lib/providers/library_provider.dart:377-381](lib/providers/library_provider.dart:377) | `mirrorNewSong()` (singular) | Declaration + a doc-comment mention at line 383. `mirrorNewSongs` (plural) is the live one and stays. |
| 9 | [lib/widgets/app_scaffold.dart:58](lib/widgets/app_scaffold.dart:58) | `kContentMaxWidth = 1180` | Declaration only. |
| 10 | [lib/widgets/mascot/microduck_mesh.dart:152](lib/widgets/mascot/microduck_mesh.dart:152) | `kMatrixCount` | Declaration only. |

## 1.2 Dead members (methods / getters / fields)

| # | Where | What | Evidence / note |
|---|---|---|---|
| 11 | [lib/services/recommendation_service.dart:227-240, 308-350, 366-367](lib/services/recommendation_service.dart:227) | `getPersonalizedFeed`, `generateMixes`, `getRecommendedArtists`, `getRecommendedGenres` (~60 lines) | No callers anywhere. The service itself is live (play/skip tracking, `settings_screen.dart`), so delete only these methods. `_getTopArtists` / `_getTopGenres` stay (still used at lines 383-384); check any other private helper that only the deleted methods call (`flutter analyze` will flag those as unused once they are gone). This is the older on-device recommender that Smart Shuffle replaced. |
| 12 | [lib/offline_service.dart:460-519](lib/offline_service.dart:460) | `startBackgroundDownload`, `cancelBackgroundDownload`, getter `isBackgroundDownloadActive` (~60 lines) | Never called; downloads go through the `download_provider` / auto-download path. The `_isBackgroundDownloadActive` field is still read by `_downloadActive()` at line 167; after the delete it is always false, so remove the field and simplify that line to `downloadState.value.isDownloading`. |
| 13 | [lib/offline_service.dart:52](lib/offline_service.dart:52), [219-229](lib/offline_service.dart:219) | `setOfflineMode`, `getLocalLyrics` | No callers. |
| 14 | [lib/services/cache_settings_service.dart:60-86](lib/services/cache_settings_service.dart:60) | `disableAllCaches`, `enableAllCaches`, `areAllCachesDisabled`, `areAllCachesEnabled` | No callers. Also `initialize()` (line 10) is a documented no-op "kept for API compat"; its only caller is [settings_screen.dart:201](lib/screens/settings_screen.dart:201), so remove both together. |
| 15 | [lib/services/subsonic_service.dart:789-796, 920](lib/services/subsonic_service.dart:789) | `getAlbumsByGenre`, `invalidatePlayHistory()` (empty body, "retained for API compatibility") | No callers. |
| 16 | [lib/services/transcoding_service.dart:82, 191-195](lib/services/transcoding_service.dart:82) | `currentConnectionType`, `setConnectionType` | No callers. |
| 17 | [lib/providers/settings_provider.dart:329-332](lib/providers/settings_provider.dart:329) | `setDataCollectionEnabled` | No UI calls it. See §3.1: the flag it sets is still *read*, so this is a decision, not just a delete. Listed here only for the setter; do not delete without reading §3.1. |
| 18 | [lib/features/ai_shuffle/data/repositories/shuffle_repository.dart:30-38](lib/features/ai_shuffle/data/repositories/shuffle_repository.dart:30), [logic/recommendation_resolver.dart:28-32](lib/features/ai_shuffle/logic/recommendation_resolver.dart:28) | `getHealthOrNull`, `resolveAll` | No callers (`resolveAll` is named in a doc comment only). |
| 19 | [lib/features/local_library/logic/local_library_service.dart:317-321](lib/features/local_library/logic/local_library_service.dart:317), [updates/logic/update_service.dart:304-310](lib/features/updates/logic/update_service.dart:304), [auto_download/logic/auto_download_service.dart:62](lib/features/auto_download/logic/auto_download_service.dart:62), [local_library/logic/local_index.dart:51](lib/features/local_library/logic/local_index.dart:51), [smart_playlists/data/playlist_folders.dart:58](lib/features/smart_playlists/data/playlist_folders.dart:58) | `songById`, `cleanStaging`, `isRunning`, `hasLocalCover`, `playlistIdsIn` | One match each (the declaration). |
| 20 | [lib/widgets/mascot/mesh_builder.dart:126-138, 216-291, 330-356](lib/widgets/mascot/mesh_builder.dart:126) | `pixelText`, `dome`, `sphere`, `ellipsoid`, `torus` (~115 lines) | Declarations only (`ellipsoid` also appears in its own doc comment). The mascot mesh is built from other primitives. |
| 21 | [lib/utils/platform_utils.dart:92-152](lib/utils/platform_utils.dart:92) | `supportsKeyboardShortcuts`, `supportsMpris`, `supportsSelfUpdate`, `prefersPopupMenu`, `prefersCenteredDialogs`, `isWideScreen`, `homeDir` | One match each. `isWideScreen` and `supportsKeyboardShortcuts` are documented as aliases of `isDesktop`, which is the symbol callers use. |
| 22 | [lib/ai_shuffle models](lib/features/ai_shuffle/data/models/) | `ModelStatusResponse.builtAtFormatted` (:64), `PredictResponse.timeSlot` (:55), `.fallbackDescription` (:61), `.isHighConfidence` (:72), `RecommendedSong.isSecondOrder` (:85), `.legacyArtist` / `.legacyAlbum` (:154-155, commented "kept for display compatibility"), `.isColdStart` (:315) | One match each; no screen reads them. |
| 23 | [lib/core/layout/window_size.dart:29-30](lib/core/layout/window_size.dart:29) | `isCompact`, `isExpanded` | One match each. |
| 24 | [lib/core/album_palette.dart:83](lib/core/album_palette.dart:83), [lyrics/models/lyric_translation.dart:40-41](lib/lyrics/models/lyric_translation.dart:40), [models/download_state.dart:41](lib/models/download_state.dart:41), [social/data/social_models.dart:609](lib/features/social/data/social_models.dart:609), [providers/download_provider.dart:110](lib/providers/download_provider.dart:110), [providers/player_provider.dart:1175](lib/providers/player_provider.dart:1175), [services/mini_player.dart:186](lib/services/mini_player.dart:186) | `onVibrant`, `hasPronunciation`, `hasTranslation`, `isDownloaded`, `hasShared`, `progressOf`, `isShuffling`, `savedBounds` | One match each. |
| 25 | [lib/core/hive_boxes.dart:109, 121-122](lib/core/hive_boxes.dart:109) | `kLastTimestamp`, `kThemeMode`, `kMeshGradientEnabled` | Key constants nothing reads or writes. The literal strings `'theme_mode'` / `'mesh_gradient_enabled'` / `'lastTimestamp'` appear nowhere else in `lib`, so no stored value is orphaned in code. |

Removing #11, #12, #20 and #14 alone is ~330 lines.

## 1.3 Stale files / config (not Dart)

| # | File | Why |
|---|---|---|
| 26 | `graphify.json` (root, tracked) | A community-label dump from a code-graph tool (May 2026). 0 references anywhere (`grep -rIl graphify` outside the file: none). |
| 27 | `skills-lock.json` (root, tracked) | Lock file for the Flutter agent skills (Apr 2026). 0 references; nothing in CI or scripts reads it. |
| 28 | `SKILLS.md` (root, 756 lines) | A pasted agent skill ("flutter-production-build-and-audit"). 0 references; the real skill lives under `.claude/skills`. |
| 29 | `tools/shuffle-proposal-audit.md` | June 2026 one-off audit note. 0 references. |

Risk: none for the build. The owner may keep 26-28 deliberately as agent context; if so, move them under `docs/` rather than the repo root.

## 1.4 Unused pubspec dependencies

| # | Dependency | Evidence |
|---|---|---|
| 30 | `cupertino_icons` ([pubspec.yaml:37](pubspec.yaml:37)) | 0 uses of `CupertinoIcons` in `lib/`; icons come from `NaviGlyph` / `Ion`. |
| 31 | `audio_session` ([pubspec.yaml:15](pubspec.yaml:15)) | No `package:audio_session` import in `lib/` or `test/`. `just_audio` pulls it in transitively, so removing the direct line is safe; keep it only if a platform channel needs the pin. Run `flutter pub get` + `flutter build apk` once to confirm. |

Risk: low; confirm with a build. Not touched here: `media_kit_libs_*`, `sqlite3_flutter_libs`, `drift_dev`, `build_runner`, `flutter_launcher_icons`, which have no Dart imports by design (native libs / codegen / tooling).

---

# 2. Merge (duplicate implementations; the one to keep is named)

## 2.1 Byte / size formatting: four copies

| Copy | Behaviour |
|---|---|
| [lib/features/status/logic/status_model.dart:141](lib/features/status/logic/status_model.dart:141) `formatBytes` | `B`, `KB` (0 dp), `MB` (1 dp), `GB` (2 dp) |
| [lib/offline_service.dart:286](lib/offline_service.dart:286) `OfflineService.formatSize` | same, but `KB` at 1 dp |
| [lib/features/updates/ui/updates_screen.dart:13](lib/features/updates/ui/updates_screen.dart:13) `formatUpdateSize` | `KB` (ceil) / `MB` (1 dp) |
| [lib/features/exportify_import/data/exportify_models.dart:267](lib/features/exportify_import/data/exportify_models.dart:267) `formatGb` | `GB` only |

Keep: `formatBytes`, moved into [lib/utils/format.dart](lib/utils/format.dart) (which already holds `formatLongDuration`, `compactCount`, `songCount`). Delete `OfflineService.formatSize` (its ~6 callers switch to the function) and `formatUpdateSize`. The KB rounding differs by design in `formatUpdateSize` ("1.4 MB" for a patch), so either keep it as a thin wrapper or accept `ceil`. `formatGb` is a different unit; leave it. `formatSpeed` in `status_model.dart` stays (it calls `formatBytes`).
Risk: low. Goldens that print sizes may shift by one rounding step; re-run goldens.

## 2.2 Mm:ss duration formatting: five copies

[lib/utils/format.dart:12](lib/utils/format.dart:12) `formatTrackDuration(int seconds)` is the canonical one. Re-implemented inline in:
- [lib/features/library_extras/data/duplicates.dart:75](lib/features/library_extras/data/duplicates.dart:75) `_mmss`
- [lib/features/social/ui/jam/jam_desktop.dart:266](lib/features/social/ui/jam/jam_desktop.dart:266) `_time` (same, but returns `''` for ≤ 0)
- [lib/player/sleep_timer.dart:104](lib/player/sleep_timer.dart:104) (`m:ss` of a `Duration`)
- [lib/lyrics/services/lyrics_repository.dart:277-278](lib/lyrics/services/lyrics_repository.dart:277) (`mm:ss`, zero-padded minutes: an LRC tag, not the same format, leave)
- [lib/player/player_controls.dart:24](lib/player/player_controls.dart:24) `formatClock(Duration)` (adds `h:mm:ss`): keep as the `Duration` variant, but have `formatTrackDuration` delegate to it so there is one padLeft implementation.

Action: replace `_mmss` and `_time` with `formatTrackDuration`; point `sleep_timer.dart` at `formatClock`. Risk: low.

## 2.3 "x ago" strings: two copies

[lib/features/social/logic/social_rules.dart:64](lib/features/social/logic/social_rules.dart:64) `agoText(int seconds)` and [status_model.dart:131](lib/features/status/logic/status_model.dart:131) `formatAgo(DateTime?, DateTime)` produce "just now / N min ago / N hr ago / N d ago" with slightly different wording ("hr" vs "h", 5 s vs 60 s thresholds). Keep one in `utils/format.dart` taking a `Duration`; both call sites pass their own difference. Risk: low, but social tests assert the exact strings, so settle the wording first.

## 2.4 Text normalisation for matching: three variants

- [duplicates.dart:11](lib/features/library_extras/data/duplicates.dart:11) `normalizeName` / `normalizeArtist` (accent folding table, `&` to `and`, strip punctuation)
- [matcher.dart:20](lib/features/local_library/logic/matcher.dart:20) `normalizeForMatch` (a second accent table, strips `(feat …)`/`[remix]`)
- [library_provider.dart:42](lib/providers/library_provider.dart:42) `_artistKey` (`trim().toLowerCase()`)

Keep one `foldAccents()` in `utils/` used by the first two; leave the feature-specific suffix stripping where it is. Two separate accent tables will drift (they already differ: one lists `ł`, `ø`, `š`, the other doesn't). Risk: medium, because matching results change if the tables are unified; add tests first (both have tests).

## 2.5 `Dio` error mapping in API clients: seven copies

Each of these has its own `_wrap<T>()` that maps `DioException` status codes to the same user strings ("Can’t reach the server. Check your connection.", "Sign in again…", "still starting up…") and its own `…Exception` class:
[listen_api.dart:140](lib/features/listen/data/listen_api.dart:140), [rotation_api.dart:47](lib/features/rotation/data/rotation_api.dart:47) (already imports `ListenException` from listen), [trending_api.dart:34](lib/features/trending/data/trending_api.dart:34), [recognize_api.dart:45](lib/features/recognize/data/recognize_api.dart:45), [social_api.dart:261](lib/features/social/data/social_api.dart:261), [lyrics_server_api.dart:137](lib/lyrics/services/lyrics_server_api.dart:137), [online_fetch_api.dart:160](lib/features/online_fetch/data/online_fetch_api.dart:160) (this one already delegates to `guardFetchCall`), plus [shuffle_api_service.dart:478](lib/features/ai_shuffle/data/services/shuffle_api_service.dart:478). Also 11 separate `*Exception implements Exception` classes with a single `message` field.

Keep: one `guardDio<T>(call, {String Function(int? status)? messageFor})` in `lib/core/` plus a shared `ServerMessageException`; each API passes only its differing strings. Alternatively reuse the `AppException` hierarchy in [lib/core/app_exception.dart](lib/core/app_exception.dart), which today is used for Subsonic calls only. Risk: medium (many call sites catch the specific exception type); do it one API at a time.

## 2.6 Hover icon button: two implementations

[lib/widgets/ui/navi_icon_button.dart](lib/widgets/ui/navi_icon_button.dart) (`NaviIconButton`, 9 call sites) and the private `_BarButton` / `_BarButtonState` in [lib/widgets/shell/desktop/top_bar.dart:118](lib/widgets/shell/desktop/top_bar.dart:118) share ~9 duplicated lines of hover/press/semantics logic. Keep `NaviIconButton`; let `top_bar.dart` use it (add a `size`/`hoverFill` parameter if its look differs). Risk: low-medium: the desktop top bar has golden tests.

## 2.7 Online search: page and sheet

[online_search_page.dart](lib/features/online_fetch/ui/online_search_page.dart) (166 lines, desktop page) and `_OnlineSearchSheetState` in [online_search_sheet.dart](lib/features/online_fetch/ui/online_search_sheet.dart) (phone sheet) share ~20 duplicated lines (query state, `_play`, `_searchAnyway`, `_setType`) around the already-shared `OnlineSearchBody`. Move the state and handlers into one `OnlineSearchController` (or a mixin) so each shell is only layout. Both are live (`navigateInApp(... OnlineSearchPage ...)` at sheet:40). Note: the `redesign-search-online-s` session is working on this area; do the merge after it lands. Risk: medium.

## 2.8 Near-twin screens

- [blend_screens.dart](lib/features/social/ui/blend_screens.dart) (273 lines) vs [collab_screens.dart](lib/features/social/ui/collab_screens.dart) (622 lines): each has Section / Row / Screen / Body with ~10 overlapping lines (header, row layout, empty state). Extract a shared `SharedPlaylistRow` and section scaffold.
- [jam_desktop.dart](lib/features/social/ui/jam/jam_desktop.dart) `_QueuePane` / `_Row` vs [jam_room.dart](lib/features/social/ui/jam/jam_room.dart) `JamQueueRow` / `JamMemberRow`: same row anatomy on two layouts (8 duplicated lines + the `_time` helper above).
- [rule_editor_screen.dart](lib/features/smart_playlists/ui/rule_editor_screen.dart) vs [playlist_editor.dart](lib/screens/playlist_editor.dart): 9 duplicated lines (name field, save/discard bar).
- [shuffle_repository.dart](lib/features/ai_shuffle/data/repositories/shuffle_repository.dart) is a 225-line pass-through over [shuffle_api_service.dart](lib/features/ai_shuffle/data/services/shuffle_api_service.dart): most methods are `=> _api.x()` with a `try/catch` that only logs. Keep the repository only if tests rely on faking it (they do: `ReversingShuffleRepository`, three `Mock/_FakeRepo`); otherwise fold into the service.

Risk: medium each; none are urgent.

## 2.9 Cover images: one place bypasses the widget

[lib/widgets/cover_art.dart](lib/widgets/cover_art.dart) `CoverArt` (56 call sites) is the documented single path. Still using raw `CachedNetworkImage` directly: [features/month/ui/story/story_cards.dart](lib/features/month/ui/story/story_cards.dart) (`StoryCover`) and [screens/replay/year_story.dart](lib/screens/replay/year_story.dart). `CoverImage` ([player/artwork.dart](lib/player/artwork.dart), 11 uses) and `FullBleedCover` are a deliberate second path for the player (gapless, no flicker), not a duplicate. Switch the two story files to `CoverArt` (or `CoverImage`) so cache keys and the size ladder (`kCoverSteps`) apply. Risk: low.

## 2.10 Test fakes: the largest duplication in the repo

`test/` defines `_FakeSubsonic` in **30 files** (`class _FakeSubsonic extends Fake implements SubsonicService`), `_FakeSettings` in 20, `_FakePlayer` in 20, `MockSubsonicService` in 17, `MockPlaylistCacheService` in 13, `MockListeningEventCollector` in 10. Only four shared helpers exist ([test/helpers/](test/helpers/): `fake_http`, `fake_queue_sync`, `reversing_shuffle_repository`, `test_utils`). Move one configurable `FakeSubsonic` (cover URL, a `songs` map, an `albums` list) and `FakeSettings` into `test/helpers/fakes.dart` and delete the copies: roughly 1,000+ lines. Risk: low per file; do it incrementally, running the suite after each batch. Several copies are 1-line `{}` bodies (e.g. [online_search_goldens_test.dart:45](test/goldens/online_search_goldens_test.dart:45)) and can use the shared one unchanged.

---

# 3. Needs a decision

## 3.1 `dataCollectionEnabled`: read but can no longer be changed

[player_provider.dart:1226](lib/providers/player_provider.dart:1226) gates play counting on `settings.dataCollectionEnabled`; [settings_provider.dart:111-186, 257](lib/providers/settings_provider.dart:111) loads and stores it; but nothing calls `setDataCollectionEnabled` (§1.2 #17), and the settings UI has no toggle. So it is always `true` unless an old install already stored `false` in Hive (then counting stays off with no way to turn it back on).
Decide: (a) remove the flag, the key `kDataCollectionEnabled`, its Hive migration entry ([hive_boxes.dart:189-191](lib/core/hive_boxes.dart:189)) and the `&& _counting` check's first half; or (b) restore the toggle. Option (a) needs a one-time reset of any stored `false`.

## 3.2 `riverpod_lint` / `custom_lint` configured but not active

[pubspec.yaml:90-91](pubspec.yaml:90) lists both, and the CI comments ([ci.yml:31](.github/workflows/ci.yml:31)) pin the Flutter version because of them, but [analysis_options.yaml](analysis_options.yaml) has no `analyzer: plugins: - custom_lint` and CI runs only `flutter analyze lib`, never `dart run custom_lint`. They do nothing today and constrain the Flutter version. Either enable them in CI or drop both.

## 3.3 Test-only public API in `lib/`

Kept alive only by tests: `pruneMissingForTest` ([library_provider.dart:167](lib/providers/library_provider.dart:167)), `answerForTest` ([chat_controller.dart:273](lib/widgets/mascot/chat/chat_controller.dart:273)), `sortByPlayStats`, `directorySize`, `MemoryFolderStore`, `isCollabOfOthers`, `movedTo`, `danceBeats` (each referenced once in `lib/`, by its own declaration, and by one test). Fine as seams, but they are production code kept for tests. Decide whether to keep as `@visibleForTesting` (recommended: annotate them) or move into test helpers. There are about 250 other public symbols used only from their own file plus tests (mostly provider / backend seams, e.g. `HiveFolderStore`, `recapClockProvider`); those are normal DI seams and not worth touching.

## 3.4 Two-name APIs kept "for compatibility"

Parameters that no caller needs but whose signature is mocked in tests:
- `ScrobbleService.submit(..., {Song? song})` ([scrobble_service.dart:69](lib/services/scrobble_service.dart:69), doc says "no longer used"); the only live caller passes it ([player_provider.dart:1575](lib/providers/player_provider.dart:1575)) and `test/scrobble_test.dart` mocks it with `song: any(named: 'song')`. Remove together with the test matchers.
- `NowPlayingScreen.initialImageUrl` ([now_playing_screen.dart:173-176](lib/screens/now_playing_screen.dart:173)): "Kept for call-site compatibility"; nobody passes it. Safe to remove; listed here only because the constructor is public API for the TV shell.
- `SongTile.onLongPress` ([song_tile.dart:49](lib/widgets/song_tile.dart:49)): used by the widget (line 86), but no call site of the 14 passes it; confirm before removing.

## 3.5 Stale reports and docs

| File | Observation |
|---|---|
| `QUEUE_INVESTIGATION_REPORT.md` (root, 204 lines, Aug 2026), `SMART_SHUFFLE_QUEUE_AUDIT_REPORT.md` (root, 173 lines, Sep 2026) | Point-in-time investigations, 0 inbound references. If the fixes shipped, move to `docs/archive/` or delete. |
| `api_refernce.md` (root, 869 lines; note the typo) | Documents the Smart Shuffle server API "v4.0.0"; referenced from 1 file. Dated June 2026 while `shuffle_api_service.dart` has since gained methods (`getCatalog`, `getIdMap`, `getPlaylistSuggestions`); not diffed line by line, so check before trusting it. Rename to `docs/` and reconcile, or delete. |
| `lib/services/context.md` (Oct 2026) | A "deep-dive developer context" doc living inside `lib/`; 0 references, emoji-heavy, overlaps `DESIGN.md` / `README.md`. Move to `docs/` or delete. |
| `docs/PLAN_NEXT.md`, `docs/TODO.md` | Planning docs; confirm they are still the live plan. |
| `docs/failed-songs-2026-11-16.csv`, `322` (root, an untracked file with a numeric name), `.impeccable/critique/*.md` | Untracked scratch files. Delete or ignore; never commit `322`. |
| [window_manager_service.dart:11-25](lib/services/window_manager_service.dart:11) | A commented usage example in the header ("call attach() in initState…"). Check it against how `main.dart` actually attaches it, or drop the block; it is the only commented-out code block in `lib/` (plus a 2-line example in [platform_utils.dart:15-16](lib/utils/platform_utils.dart:15)). |

## 3.6 `tools/` vs `tool/`, and the server snapshots

- Two script directories: `tool/` (release helpers used by CI, `export_listens.py`, `update_size_report.dart`, `make_release_local.ps1`) and `tools/` (`release.sh`, `session_sim/run_sim.py`, an audit note). `tools/release.sh` (June 2026) is a pre-release script superseded by `tool/make_release_local.ps1` and the GitHub workflow ([RELEASING.md](docs/RELEASING.md) names only the latter); its only inbound reference is itself. `tools/session_sim/run_sim.py` is referenced by `docs/SESSION_SYNC.md:139`. Fold both into `tool/` and delete `tools/release.sh` if the workflow replaced it.
- `tool/server/` holds 17 versioned server drop-ins (51 files: `album-overnight-v1`, `lyrics-v1` / `v2` / `v3`, `moods-v1` / `v2`, …). Superseded versions (`lyrics-v1`, `lyrics-v2`, `moods-v1`, `exportify-v1`?) may no longer match what runs on the server. Needs the owner to say which versions are deployed; the app-side audit cannot tell.
- `export/` is git-ignored, so not a repo problem (it is just a local scratch folder with `web-server-v2`).

## 3.7 `ThemeTokens` colour constants

[theme.dart:305-309](lib/core/theme.dart:305): `systemOrange`, `systemYellow`, `systemGray`, `systemGray2` are never read as `ThemeTokens.systemX`; the same hex values are inlined (`gold`, `warning`) with the name in a trailing comment. Either use the constants where the hex is inlined or delete them. Cosmetic.

## 3.8 Feature flags

No flag found that is "on forever or off forever" in `lib/`, other than `dataCollectionEnabled` (§3.1). `BuildFlavor` ([build_flavor.dart](lib/core/build_flavor.dart)) is read in several places and is in use. No `TODO` / `FIXME` / `HACK` comments exist in `lib/` (count 0), and there is no `@Deprecated` code.

---

# 4. Verified clean

- No unused imports (analyzer) and no unused private members (analyzer) in `lib/`.
- No orphan files in `lib/`: the three files with no direct importer (`web_storage_web.dart`, `windows_smtc_sink_io.dart`, `web_env_web.dart`) are conditional-import targets (`if (dart.library.…)`) and are live. `lib/core/navigation_transitions.dart`, flagged by an older note, no longer exists.
- Assets: every file under `assets/icons/` is used (`ai`, `analytics`, `books` via `illustration:`; `trend` directly), as are `assets/tray/tray.ico`, the shader, and the Inter fonts. `assets/images/logo.png` is **not** declared in `pubspec.yaml` and nothing references it, so it is never bundled: delete the file (safe, 0 references; ~size not measured).
- All 108 `NaviGlyph` values are referenced outside their own file.
- `.github/workflows/*` reference only `tool/release/*` scripts that exist.

# Suggested order

1. §1.1-1.4 in one commit (~600 lines of source gone, no behaviour change); run `flutter analyze` + the suite.
2. §2.10 test fakes (biggest line count, safest), then §2.1-2.3 formatters.
3. §3.1 and §3.2 decisions, then §2.5 (Dio guard).
4. §2.7 after the search-online redesign lands.
