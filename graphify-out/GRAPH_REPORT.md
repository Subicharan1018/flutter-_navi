# Graph Report - flutter-_navi  (2026-05-14)

## Corpus Check
- 162 files · ~270,408 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1548 nodes · 2768 edges · 107 communities (98 shown, 9 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7080a2bf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Now Playing & Queue UI|Now Playing & Queue UI]]
- [[_COMMUNITY_Replay & New Releases Screens|Replay & New Releases Screens]]
- [[_COMMUNITY_Library & Favorites Screens|Library & Favorites Screens]]
- [[_COMMUNITY_Home & Made For You Screens|Home & Made For You Screens]]
- [[_COMMUNITY_Made For You Detail Screen|Made For You Detail Screen]]
- [[_COMMUNITY_Playlist Detail Screen|Playlist Detail Screen]]
- [[_COMMUNITY_Song Picker Screen|Song Picker Screen]]
- [[_COMMUNITY_Settings Screen|Settings Screen]]
- [[_COMMUNITY_Made For You Widgets|Made For You Widgets]]
- [[_COMMUNITY_Listening Stats Screen|Listening Stats Screen]]
- [[_COMMUNITY_Playlist Header Widgets|Playlist Header Widgets]]
- [[_COMMUNITY_Made For You Playlist Details|Made For You Playlist Details]]
- [[_COMMUNITY_Player Provider & Controls|Player Provider & Controls]]
- [[_COMMUNITY_Library & Playlist Providers|Library & Playlist Providers]]
- [[_COMMUNITY_Settings Provider|Settings Provider]]
- [[_COMMUNITY_Download Provider & State|Download Provider & State]]
- [[_COMMUNITY_Listening Stats Provider|Listening Stats Provider]]
- [[_COMMUNITY_Search Provider & History|Search Provider & History]]
- [[_COMMUNITY_Replay Provider|Replay Provider]]
- [[_COMMUNITY_Audio Handler & Core Logic|Audio Handler & Core Logic]]
- [[_COMMUNITY_Subsonic Service & API|Subsonic Service & API]]
- [[_COMMUNITY_Recommendation Service|Recommendation Service]]
- [[_COMMUNITY_Playlist Cache Service|Playlist Cache Service]]
- [[_COMMUNITY_Listening Event Collector|Listening Event Collector]]
- [[_COMMUNITY_Scrobble Service|Scrobble Service]]
- [[_COMMUNITY_Search History Service|Search History Service]]
- [[_COMMUNITY_BPM Analyzer Service|BPM Analyzer Service]]
- [[_COMMUNITY_Cache Settings Service|Cache Settings Service]]
- [[_COMMUNITY_Replay Gain Service|Replay Gain Service]]
- [[_COMMUNITY_Transcoding Service|Transcoding Service]]
- [[_COMMUNITY_Replay Upload Service|Replay Upload Service]]
- [[_COMMUNITY_Listening Log Service|Listening Log Service]]
- [[_COMMUNITY_Shuffle Algorithms|Shuffle Algorithms]]
- [[_COMMUNITY_AI Shuffle Features|AI Shuffle Features]]
- [[_COMMUNITY_UI Dialogs|UI Dialogs]]
- [[_COMMUNITY_UI Widgets (SongAlbum)|UI Widgets (Song/Album)]]
- [[_COMMUNITY_App Scaffold & Navigation|App Scaffold & Navigation]]
- [[_COMMUNITY_Core Constants & Exceptions|Core Constants & Exceptions]]
- [[_COMMUNITY_Hive Database & Migration|Hive Database & Migration]]
- [[_COMMUNITY_App Database (Drift)|App Database (Drift)]]
- [[_COMMUNITY_Core Themes & Transitions|Core Themes & Transitions]]
- [[_COMMUNITY_Palette Cache|Palette Cache]]
- [[_COMMUNITY_Device Utilities|Device Utilities]]
- [[_COMMUNITY_Android Entry Point|Android Entry Point]]
- [[_COMMUNITY_Linux Entry Point|Linux Entry Point]]
- [[_COMMUNITY_AI Shuffle Data Models|AI Shuffle Data Models]]
- [[_COMMUNITY_AI Shuffle UI Components|AI Shuffle UI Components]]
- [[_COMMUNITY_Replay Screen Tests|Replay Screen Tests]]
- [[_COMMUNITY_Event Collector Tests|Event Collector Tests]]
- [[_COMMUNITY_Hive Storage & Security|Hive Storage & Security]]
- [[_COMMUNITY_Core Exception Classes|Core Exception Classes]]
- [[_COMMUNITY_App Database Schema|App Database Schema]]
- [[_COMMUNITY_Navigation Animations|Navigation Animations]]
- [[_COMMUNITY_Core Utility Tests|Core Utility Tests]]
- [[_COMMUNITY_Architecture Design Context|Architecture Design Context]]
- [[_COMMUNITY_Listening Stats Models|Listening Stats Models]]
- [[_COMMUNITY_AI Shuffle Repositories|AI Shuffle Repositories]]
- [[_COMMUNITY_Palette Cache Logic|Palette Cache Logic]]
- [[_COMMUNITY_Analytics Tables|Analytics Tables]]
- [[_COMMUNITY_Service Layer Rationale|Service Layer Rationale]]
- [[_COMMUNITY_Layered Architecture Rationale|Layered Architecture Rationale]]
- [[_COMMUNITY_Knowledge Graph Rules|Knowledge Graph Rules]]
- [[_COMMUNITY_Shuffle Logic & Settings|Shuffle Logic & Settings]]
- [[_COMMUNITY_Player Notifier Bug Analysis|Player Notifier Bug Analysis]]
- [[_COMMUNITY_Offline Download Logic|Offline Download Logic]]
- [[_COMMUNITY_Subsonic Service Security Audit|Subsonic Service Security Audit]]
- [[_COMMUNITY_Search State Management|Search State Management]]
- [[_COMMUNITY_Widget Rendering Tests|Widget Rendering Tests]]
- [[_COMMUNITY_UI Component Rationales|UI Component Rationales]]
- [[_COMMUNITY_AI Shuffle Service Logic|AI Shuffle Service Logic]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]

