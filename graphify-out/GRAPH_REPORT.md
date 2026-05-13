# Graph Report - .  (2026-05-13)

## Corpus Check
- 178 files · ~264,189 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 801 nodes · 1517 edges · 76 communities (60 shown, 16 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.75)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]

## God Nodes (most connected - your core abstractions)
1. `replay_screen.dart` - 52 edges
2. `playlist_details_screen.dart` - 52 edges
3. `package:flutter_riverpod/flutter_riverpod.dart` - 46 edges
4. `subsonic_service.dart` - 46 edges
5. `ListeningStats` - 43 edges
6. `ListeningEventCollector` - 41 edges
7. `settings_screen.dart` - 40 edges
8. `PlayerProvider` - 40 edges
9. `package:flutter/material.dart` - 38 edges
10. `mini_player.dart` - 37 edges

## Surprising Connections (you probably didn't know these)
- `ListeningEventCollector` --semantically_similar_to--> `listening_log_service.dart`  [EXTRACTED] [semantically similar]
  lib/services/context.md → lib/services/scrobble_service.dart
- `ListeningEventCollector` --defines--> `pumpMicrotasks`  [EXTRACTED]
  lib/services/context.md → test/services/listening_event_collector_test.dart
- `PaletteCache` --conceptually_related_to--> `Multi-Engine Theme System`  [EXTRACTED]
  lib/core/palette_cache.dart → CLAUDE.md
- `ListeningEventCollector` --defines--> `makeSong`  [EXTRACTED]
  lib/services/context.md → test/services/audio_handler_shuffle_test.dart
- `ListeningEventCollector` --defines--> `generateUuid`  [EXTRACTED]
  lib/services/context.md → lib/utils/device_utils.dart

## Hyperedges (group relationships)
- **Playback State Management** — player_provider_playernotifier, subsonic_service_subsonicservice, hive_boxes_hiveboxes [INFERRED 0.85]
- **Playback Telemetry and Scrobbling** — scrobble_service_scrobbleservice, listening_log_service_listeninglogservice, listening_event_collector_listeningeventcollector [INFERRED 0.95]
- **Community 61 (Core Services)** — audio_handler_audiohandler, offline_service_offlineservice, player_provider_playerprovider, subsonic_service_subsonicservice, claude_advancedshufflealgorithms, listening_event_collector_listeningeventcollector [EXTRACTED 1.00]
- **Song Central Coupling** — song_song, subsonic_service_subsonicservice, player_notifier_playernotifier, hive_boxes_hiveboxes, app_database_appdatabase [EXTRACTED 1.00]
- **AI Shuffle UI Component Set** —  [INFERRED]
- **Android Launcher Icons Set** — ic_launcher_hdpi, launcher_icon_hdpi, ic_launcher_mdpi, launcher_icon_mdpi, ic_launcher_xhdpi, launcher_icon_xhdpi, ic_launcher_xxhdpi, launcher_icon_xxhdpi, ic_launcher_xxxhdpi, launcher_icon_xxxhdpi [EXTRACTED 1.00]

## Communities (76 total, 16 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.07
Nodes (60): makeSong, dart:async, dart:io, DownloadStateNotifier, _performDownload, progressOf, _set, _setFailed (+52 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (42): add_to_playlist_dialog.dart, ../../data/models/health_response.dart, AiShuffleScreen, _AiShuffleScreenState, _buildErrorState, _buildSkeletonList, Card, _fetchRecommendations (+34 more)

### Community 2 - "Community 2"
Cohesion: 0.07
Nodes (31): ../data/models/profile_response.dart, ../../data/models/recommended_song.dart, ../data/models/session_status_response.dart, ../data/models/stats_response.dart, ../data/repositories/shuffle_exception.dart, ../data/repositories/shuffle_repository.dart, ../data/services/shuffle_api_service.dart, toString (+23 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (30): AnalyticsTables, ArtistAffinityCompanion, ArtistAffinityEntity, copyWithCompanion, GenreAffinityCompanion, GenreAffinityEntity, map, PlayEventsCompanion (+22 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (31): ../core/palette_cache.dart, _AppleMusicThumb, _AudioQualityStrip, _BottomAction, DraggableScrollableSheet, _EmptyTab, firstNonNull, _formatSleepLabel (+23 more)

### Community 5 - "Community 5"
Cohesion: 0.08
Nodes (29): AppException, ../core/app_exception.dart, AuthException, NetworkException, ServerException, SubsonicApiException, TimeoutException, _backgroundRefreshPlaylist (+21 more)

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (26): HealthResponse, ShuffleStatsResponse, AlbumStat, ArtistStat, _parseInt, RecentPlay, TrackStat, AnimatedBuilder (+18 more)

### Community 7 - "Community 7"
Cohesion: 0.08
Nodes (24): analog, AnimatedContainer, aura, buildTheme, CupertinoClickable, _CupertinoClickableState, frost, GlassBox (+16 more)

### Community 8 - "Community 8"
Cohesion: 0.08
Nodes (24): AppDatabase (generated), DownloadState, PlaylistCache, SongDownloadState, copyWith, cancelBackgroundDownload, downloadSongs, File (+16 more)

### Community 9 - "Community 9"
Cohesion: 0.09
Nodes (22): ../core/app_constants.dart, applyShuffleAlgorithm, _applySmartLocalAlgorithm, _clearHistory, _drainPoolOfQueuedSongs, _init, _initPlaylistPool, _jumpToInternal (+14 more)

### Community 10 - "Community 10"
Cohesion: 0.1
Nodes (21): ListeningEventCollector, dart:ffi, AnalyticsStats, CONFLICT, _csvField, _fileTimestamp, getApplicationDocumentsDirectory, p (+13 more)

### Community 11 - "Community 11"
Cohesion: 0.1
Nodes (20): CustomScrollView, _DailyListeningChart, _DashedLine, _InlineStatRow, LayoutBuilder, _monthLabel, _ReplayHeader, _ReplayScreenState (+12 more)

### Community 12 - "Community 12"
Cohesion: 0.11
Nodes (18): ../core/navigation_transitions.dart, _AlbumThumb, didChangeDependencies, _GlassShell, _MiniPlayerState, _MiniProgressBar, _MiniProgressBarState, _NoiseLayer (+10 more)

### Community 13 - "Community 13"
Cohesion: 0.11
Nodes (18): _AddSongsRow, _CircleIconButton, _CollapsedTitle, _confirmDeletePlaylist, _DismissBackground, _DownloadAllButton, _ExpandedHeader, _filterSongs (+10 more)

### Community 14 - "Community 14"
Cohesion: 0.11
Nodes (17): ../features/ai_shuffle/ui/home_stats_widget.dart, AnimatedOpacity, _artGradient, cardBg, _ExploreCard, _greet, _HomeHeader, _HomeScreenState (+9 more)

### Community 15 - "Community 15"
Cohesion: 0.12
Nodes (16): AudioHandler, Gapless Incremental Reordering, _applyReplayGain, commitSmartLocalOrder, currentQueue, _interleave, _moveBasedReorder, _rebuildSource (+8 more)

### Community 16 - "Community 16"
Cohesion: 0.12
Nodes (16): CupertinoActionSheetAction, DropdownMenuItem, _SettingsDivider, _SettingsDropdownRow, _SettingsGroup, _SettingsInputRow, _SettingsNavRow, _SettingsScreenState (+8 more)

### Community 17 - "Community 17"
Cohesion: 0.14
Nodes (15): dart:ui, Function, _QueueTile, Slidable, _onSearchChanged, _SearchHeaderDelegate, _SearchHistorySliver, _SearchResultsSliver (+7 more)

### Community 18 - "Community 18"
Cohesion: 0.16
Nodes (11): dart:convert, _migrateBool, _migrateDouble, _migrateFromSharedPreferences, _migrateInt, _migrateString, ListeningStatsNotifier, uploadData (+3 more)

### Community 19 - "Community 19"
Cohesion: 0.15
Nodes (13): GestureDetector, build, Column, _buildContent, _buildEmptyState, _OfflineScreenState, _playAll, _shortDesc (+5 more)

### Community 20 - "Community 20"
Cohesion: 0.18
Nodes (13): SliverToBoxAdapter, SliverPadding, _NewReleaseCard, _onAlbumTap, Positioned, SliverList, SnackBar, SongTile (+5 more)

### Community 21 - "Community 21"
Cohesion: 0.18
Nodes (12): ../database/app_database.dart, SearchHistory, _cacheSongs, PlaylistController, compute, CachedPlaylistResult, library_provider.dart, ../models/album.dart (+4 more)

### Community 22 - "Community 22"
Cohesion: 0.15
Nodes (13): ../core/constants.dart, getString, _normalizedBaseUrl, SettingsNotifier, SettingsState, ../services/bpm_analyzer_service.dart, ../services/cache_settings_service.dart, ../services/listening_event_collector.dart (+5 more)

### Community 23 - "Community 23"
Cohesion: 0.15
Nodes (12): ../features/ai_shuffle/ui/ai_shuffle_screen.dart, Expanded, AppScaffold, _AppScaffoldState, didChangeAppLifecycleState, _NavItem, ../screens/favorites_screen.dart, ../screens/home_screen.dart (+4 more)

### Community 24 - "Community 24"
Cohesion: 0.18
Nodes (12): favorites_screen.dart, _buildAlbumsGrid, _buildSongsList, _EmptyState, _FavoritesHeader, _FavoritesScreenState, _FilterPill, SliverFillRemaining (+4 more)

### Community 25 - "Community 25"
Cohesion: 0.26
Nodes (12): ../../../core/theme.dart, edit_playlist_screen.dart, dispose, Center, _SongPickerScreenState, _toggleSong, Scaffold, AlertDialog (+4 more)

### Community 27 - "Community 27"
Cohesion: 0.17
Nodes (11): ClipRRect, paint, shouldRepaint, CustomPaint, formatDuration, getPreferredSize, _GlassThumbShape, _NeonTrackPainter (+3 more)

### Community 28 - "Community 28"
Cohesion: 0.17
Nodes (12): FluidBackground, ../fluid_background.dart, initState, DecoratedBox, didUpdateWidget, _FluidBackgroundState, _FluidPainter, FluidShaderLoader (+4 more)

### Community 29 - "Community 29"
Cohesion: 0.17
Nodes (11): Spacer, _buildItem, _confirmDelete, Dismissible, _EmptyLibrary, _FilterChip, LibraryScreen, _LibraryScreenState (+3 more)

### Community 30 - "Community 30"
Cohesion: 0.2
Nodes (10): AppDatabase, HiveBoxes, MigrationStrategy, package:drift_flutter/drift_flutter.dart, PlayerNotifier, PlayerState, tables/analytics_tables.dart, tables/playlist_cache_table.dart (+2 more)

### Community 31 - "Community 31"
Cohesion: 0.29
Nodes (10): Duration, OptionsMenu, Container, _DownloadBadge, ../models/download_state.dart, ../models/song.dart, options_menu.dart, ../providers/download_provider.dart (+2 more)

### Community 32 - "Community 32"
Cohesion: 0.2
Nodes (10): _QueueEntry, _queueFailedLog, serialize, withIncrementedRetries, nowPlaying, submit, listening_log_service.dart, package:uuid/uuid.dart (+2 more)

### Community 33 - "Community 33"
Cohesion: 0.25
Nodes (7): AS, CAST, _queryReplay, ReplayData, ReplayStats, SUM, _ReplaySongReel

### Community 34 - "Community 34"
Cohesion: 0.25
Nodes (7): _loadFromHive, getLabel, _initConnectivityWatcher, _stopConnectivityWatcher, TranscodeBitrate, TranscodeFormat, _updateConnectionType

### Community 35 - "Community 35"
Cohesion: 0.25
Nodes (8): FluidBackground Shader, Multi-Engine Theme System, dart:collection, clear, _evictIfNeeded, hasColorsFor, update, PaletteCache

### Community 36 - "Community 36"
Cohesion: 0.29
Nodes (6): MapEntry, addPlay, calculateSongScore, getHourPreference, _saveData, SongProfile

### Community 37 - "Community 37"
Cohesion: 0.29
Nodes (6): _cacheBPM, _estimateBPMFromGenre, _getCachedBPM, getCachedCount, initialize, isCached

### Community 38 - "Community 38"
Cohesion: 0.29
Nodes (7): calculateVolumeMultiplier, getFallbackGain, getMode, getModeDescription, getPreampGain, getPreventClipping, replay_gain_service.dart

### Community 39 - "Community 39"
Cohesion: 0.29
Nodes (6): AppRouteTransitions, buildTransitions, _FadeScaleRoute, FadeTransition, SlideTransition, _SlideUpRoute

### Community 41 - "Community 41"
Cohesion: 0.33
Nodes (6): cache_settings_service.dart, areAllCachesDisabled, areAllCachesEnabled, getBpmCacheEnabled, getImageCacheEnabled, getMusicCacheEnabled

### Community 42 - "Community 42"
Cohesion: 0.33
Nodes (6): RecommendationCard Widget, ServerStatusBar Widget, SessionControlsSheet Widget, Shuffle Algorithm Test Suite, SongProfileSheet Widget, Widget Test Suite

### Community 43 - "Community 43"
Cohesion: 0.5
Nodes (3): ../../../../core/hive_boxes.dart, _loadHistory, SearchHistoryNotifier

## Knowledge Gaps
- **493 isolated node(s):** `MainActivity`, `FluidShaderLoader`, `_FluidPainter`, `_FluidBackgroundState`, `_onTick` (+488 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `package:flutter_riverpod/flutter_riverpod.dart` connect `Community 25` to `Community 0`, `Community 1`, `Community 2`, `Community 4`, `Community 6`, `Community 7`, `Community 9`, `Community 11`, `Community 12`, `Community 13`, `Community 14`, `Community 16`, `Community 17`, `Community 18`, `Community 19`, `Community 20`, `Community 21`, `Community 22`, `Community 23`, `Community 24`, `Community 29`, `Community 31`, `Community 32`, `Community 33`, `Community 43`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Why does `subsonic_service.dart` connect `Community 5` to `Community 0`, `Community 32`, `Community 43`, `Community 45`, `Community 15`, `Community 18`, `Community 21`, `Community 22`, `Community 25`, `Community 30`, `Community 31`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Why does `ListeningEventCollector` connect `Community 10` to `Community 0`, `Community 32`, `Community 3`, `Community 8`, `Community 9`, `Community 45`, `Community 17`, `Community 18`, `Community 21`, `Community 30`, `Community 31`?**
  _High betweenness centrality (0.076) - this node is a cross-community bridge._
- **What connects `MainActivity`, `FluidShaderLoader`, `_FluidPainter` to the rest of the system?**
  _493 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._