## God Nodes (most connected - your core abstractions)
1. `package:flutter_riverpod/flutter_riverpod.dart` - 68 edges
2. `package:flutter/material.dart` - 63 edges
3. `replay_screen.dart` - 52 edges
4. `playlist_details_screen.dart` - 52 edges
5. `listening_stats_screen.dart` - 44 edges
6. `../../providers/settings_provider.dart` - 43 edges
7. `../../models/song.dart` - 43 edges
8. `subsonic_service.dart` - 42 edges
9. `../../../core/theme.dart` - 41 edges
10. `settings_screen.dart` - 40 edges

## Surprising Connections (you probably didn't know these)
- `replay_screen.dart` --defines--> `_buildTestApp`  [EXTRACTED]
  lib/screens/home_screen.dart → test/replay_screen_test.dart
- `replay_screen.dart` --defines--> `ProviderScope`  [EXTRACTED]
  lib/screens/home_screen.dart → test/widget_test.dart
- `replay_screen.dart` --defines--> `main()`  [EXTRACTED]
  lib/screens/home_screen.dart → linux/runner/main.cc
- `main()` --calls--> `my_application_new()`  [INFERRED]
  linux/runner/main.cc → linux/runner/my_application.cc
- `favorites_screen.dart` --defines--> `AlbumCard`  [EXTRACTED]
  lib/screens/home_screen.dart → lib/widgets/album_card.dart

## Communities (107 total, 9 thin omitted)

### Community 0 - "Now Playing & Queue UI"
Cohesion: 0.05
Nodes (57): dart:ffi, dart:io, copyWith, SongDownloadState, copyWith, SongPair, cancelBackgroundDownload, copyWith (+49 more)

### Community 1 - "Replay & New Releases Screens"
Cohesion: 0.04
Nodes (54): ../core/palette_cache.dart, _AppleMusicThumb, _AudioQualityStrip, _BottomAction, build, Center, Container, Dismissible (+46 more)

### Community 2 - "Library & Favorites Screens"
Cohesion: 0.06
Nodes (46): _parseInt, ProfileResponse, _parseInt, SessionStatusResponse, _parseInt, ShuffleStatsResponse, AlbumStat, ArtistStat (+38 more)

### Community 3 - "Home & Made For You Screens"
Cohesion: 0.05
Nodes (43): ../../data/models/health_response.dart, ../data/models/profile_response.dart, ../../data/models/recommended_song.dart, ../data/models/session_status_response.dart, ../data/models/stats_response.dart, ../data/repositories/shuffle_exception.dart, ../data/repositories/shuffle_repository.dart, ../data/services/shuffle_api_service.dart (+35 more)

### Community 4 - "Made For You Detail Screen"
Cohesion: 0.06
Nodes (45): ../core/app_exception.dart, AppException, AuthException, NetworkException, ServerException, SubsonicApiException, TimeoutException, toString (+37 more)

### Community 5 - "Playlist Detail Screen"
Cohesion: 0.07
Nodes (40): add_to_playlist_dialog.dart, ../../../core/theme.dart, build, dispose, EditPlaylistScreen, _EditPlaylistScreenState, initState, Scaffold (+32 more)

### Community 6 - "Song Picker Screen"
Cohesion: 0.05
Nodes (40): ArtistAffinityCompanion, ArtistAffinityEntity, copyWith, copyWithCompanion, Function, GenreAffinityCompanion, GenreAffinityEntity, map (+32 more)

### Community 7 - "Settings Screen"
Cohesion: 0.08
Nodes (36): _AddSongsRow, build, _CircleIconButton, ClipRRect, _CollapsedTitle, _confirmDeletePlaylist, Container, _DismissBackground (+28 more)

### Community 8 - "Made For You Widgets"
Cohesion: 0.08
Nodes (33): Function, DownloadStateNotifier, OfflineService, _performDownload, progressOf, _set, _setFailed, statusOf (+25 more)

### Community 9 - "Listening Stats Screen"
Cohesion: 0.06
Nodes (35): 1. Presentation Layer (`lib/screens`, `lib/widgets`), 2. State Management Layer (`lib/providers`), 3. Service Layer (`lib/services`), 4. Data Layer (`lib/database`, `lib/models`), A. Music Playback Flow, 🧠 Advanced Shuffle Algorithms, 🔊 Audio Engine Details, 🔊 Audio Engine & Shuffle Intelligence (+27 more)

### Community 10 - "Playlist Header Widgets"
Cohesion: 0.08
Nodes (32): Playlist, _artPlaceholder, build, Container, CustomScrollView, _DailyListeningChart, _DashedLine, dispose (+24 more)

### Community 11 - "Made For You Playlist Details"
Cohesion: 0.06
Nodes (33): AudioHandler Performance, BUG 1: `_trackChangeTimer` Empty Callback ✅ (Approved), BUG 2: `_playedDuration` Drift & Scrobble Logic ⚠️ (Reworked), BUG 3: Shuffle Rebuild Performance ⚠️ (Reworked — Simplified), BUG 4: `applyShuffleAlgorithm` Sets Stale `currentIndex` ✅ (Approved), BUG 5: `_persistState` Timer Fires Multiple Times Per 5s Boundary ✅ (Approved), BUG 6: `PaletteCache` Has No Size Limit ✅ (Approved), BUG 7: Synchronous `File.existsSync()` Per Song on Main Thread ✅ (Approved) (+25 more)

### Community 12 - "Player Provider & Controls"
Cohesion: 0.09
Nodes (29): ControlledAudioPlayer, main, MethodChannel, MockListeningEventCollector, MockPlaylistCacheService, MockSubsonicService, setMockPlaying, setMockPosition (+21 more)

### Community 13 - "Library & Playlist Providers"
Cohesion: 0.07
Nodes (28): ../controllers/lyrics_controller.dart, AppRouteTransitions, buildTransitions, dispose, _FadeScaleRoute, FadeTransition, SlideTransition, _SlideUpRoute (+20 more)

### Community 14 - "Settings Provider"
Cohesion: 0.07
Nodes (27): analog, AnimatedContainer, AppTheme, AppThemeTokens, aura, build, buildTheme, CupertinoClickable (+19 more)

### Community 15 - "Download Provider & State"
Cohesion: 0.11
Nodes (27): 10. Testing Rules, 11. Surprising Connections, 12. Graph Query Reference, 13. MCP Server, 1. Project Identity, 2. Development Commands, 3. Architecture Overview, 4. God Nodes (Updated) (+19 more)

### Community 16 - "Listening Stats Provider"
Cohesion: 0.11
Nodes (27): ../core/navigation_transitions.dart, _AlbumThumb, build, Container, didChangeDependencies, didUpdateWidget, dispose, _GlassShell (+19 more)

### Community 17 - "Search Provider & History"
Cohesion: 0.12
Nodes (19): dart:convert, ../database/app_database.dart, PlaylistCache, SearchHistory, _cacheSongs, compute, PlaylistController, ListeningStatsNotifier (+11 more)

### Community 18 - "Replay Provider"
Cohesion: 0.08
Nodes (25): ../core/app_constants.dart, applyShuffleAlgorithm, _applySmartLocalAlgorithm, AudioHandler, _clearHistory, copyWith, dispose, _drainPoolOfQueuedSongs (+17 more)

### Community 19 - "Audio Handler & Core Logic"
Cohesion: 0.08
Nodes (24): ../features/ai_shuffle/ui/home_stats_widget.dart, AnimatedOpacity, _artGradient, build, cardBg, Container, dispose, _EmptyReplayHint (+16 more)

### Community 20 - "Subsonic Service & API"
Cohesion: 0.14
Nodes (23): edit_playlist_screen.dart, dispose, initState, build, _playAll, build, Container, QueueScreen (+15 more)

### Community 21 - "Recommendation Service"
Cohesion: 0.12
Nodes (21): AlbumCard, _AlbumPlaceholder, build, Container, Semantics, build, Container, Duration (+13 more)

### Community 22 - "Playlist Cache Service"
Cohesion: 0.14
Nodes (22): build, Column, CupertinoActionSheetAction, dispose, DropdownMenuItem, initState, Padding, _SettingsDivider (+14 more)

### Community 23 - "Listening Event Collector"
Cohesion: 0.11
Nodes (18): Song, _interleave, interleave, MapEntry, songWeight, _makeSong, buildFromFull, main (+10 more)

### Community 24 - "Scrobble Service"
Cohesion: 0.15
Nodes (21): ../core/constants.dart, BpmAnalyzerService, CacheSettingsService, copyWith, getString, _loadFromHive, _normalizedBaseUrl, PlaylistCacheService (+13 more)

### Community 25 - "Search History Service"
Cohesion: 0.1
Nodes (21): 1.4 Common Flutter Illogical Patterns — Full Reference, Async State Races, Autoplay/Lookahead Guard — Growing Set, code:dart (// ❌ ILLOGICAL — state read before async gap may be stale af), code:dart (// ❌ ILLOGICAL — no guard), code:dart (// ❌ ILLOGICAL — subscription never cancelled), code:dart (// ❌ ILLOGICAL — crashes when field is absent or wrong type), code:dart (// ❌ ILLOGICAL — widget may be unmounted by the time async c) (+13 more)

### Community 26 - "BPM Analyzer Service"
Cohesion: 0.1
Nodes (19): Spacer, build, _buildItem, Center, _confirmDelete, Dismissible, _EmptyLibrary, _FilterChip (+11 more)

### Community 27 - "Cache Settings Service"
Cohesion: 0.12
Nodes (19): GestureDetector, SliverToBoxAdapter, SliverPadding, build, GestureDetector, initState, _NewReleaseCard, NewReleasesScreen (+11 more)

### Community 28 - "Replay Gain Service"
Cohesion: 0.1
Nodes (19): AiShuffleScreen, _AiShuffleScreenState, build, _buildEmptyState, _buildErrorState, _buildSkeletonList, Center, dispose (+11 more)

### Community 29 - "Transcoding Service"
Cohesion: 0.11
Nodes (18): ../features/ai_shuffle/ui/ai_shuffle_screen.dart, Expanded, AppScaffold, _AppScaffoldState, build, didChangeAppLifecycleState, dispose, Expanded (+10 more)

### Community 30 - "Replay Upload Service"
Cohesion: 0.13
Nodes (18): favorites_screen.dart, _AlbumCard, build, _buildAlbumsGrid, _buildSongsList, Center, _EmptyState, _FavoritesHeader (+10 more)

### Community 31 - "Listening Log Service"
Cohesion: 0.15
Nodes (18): build, Container, dispose, Function, ListTile, _onSearchChanged, Padding, _SearchHeaderDelegate (+10 more)

### Community 32 - "Shuffle Algorithms"
Cohesion: 0.12
Nodes (15): HiveBoxes, _migrateBool, _migrateDouble, _migrateFromSharedPreferences, _migrateInt, _migrateString, _buildTestApp, main (+7 more)

### Community 33 - "AI Shuffle Features"
Cohesion: 0.17
Nodes (11): fl_register_plugins(), GeneratedPluginRegistrant, first_frame_cb(), my_application_activate(), my_application_class_init(), my_application_dispose(), my_application_init(), my_application_local_command_line() (+3 more)

### Community 34 - "UI Dialogs"
Cohesion: 0.12
Nodes (16): 🏗️ 1. Core Architecture & Isolate Rules, 🔊 2. Audio Engine & Shuffle Specifications, 📊 3. Analytics & Intelligence (Data Integrity), 🎨 4. Design System (ThemeTokens Engine), 💾 5. Persistence & API Specification, 🧩 Core Tokens (`AppThemeTokens`), 🗄️ Database (Drift/SQLite), 🚀 Gapless Incremental Reordering (+8 more)

### Community 35 - "UI Widgets (Song/Album)"
Cohesion: 0.12
Nodes (14): dart:collection, audio_handler.dart, palette_cache.dart, player_provider.dart (BUG 1 — timer), player_provider.dart (BUG 2 — scrobble), player_provider.dart (BUG 4 — stale currentIndex), player_provider.dart (BUG 5 — persist dedup), Pre-flight checks (+6 more)

### Community 36 - "App Scaffold & Navigation"
Cohesion: 0.21
Nodes (15): ../fluid_background.dart, build, DecoratedBox, didUpdateWidget, dispose, FluidBackground, _FluidBackgroundState, _FluidPainter (+7 more)

### Community 37 - "Core Constants & Exceptions"
Cohesion: 0.12
Nodes (14): nowPlaying, ScrobbleService, submit, ControlledAudioPlayer, main, MockListeningEventCollector, MockListeningLogService, MockPlaylistCacheService (+6 more)

### Community 38 - "Hive Database & Migration"
Cohesion: 0.13
Nodes (14): _applyReplayGain, AudioHandler, commitSmartLocalOrder, currentQueue, _moveBasedReorder, _rebuildSource, refreshReplayGain, standardShuffle (+6 more)

### Community 39 - "App Database (Drift)"
Cohesion: 0.13
Nodes (14): ClipRRect, build, ClipRRect, CustomPaint, formatDuration, getPreferredSize, _GlassThumbShape, _NeonTrackPainter (+6 more)

### Community 40 - "Core Themes & Transitions"
Cohesion: 0.14
Nodes (13): build, _buildContent, _buildEmptyState, Center, Column, initState, OfflineScreen, _OfflineScreenState (+5 more)

### Community 41 - "Palette Cache"
Cohesion: 0.18
Nodes (9): classify, main, main, main, ProviderScope, package:flutter_test/flutter_test.dart, package:navivibe/core/app_exception.dart, package:navivibe/core/palette_cache.dart (+1 more)

### Community 42 - "Device Utilities"
Cohesion: 0.15
Nodes (13): 1.2 Code Quality Non-Negotiables, code:dart (// ❌ NEVER — mutable model causes unpredictable state bugs), code:dart (// ✅ REQUIRED — immutable with copyWith), code:dart (// ❌ NEVER — these are build failures), code:dart (// ✅ REQUIRED — real implementation or explicit documented s), code:dart (// ❌ NEVER — crashes when server returns int instead of doub), code:dart (// ✅ REQUIRED — handles int, double, String-encoded numbers,), code:dart (// ❌ NEVER — errors disappear silently) (+5 more)

### Community 43 - "Android Entry Point"
Cohesion: 0.15
Nodes (13): code:block16 (User presses Next →), code:dart (// ❌ ILLOGICAL — does not check if index is still valid afte), code:dart (// ✅ CORRECT — re-read state after every await), code:block19 (User enables shuffle →), code:dart (// ❌ ILLOGICAL — uses savedIndex captured before shuffle), code:dart (// ✅ CORRECT — read index AFTER shuffle from the player itse), code:block22 (Song starts →), code:dart (// ❌ ILLOGICAL — scrobbles on EVERY tick after threshold) (+5 more)

### Community 44 - "Linux Entry Point"
Cohesion: 0.24
Nodes (10): cache_settings_service.dart, ../../../../core/hive_boxes.dart, _loadHistory, SearchHistoryNotifier, areAllCachesDisabled, areAllCachesEnabled, CacheSettingsService, getBpmCacheEnabled (+2 more)

### Community 45 - "AI Shuffle Data Models"
Cohesion: 0.29
Nodes (10): dart:math, ListeningLogService, _QueueEntry, _queueFailedLog, serialize, withIncrementedRetries, listening_log_service.dart, package:shared_preferences/shared_preferences.dart (+2 more)

### Community 46 - "AI Shuffle UI Components"
Cohesion: 0.17
Nodes (11): build, Divider, _getBackgroundColor, _getIcon, _getText, _getTextColor, InkWell, ServerStatusBar (+3 more)

### Community 47 - "Replay Screen Tests"
Cohesion: 0.17
Nodes (11): SafeArea, build, _buildSectionTitle, _buildTable, Padding, SafeArea, SizedBox, SongProfileSheet (+3 more)

### Community 49 - "Hive Storage & Security"
Cohesion: 0.18
Nodes (10): build, initState, MadeForYouScreen, _MadeForYouScreenState, Positioned, Scaffold, SliverList, SliverToBoxAdapter (+2 more)

### Community 50 - "Core Exception Classes"
Cohesion: 0.27
Nodes (9): isLrcFormat, LrcParser, parseLrc, parsePlain, RegExp, build, LyricLineWidget, lrc_parser.dart (+1 more)

### Community 51 - "App Database Schema"
Cohesion: 0.25
Nodes (9): LrcLibService, LyricsResult, _cache, LyricsRepository, _structuredLinesToLrc, lrclib_service.dart, ../models/lyrics_result.dart, ../../models/song.dart (+1 more)

### Community 52 - "Navigation Animations"
Cohesion: 0.18
Nodes (10): Card, build, _buildErrorCard, _buildSkeleton, _buildSkeletonRow, Card, Column, HomeStatsWidget (+2 more)

### Community 53 - "Core Utility Tests"
Cohesion: 0.18
Nodes (10): Column, build, Column, Container, GestureDetector, _shortDesc, SizedBox, _ThemeCard (+2 more)

### Community 54 - "Architecture Design Context"
Cohesion: 0.2
Nodes (9): dispose, getLabel, _initConnectivityWatcher, _loadFromHive, _stopConnectivityWatcher, TranscodeBitrate, TranscodeFormat, TranscodingService (+1 more)

### Community 55 - "Listening Stats Models"
Cohesion: 0.2
Nodes (9): build, Divider, SafeArea, SessionControlsSheet, _SessionStatusSheet, _showSessionStatusSheet, SnackBar, Divider (+1 more)

### Community 56 - "AI Shuffle Repositories"
Cohesion: 0.2
Nodes (9): _fakeSong, ListeningLogService, main, _makeService, MockHttpClient, _stubPost, _stubPostTimeout, package:mocktail/mocktail.dart (+1 more)

### Community 57 - "Palette Cache Logic"
Cohesion: 0.2
Nodes (9): 1. CODE QUALITY, 2. ARCHITECTURE & DESIGN, 3. PERFORMANCE, 4. AUDIO / PLAYBACK SPECIFIC, 5. UI / UX, 6. DATA & PERSISTENCE, 7. SECURITY, 8. TESTABILITY (+1 more)

### Community 58 - "Analytics Tables"
Cohesion: 0.2
Nodes (9): code:block1 (BUILD → SELF-AUDIT → TEST), code:block47 (STEP 1: READ), code:block48 (## Task Audit: [Task Name]), Flutter Production Build & Audit Skill, Full Task Execution Flow, Phase 2: SELF-AUDIT — Mandatory After Every Task, Post-Task Audit Report Format, Purpose (+1 more)

### Community 59 - "Service Layer Rationale"
Cohesion: 0.36
Nodes (8): calculateVolumeMultiplier, getFallbackGain, getMode, getModeDescription, getPreampGain, getPreventClipping, ReplayGainService, replay_gain_service.dart

### Community 60 - "Layered Architecture Rationale"
Cohesion: 0.22
Nodes (8): dart:async, build, dispose, initState, PlainTextView, _PlainTextViewState, Stack, _startTeleprompter

### Community 61 - "Knowledge Graph Rules"
Cohesion: 0.22
Nodes (8): copyWith, dispose, LyricsController, LyricsState, _onPosition, _subscribeToPosition, _onPosition, ../services/lyrics_repository.dart

### Community 62 - "Shuffle Logic & Settings"
Cohesion: 0.22
Nodes (8): MapEntry, addPlay, calculateSongScore, getHourPreference, MapEntry, RecommendationService, _saveData, SongProfile

### Community 63 - "Player Notifier Bug Analysis"
Cohesion: 0.22
Nodes (8): AS, CAST, _queryReplay, ReplayData, ReplaySong, ReplayStats, SUM, _ReplaySongReel

### Community 64 - "Offline Download Logic"
Cohesion: 0.22
Nodes (8): RecommendationCard, build, Card, Icon, RecommendationCard, SizedBox, Icon, SizedBox

### Community 65 - "Subsonic Service Security Audit"
Cohesion: 0.22
Nodes (9): code:dart (// ❌ NEVER — non-reactive, stale data), code:dart (// ✅ REQUIRED — reactive), code:dart (// ❌ NEVER in new files), code:dart (// ✅ REQUIRED), code:dart (// ❌ NEVER), code:dart (// ✅ REQUIRED), No Hardcoded Values, No ref.read() Inside build() (+1 more)

### Community 66 - "Search State Management"
Cohesion: 0.22
Nodes (9): 1. File Changes, code:yaml (flutter:), code:dart (class _AppleMusicPainter extends CustomPainter { … }), code:dart (import '../widgets/fluid_background.dart';), code:dart (// ── OLD ──────────────────────────────────────────────────), `lib/screens/now_playing_screen.dart`, Modified files, New files (+1 more)

### Community 67 - "Widget Rendering Tests"
Cohesion: 0.25
Nodes (7): BpmAnalyzerService, _cacheBPM, _estimateBPMFromGenre, _getCachedBPM, getCachedCount, initialize, isCached

### Community 68 - "UI Component Rationales"
Cohesion: 0.25
Nodes (7): AppDatabase, MigrationStrategy, package:drift_flutter/drift_flutter.dart, tables/analytics_tables.dart, tables/playlist_cache_table.dart, tables/recommendation_tables.dart, tables/search_history_table.dart

### Community 69 - "AI Shuffle Service Logic"
Cohesion: 0.25
Nodes (7): build, Center, dispose, initState, NoLyricsCard, _NoLyricsCardState, SizedBox

### Community 70 - "Community 70"
Cohesion: 0.25
Nodes (8): Audit Checklist, Error Handling, File Consistency, Logic Correctness, Resource Management, State Management, Test Readiness, UI Correctness

### Community 71 - "Community 71"
Cohesion: 0.29
Nodes (6): Answer, Q: Song model dependencies that cross layer boundaries, Source Nodes, Answer, Q: PlayerProvider ListeningEventCollector data flow, Source Nodes

### Community 72 - "Community 72"
Cohesion: 0.29
Nodes (7): code:dart (// Required tests:), code:dart (// Required tests:), code:dart (// Required tests:), code:dart (// Required tests:), code:dart (// Required tests:), code:dart (// Required: a regression test that reproduces the exact bug), Minimum Test Coverage Per Task

### Community 73 - "Community 73"
Cohesion: 0.33
Nodes (5): dart:ui, build, DecoratedBox, LyricsBackground, Stack

### Community 75 - "Community 75"
Cohesion: 0.33
Nodes (5): 3. Shader Uniform Layout Reference, 4. Why `shouldRepaint` Returns `true` Every Frame, 5. Impeller vs. Skia Notes, 7. Checklist, Fluid Background – Fragment Shader Migration Guide

### Community 76 - "Community 76"
Cohesion: 0.33
Nodes (6): 6. Extending the Shader, Adding album art texture warping (closest to real Apple Music), code:glsl (uniform sampler2D u_albumArt;), code:dart (shader.setImageSampler(0, albumArtImage); // ui.Image), code:glsl (vec4 artColor = texture(u_albumArt, warpUV);), Tuning blob count / speed

### Community 77 - "Community 77"
Cohesion: 0.33
Nodes (6): code:dart (void main() {), Phase 3: TEST — Mandatory Test Plan Per Task, Test Setup Template, Test Type Matrix, 2. One-time Shader Pre-load (optional but recommended), code:dart (void main() async {)

### Community 78 - "Community 78"
Cohesion: 0.67
Nodes (3): 1.1 Before Writing Any Code, 1.3 The Music Player Logic Test — Spot Every Illogical Behaviour, Phase 1: BUILD — Production-Only Standards

## Knowledge Gaps
- **867 isolated node(s):** `MainActivity`, `initState`, `dispose`, `build`, `MyMusicPlayerApp` (+862 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter_riverpod/flutter_riverpod.dart` connect `Playlist Detail Screen` to `Replay & New Releases Screens`, `Library & Favorites Screens`, `Home & Made For You Screens`, `Settings Screen`, `Made For You Widgets`, `Playlist Header Widgets`, `Player Provider & Controls`, `Library & Playlist Providers`, `Settings Provider`, `Listening Stats Provider`, `Search Provider & History`, `Replay Provider`, `Audio Handler & Core Logic`, `Subsonic Service & API`, `Recommendation Service`, `Playlist Cache Service`, `Scrobble Service`, `BPM Analyzer Service`, `Cache Settings Service`, `Replay Gain Service`, `Transcoding Service`, `Replay Upload Service`, `Listening Log Service`, `Shuffle Algorithms`, `Core Constants & Exceptions`, `Core Themes & Transitions`, `Palette Cache`, `Linux Entry Point`, `AI Shuffle Data Models`, `AI Shuffle UI Components`, `Replay Screen Tests`, `Hive Storage & Security`, `App Database Schema`, `Navigation Animations`, `Core Utility Tests`, `Listening Stats Models`, `Knowledge Graph Rules`, `Player Notifier Bug Analysis`?**
  _High betweenness centrality (0.106) - this node is a cross-community bridge._
- **Why does `../../models/song.dart` connect `App Database Schema` to `Now Playing & Queue UI`, `Replay & New Releases Screens`, `Made For You Detail Screen`, `Playlist Detail Screen`, `Settings Screen`, `Made For You Widgets`, `Playlist Header Widgets`, `Library & Playlist Providers`, `Search Provider & History`, `Replay Provider`, `Audio Handler & Core Logic`, `Subsonic Service & API`, `Recommendation Service`, `Listening Event Collector`, `BPM Analyzer Service`, `Cache Settings Service`, `Replay Upload Service`, `Core Constants & Exceptions`, `Hive Database & Migration`, `Core Themes & Transitions`, `AI Shuffle Data Models`, `Hive Storage & Security`, `Layered Architecture Rationale`, `Knowledge Graph Rules`, `Shuffle Logic & Settings`, `Widget Rendering Tests`?**
  _High betweenness centrality (0.069) - this node is a cross-community bridge._
- **Why does `package:flutter/material.dart` connect `Subsonic Service & API` to `Replay & New Releases Screens`, `Library & Favorites Screens`, `Playlist Detail Screen`, `Settings Screen`, `Playlist Header Widgets`, `Library & Playlist Providers`, `Settings Provider`, `Listening Stats Provider`, `Audio Handler & Core Logic`, `Recommendation Service`, `Playlist Cache Service`, `BPM Analyzer Service`, `Cache Settings Service`, `Replay Gain Service`, `Transcoding Service`, `Replay Upload Service`, `Listening Log Service`, `Shuffle Algorithms`, `UI Widgets (Song/Album)`, `App Scaffold & Navigation`, `App Database (Drift)`, `Core Themes & Transitions`, `Palette Cache`, `AI Shuffle UI Components`, `Replay Screen Tests`, `Hive Storage & Security`, `Core Exception Classes`, `Navigation Animations`, `Core Utility Tests`, `Architecture Design Context`, `Listening Stats Models`, `Layered Architecture Rationale`, `Offline Download Logic`, `AI Shuffle Service Logic`, `Community 73`?**
  _High betweenness centrality (0.068) - this node is a cross-community bridge._
- **What connects `MainActivity`, `initState`, `dispose` to the rest of the system?**
  _867 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Now Playing & Queue UI` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Replay & New Releases Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.04 - nodes in this community are weakly interconnected._
- **Should `Library & Favorites Screens` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._