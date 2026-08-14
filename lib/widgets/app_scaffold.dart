import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart' as avpb;

import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/playlist_details_screen.dart';
import '../screens/settings_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../services/replay_upload_service.dart';
import '../services/listening_log_service.dart';
import '../services/subsonic_service.dart';
import '../services/transcoding_service.dart';
import '../services/window_manager_service.dart';
import '../core/theme.dart';
import '../core/keyboard_shortcuts.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../models/album.dart';
import '../fluid_background.dart';
import '../utils/platform_utils.dart';
import '../lyrics/views/lyrics_view.dart';
import 'mini_player.dart';
import 'options_menu.dart';
import 'create_playlist_dialog.dart';
import 'desktop_dialogs.dart';

// =============================================================================
// AppScaffold
//
// Adaptive 3-Pane Desktop & Mobile Scaffold
//   Desktop (width ≥ 850px) → 3-Pane Spotify/Apple Music Workspace Architecture
//                             (Left Library Sidebar + Center Content + Right Now Playing Panel + Bottom Desktop Player)
//   Mobile / Narrow          → Bottom Navigation Bar + Mini Player
// =============================================================================

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WidgetsBindingObserver, WindowLifecycleMixin {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(replayUploadServiceProvider).performUploadIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(listeningLogServiceProvider).flushQueue();
    }
  }

  static const List<_NavItem> _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
      label: 'Search',
    ),
    _NavItem(
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'AI Shuffle',
    ),
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
      label: 'Dashboard',
    ),
    _NavItem(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Library',
    ),
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    AiShuffleScreen(),
    DashboardScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final settings = ref.watch(settingsProvider);
    final meshEnabled = settings.meshGradientEnabled && settings.fluidBgEnabled;
    final isOffline = ref.watch(isOfflineProvider);
    final meshIsPlaying = meshEnabled
        ? ref.watch(playerProvider.select((s) => s.isPlaying))
        : true;

    return NaviKeyboardShortcuts(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useDesktopLayout =
              PlatformUtils.prefersSidebarNavigation ||
              constraints.maxWidth >= PlatformUtils.kDesktopBreakpoint;

          if (useDesktopLayout) {
            return _Desktop3PaneScaffold(
              currentIndex: _currentIndex,
              onNavTap: (i) => setState(() => _currentIndex = i),
              items: _items,
              screens: _screens,
              meshEnabled: meshEnabled,
              meshIsPlaying: meshIsPlaying,
              isOffline: isOffline,
              tokens: tokens,
            );
          }

          return _MobileScaffold(
            currentIndex: _currentIndex,
            onNavTap: (i) => setState(() => _currentIndex = i),
            items: _items,
            screens: _screens,
            meshEnabled: meshEnabled,
            meshIsPlaying: meshIsPlaying,
            isOffline: isOffline,
            tokens: tokens,
          );
        },
      ),
    );
  }
}

// =============================================================================
// Desktop 3-Pane Workspace Scaffold
// =============================================================================

class _Desktop3PaneScaffold extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final List<_NavItem> items;
  final List<Widget> screens;
  final bool meshEnabled;
  final bool meshIsPlaying;
  final bool isOffline;
  final AppThemeTokens tokens;

  const _Desktop3PaneScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
    required this.meshEnabled,
    required this.meshIsPlaying,
    required this.isOffline,
    required this.tokens,
  });

  @override
  ConsumerState<_Desktop3PaneScaffold> createState() =>
      _Desktop3PaneScaffoldState();
}

class _Desktop3PaneScaffoldState extends ConsumerState<_Desktop3PaneScaffold> {
  bool _showRightPanel = true;
  int _rightPanelTab = 0; // 0: Info/Credits, 1: Lyrics, 2: Queue

  void _toggleRightPanel([int? targetTab]) {
    setState(() {
      if (targetTab != null) {
        if (_showRightPanel && _rightPanelTab == targetTab) {
          _showRightPanel = false;
        } else {
          _showRightPanel = true;
          _rightPanelTab = targetTab;
        }
      } else {
        _showRightPanel = !_showRightPanel;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final playerState = ref.watch(playerProvider);

    final leftSidebar = _DesktopLeftSidebar(
      currentIndex: widget.currentIndex,
      onTap: widget.onNavTap,
      items: widget.items,
      tokens: tokens,
      meshEnabled: widget.meshEnabled,
    );

    final topHeader = _DesktopTopHeader(
      onNavTap: widget.onNavTap,
      tokens: tokens,
    );

    final rightPanel = _showRightPanel && playerState.queue.isNotEmpty
        ? _DesktopRightPanel(
            activeTab: _rightPanelTab,
            onTabChanged: (i) => setState(() => _rightPanelTab = i),
            onClose: () => setState(() => _showRightPanel = false),
            tokens: tokens,
          )
        : null;

    final centerContent = Column(
      children: [
        topHeader,
        if (widget.isOffline) _OfflineBanner(tokens: tokens),
        Expanded(
          child: IndexedStack(
            index: widget.currentIndex,
            children: widget.screens,
          ),
        ),
      ],
    );

    final workspaceBody = Row(
      children: [
        leftSidebar,
        Expanded(child: centerContent),
        if (rightPanel != null) rightPanel,
      ],
    );

    final body = Column(
      children: [
        Expanded(child: workspaceBody),
        _DesktopBottomPlayerBar(
          tokens: tokens,
          showRightPanel: _showRightPanel,
          rightPanelTab: _rightPanelTab,
          onToggleRightPanel: _toggleRightPanel,
        ),
      ],
    );

    if (widget.meshEnabled) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: FluidBackground(
                isPlaying: widget.meshIsPlaying,
                colors: [
                  tokens.bgBase,
                  Color.lerp(tokens.bgBase, tokens.accent, 0.18)!,
                  Color.lerp(tokens.accent, tokens.bgBase, 0.55)!,
                  tokens.accent.withValues(alpha: 0.70),
                ],
              ),
            ),
            body,
          ],
        ),
      );
    }

    return Scaffold(backgroundColor: tokens.bgBase, body: body);
  }
}

// =============================================================================
// Desktop Top Command Header
// =============================================================================

class _DesktopTopHeader extends ConsumerWidget {
  final ValueChanged<int> onNavTap;
  final AppThemeTokens tokens;

  const _DesktopTopHeader({
    required this.onNavTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.bgBase.withValues(alpha: 0.80),
        border: Border(
          bottom: BorderSide(
            color: tokens.outline.withValues(alpha: 0.20),
          ),
        ),
      ),
      child: Row(
        children: [
          // Navigation History Buttons
          IconButton(
            icon: Icon(
              Icons.chevron_left_rounded,
              color: tokens.textPrimary,
              size: 28,
            ),
            onPressed: () {
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            tooltip: 'Go Back',
          ),
          const SizedBox(width: 8),

          // Central Universal Search Input Bar (Spotify Style)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TextField(
                  readOnly: true,
                  onTap: () => onNavTap(1), // Open Search Screen
                  decoration: InputDecoration(
                    hintText: 'What do you want to play?',
                    hintStyle: TextStyle(
                      color: tokens.textMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: tokens.textSecondary,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: tokens.bgElevated.withValues(alpha: 0.60),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Settings Icon Shortcut
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: tokens.textSecondary,
              size: 22,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Desktop Left Sidebar (Main Nav + Spotify "Your Library" Panel)
// =============================================================================

class _DesktopLeftSidebar extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  final AppThemeTokens tokens;
  final bool meshEnabled;

  const _DesktopLeftSidebar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.tokens,
    required this.meshEnabled,
  });

  @override
  ConsumerState<_DesktopLeftSidebar> createState() =>
      _DesktopLeftSidebarState();
}

class _DesktopLeftSidebarState extends ConsumerState<_DesktopLeftSidebar> {
  String _libFilter = 'all'; // 'all', 'playlists', 'albums'
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final playlistsAsync = ref.watch(playlistsProvider);
    final albumsAsync = ref.watch(recentlyPlayedAlbumsProvider);
    final service = ref.watch(subsonicServiceProvider);

    return Container(
      width: 280,
      color: tokens.bgBase.withValues(alpha: widget.meshEnabled ? 0.65 : 0.95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Brand Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  color: tokens.accent,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'NaviVibe',
                  style: tokens.textStyle(20, FontWeight.w800, tokens.textPrimary),
                ),
              ],
            ),
          ),

          // Primary Navigation Menu
          ...List.generate(widget.items.length, (i) {
            final item = widget.items[i];
            final active = widget.currentIndex == i;
            return _SidebarNavItem(
              item: item,
              active: active,
              tokens: tokens,
              onTap: () => widget.onTap(i),
            );
          }),

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              color: tokens.outline.withValues(alpha: 0.25),
              height: 1,
            ),
          ),
          const SizedBox(height: 12),

          // Spotify-style "Your Library" Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.library_music_rounded,
                  color: tokens.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Your Library',
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.add_rounded,
                    color: tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const CreatePlaylistDialog(),
                  ),
                  tooltip: 'Create Playlist',
                ),
              ],
            ),
          ),

          // Filter Chips (Playlists, Albums)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _LibFilterChip(
                  label: 'All',
                  selected: _libFilter == 'all',
                  onTap: () => setState(() => _libFilter = 'all'),
                  tokens: tokens,
                ),
                const SizedBox(width: 6),
                _LibFilterChip(
                  label: 'Playlists',
                  selected: _libFilter == 'playlists',
                  onTap: () => setState(() => _libFilter = 'playlists'),
                  tokens: tokens,
                ),
                const SizedBox(width: 6),
                _LibFilterChip(
                  label: 'Albums',
                  selected: _libFilter == 'albums',
                  onTap: () => setState(() => _libFilter = 'albums'),
                  tokens: tokens,
                ),
              ],
            ),
          ),

          // Library Item Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              height: 32,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: TextStyle(color: tokens.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search library...',
                  hintStyle: TextStyle(color: tokens.textMuted, fontSize: 12),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: tokens.textMuted,
                    size: 16,
                  ),
                  filled: true,
                  fillColor: tokens.bgElevated.withValues(alpha: 0.50),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          // Scrollable Library Item List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              children: [
                if (_libFilter == 'all' || _libFilter == 'playlists')
                  playlistsAsync.when(
                    data: (playlists) {
                      final filtered = playlists.where(
                        (p) => p.name.toLowerCase().contains(_searchQuery),
                      ).toList();
                      return Column(
                        children: filtered.map((playlist) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: tokens.bgElevated,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: tokens.accent,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              playlist.name,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Playlist \u2022 ${playlist.songCount} songs',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlaylistDetailsScreen(
                                    playlist: playlist,
                                  ),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                if (_libFilter == 'all' || _libFilter == 'albums')
                  albumsAsync.when(
                    data: (albums) {
                      final filtered = albums.where(
                        (a) =>
                            a.name.toLowerCase().contains(_searchQuery) ||
                            a.artist.toLowerCase().contains(_searchQuery),
                      ).toList();
                      return Column(
                        children: filtered.map((album) {
                          final coverUrl = service.getCoverArtUrl(album.coverArt);
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CachedNetworkImage(
                                imageUrl: coverUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: tokens.bgElevated,
                                  child: Icon(
                                    Icons.album_rounded,
                                    color: tokens.textMuted,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              album.name,
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Album \u2022 ${album.artist}',
                              style: TextStyle(
                                color: tokens.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              try {
                                final songs = await service.getAlbum(album.id);
                                if (context.mounted) {
                                  ref
                                      .read(playerProvider.notifier)
                                      .setQueue(songs, 0);
                                }
                              } catch (_) {}
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppThemeTokens tokens;

  const _LibFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? tokens.accent : tokens.bgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : tokens.textPrimary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Desktop Right Panel (Now Playing Info / Credits / Lyrics / Queue)
// =============================================================================

class _DesktopRightPanel extends ConsumerWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onClose;
  final AppThemeTokens tokens;

  const _DesktopRightPanel({
    required this.activeTab,
    required this.onTabChanged,
    required this.onClose,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final service = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty ||
        playerState.currentIndex >= playerState.queue.length) {
      return const SizedBox.shrink();
    }

    final song = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: tokens.bgBase.withValues(alpha: 0.90),
        border: Border(
          left: BorderSide(color: tokens.outline.withValues(alpha: 0.20)),
        ),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    song.title,
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: onClose,
                  tooltip: 'Close Panel',
                ),
              ],
            ),
          ),

          // Tab Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _PanelTabButton(
                  label: 'Info',
                  selected: activeTab == 0,
                  onTap: () => onTabChanged(0),
                  tokens: tokens,
                ),
                const SizedBox(width: 8),
                _PanelTabButton(
                  label: 'Lyrics',
                  selected: activeTab == 1,
                  onTap: () => onTabChanged(1),
                  tokens: tokens,
                ),
                const SizedBox(width: 8),
                _PanelTabButton(
                  label: 'Queue',
                  selected: activeTab == 2,
                  onTap: () => onTabChanged(2),
                  tokens: tokens,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Divider(color: tokens.outline.withValues(alpha: 0.20), height: 1),

          // Panel Content Body
          Expanded(
            child: IndexedStack(
              index: activeTab,
              children: [
                // Tab 0: Track Info & Credits
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Large Artwork Card
                      Center(
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.50),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        song.title,
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${song.artist} \u2022 ${song.album}',
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Audio Quality Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.bgElevated,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.high_quality_rounded,
                              color: tokens.accent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              song.suffix.isNotEmpty
                                  ? '${song.suffix.toUpperCase()} \u2022 ${song.bitRate > 0 ? "${song.bitRate} kbps" : "Original Lossless"}'
                                  : 'ORIGINAL AUDIO',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Song Credits Section
                      Text(
                        'Credits & Details',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CreditRow(
                        label: 'Artist',
                        value: song.artist,
                        tokens: tokens,
                      ),
                      if (song.composer.isNotEmpty)
                        _CreditRow(
                          label: 'Composer',
                          value: song.composer,
                          tokens: tokens,
                        ),
                      _CreditRow(
                        label: 'Album',
                        value: song.album,
                        tokens: tokens,
                      ),
                      if (song.year > 0)
                        _CreditRow(
                          label: 'Year',
                          value: song.year.toString(),
                          tokens: tokens,
                        ),
                      _CreditRow(
                        label: 'Plays',
                        value: '${song.playCount} plays',
                        tokens: tokens,
                      ),
                    ],
                  ),
                ),

                // Tab 1: Realtime Synced Lyrics
                LyricsView(
                  song: song,
                  imageUrl: imageUrl,
                  isEmbedded: true,
                ),

                // Tab 2: Interactive Queue List
                const _DesktopQueueView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AppThemeTokens tokens;

  const _PanelTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? tokens.accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? tokens.accent.withValues(alpha: 0.40)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? tokens.accent : tokens.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  final String label;
  final String value;
  final AppThemeTokens tokens;

  const _CreditRow({
    required this.label,
    required this.value,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopQueueView extends ConsumerWidget {
  const _DesktopQueueView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.watch(subsonicServiceProvider);
    final tokens = ThemeTokens.of(context);

    if (playerState.queue.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playerState.queue.length,
      itemBuilder: (context, index) {
        final song = playerState.queue[index];
        final isPlaying = index == playerState.currentIndex;
        final coverUrl = service.getCoverArtUrl(song.coverArt);

        return ListTile(
          dense: true,
          tileColor: isPlaying
              ? tokens.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: coverUrl,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          title: Text(
            song.title,
            style: TextStyle(
              color: isPlaying ? tokens.accent : tokens.textPrimary,
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            style: TextStyle(color: tokens.textSecondary, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isPlaying
              ? Icon(Icons.volume_up_rounded, color: tokens.accent, size: 18)
              : IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: tokens.textMuted,
                    size: 16,
                  ),
                  onPressed: () => notifier.removeFromQueue(index),
                ),
          onTap: () => notifier.jumpTo(index),
        );
      },
    );
  }
}



// =============================================================================
// Desktop Bottom Player Bar (Full Width Spotify Style)
// =============================================================================

class _DesktopBottomPlayerBar extends ConsumerWidget {
  final AppThemeTokens tokens;
  final bool showRightPanel;
  final int rightPanelTab;
  final Function([int?]) onToggleRightPanel;

  const _DesktopBottomPlayerBar({
    required this.tokens,
    required this.showRightPanel,
    required this.rightPanelTab,
    required this.onToggleRightPanel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty ||
        playerState.currentIndex >= playerState.queue.length) {
      return const SizedBox.shrink();
    }

    final song = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);
    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive = playerState.repeatMode != LoopMode.off;

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.bgBase.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: tokens.outline.withValues(alpha: 0.20)),
        ),
      ),
      child: Row(
        children: [
          // Left Zone: Current Song Info
          SizedBox(
            width: 280,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _openAppleMusicFullScreen(context),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openAppleMusicFullScreen(context),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    playerState.starredIds.contains(song.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: playerState.starredIds.contains(song.id)
                        ? Colors.pinkAccent
                        : tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => notifier.toggleStar(song.id),
                ),
              ],
            ),
          ),

          // Center Zone: Playback Controls & Progress Bar
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        isShuffleActive
                            ? Icons.shuffle_on_rounded
                            : Icons.shuffle_rounded,
                        color: isShuffleActive
                            ? tokens.accent
                            : tokens.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: tokens.textPrimary,
                        size: 24,
                      ),
                      onPressed: () => notifier.playPrev(),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          playerState.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 22,
                        ),
                        onPressed: () => playerState.isPlaying
                            ? notifier.player.pause()
                            : notifier.player.play(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: tokens.textPrimary,
                        size: 24,
                      ),
                      onPressed: () => notifier.playNext(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        playerState.repeatMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: isRepeatActive
                            ? tokens.accent
                            : tokens.textSecondary,
                        size: 20,
                      ),
                      onPressed: () => notifier.cycleRepeat(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: StreamBuilder<Duration>(
                    stream: notifier.player.positionStream,
                    builder: (context, snapshot) {
                      final pos = snapshot.data ?? Duration.zero;
                      final dur = Duration(seconds: song.duration);
                      return avpb.ProgressBar(
                        progress: pos,
                        total: dur,
                        onSeek: (d) => notifier.player.seek(d),
                        barHeight: 3,
                        thumbRadius: 5,
                        baseBarColor: tokens.outline.withValues(alpha: 0.3),
                        bufferedBarColor: tokens.outline.withValues(alpha: 0.5),
                        progressBarColor: tokens.accent,
                        thumbColor: tokens.accent,
                        timeLabelTextStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Right Zone: Lyrics, Queue, Sidebar Toggles & Volume
          SizedBox(
            width: 280,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.lyrics_outlined,
                    color: showRightPanel && rightPanelTab == 1
                        ? tokens.accent
                        : tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => onToggleRightPanel(1),
                  tooltip: 'Lyrics',
                ),
                IconButton(
                  icon: Icon(
                    Icons.queue_music_rounded,
                    color: showRightPanel && rightPanelTab == 2
                        ? tokens.accent
                        : tokens.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => onToggleRightPanel(2),
                  tooltip: 'Queue',
                ),
                IconButton(
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: tokens.textSecondary,
                    size: 18,
                  ),
                  onPressed: () => _openAppleMusicFullScreen(context),
                  tooltip: 'Fullscreen Player',
                ),
                const SizedBox(width: 4),
                _DesktopVolumeSlider(player: notifier.player),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Desktop Volume Slider
// =============================================================================

class _DesktopVolumeSlider extends StatefulWidget {
  final AudioPlayer player;
  const _DesktopVolumeSlider({required this.player});

  @override
  State<_DesktopVolumeSlider> createState() => _DesktopVolumeSliderState();
}

class _DesktopVolumeSliderState extends State<_DesktopVolumeSlider> {
  double _volume = 1.0;
  bool _muted = false;
  double _lastVol = 1.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.volume;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _muted || _volume == 0
                ? Icons.volume_off_rounded
                : _volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
            color: tokens.textSecondary,
            size: 20,
          ),
          onPressed: () {
            setState(() {
              if (_muted) {
                _muted = false;
                _volume = _lastVol > 0 ? _lastVol : 1.0;
              } else {
                _lastVol = _volume;
                _muted = true;
                _volume = 0;
              }
              widget.player.setVolume(_volume);
            });
          },
        ),
        SizedBox(
          width: 90,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: tokens.accent,
              inactiveTrackColor: tokens.outline.withValues(alpha: 0.3),
              thumbColor: tokens.accent,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _muted ? 0 : _volume,
              onChanged: (v) {
                setState(() {
                  _volume = v;
                  _muted = (v == 0);
                  widget.player.setVolume(v);
                });
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final tokens = widget.tokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? tokens.accent.withValues(alpha: 0.18)
                : _hovered
                ? tokens.outline.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                active ? widget.item.activeIcon : widget.item.icon,
                color: active
                    ? tokens.accent
                    : _hovered
                    ? tokens.textPrimary
                    : tokens.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: active
                      ? tokens.accent
                      : _hovered
                      ? tokens.textPrimary
                      : tokens.textSecondary,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Mobile Scaffold kept intact for phones
class _MobileScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final List<_NavItem> items;
  final List<Widget> screens;
  final bool meshEnabled;
  final bool meshIsPlaying;
  final bool isOffline;
  final AppThemeTokens tokens;

  const _MobileScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
    required this.meshEnabled,
    required this.meshIsPlaying,
    required this.isOffline,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (isOffline) _OfflineBanner(tokens: tokens),
        Expanded(
          child: IndexedStack(index: currentIndex, children: screens),
        ),
      ],
    );

    final bottomNav = NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onNavTap,
      backgroundColor: tokens.bgSurface.withValues(alpha: 0.90),
      indicatorColor: tokens.accent.withValues(alpha: 0.20),
      elevation: 0,
      height: 64,
      destinations: items
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon, color: tokens.textSecondary),
              selectedIcon: Icon(item.activeIcon, color: tokens.accent),
              label: item.label,
            ),
          )
          .toList(),
    );

    final body = Stack(
      children: [
        content,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MiniPlayer(),
              bottomNav,
            ],
          ),
        ),
      ],
    );

    return Scaffold(backgroundColor: tokens.bgBase, body: body);
  }
}

class _OfflineBanner extends StatelessWidget {
  final AppThemeTokens tokens;
  const _OfflineBanner({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orangeAccent.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: const Text(
        'Offline Mode — Playing downloaded music',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// =============================================================================
// Apple Music Desktop Fullscreen Player (Inspired by Apple Music Web/Mac UI)
// =============================================================================

class _AppleMusicDesktopFullScreenPlayer extends ConsumerWidget {
  const _AppleMusicDesktopFullScreenPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.watch(subsonicServiceProvider);
    final tokens = ThemeTokens.of(context);

    if (playerState.queue.isEmpty ||
        playerState.currentIndex >= playerState.queue.length) {
      return const SizedBox.shrink();
    }

    final song = playerState.queue[playerState.currentIndex];
    final imageUrl = service.getCoverArtUrl(song.coverArt);
    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive = playerState.repeatMode != LoopMode.off;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background: Ambient Blurred Artwork Gradient
          Positioned.fill(
            child: FluidBackground(
              isPlaying: playerState.isPlaying,
              colors: [
                tokens.bgBase,
                tokens.accent.withValues(alpha: 0.35),
                tokens.bgBase,
                Colors.black,
              ],
            ),
          ),

          // Main Fullscreen Content Container
          SafeArea(
            child: Column(
              children: [
                // Top Action Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Exit Fullscreen',
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 28,
                        ),
                        onPressed: () => showPlatformSheet(
                          context: context,
                          builder: (_) => OptionsMenu(song: song),
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Split View: Left (Cover + Title + Controls) & Right (Synced Lyrics)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Column: Artwork, Song Info, Seekbar, Controls
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 340x340 Cover Artwork
                              Container(
                                width: 340,
                                height: 340,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.60,
                                      ),
                                      blurRadius: 40,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 700,
                                    memCacheHeight: 700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Song Title & Artist / Album
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: -0.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${song.artist} \u2014 ${song.album}',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.70,
                                            ),
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      playerState.starredIds.contains(song.id)
                                          ? Icons.star_rounded
                                          : Icons.star_border_rounded,
                                      color: playerState.starredIds.contains(
                                        song.id,
                                      )
                                          ? tokens.accent
                                          : Colors.white.withValues(
                                              alpha: 0.70,
                                            ),
                                      size: 28,
                                    ),
                                    onPressed: () =>
                                        notifier.toggleStar(song.id),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Seek Bar
                              StreamBuilder<Duration>(
                                stream: notifier.player.positionStream,
                                builder: (context, snapshot) {
                                  final pos = snapshot.data ?? Duration.zero;
                                  final dur = Duration(seconds: song.duration);
                                  final remaining = dur - pos;

                                  return Column(
                                    children: [
                                      avpb.ProgressBar(
                                        progress: pos,
                                        total: dur,
                                        onSeek: (d) => notifier.player.seek(d),
                                        barHeight: 4,
                                        thumbRadius: 6,
                                        baseBarColor: Colors.white.withValues(
                                          alpha: 0.20,
                                        ),
                                        bufferedBarColor: Colors.white
                                            .withValues(alpha: 0.40),
                                        progressBarColor: Colors.white,
                                        thumbColor: Colors.white,
                                        timeLabelLocation:
                                            avpb.TimeLabelLocation.none,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatDuration(pos),
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.60,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '-${_formatDuration(remaining.isNegative ? Duration.zero : remaining)}',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.60,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 20),

                              // Playback Controls Row
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      isShuffleActive
                                          ? Icons.shuffle_on_rounded
                                          : Icons.shuffle_rounded,
                                      color: isShuffleActive
                                          ? tokens.accent
                                          : Colors.white.withValues(
                                              alpha: 0.60,
                                            ),
                                      size: 22,
                                    ),
                                    onPressed: () => notifier.toggleShuffle(),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.skip_previous_rounded,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                    onPressed: () => notifier.playPrev(),
                                  ),
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        playerState.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.black,
                                        size: 38,
                                      ),
                                      onPressed: () => playerState.isPlaying
                                          ? notifier.player.pause()
                                          : notifier.player.play(),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.skip_next_rounded,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                    onPressed: () => notifier.playNext(),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      playerState.repeatMode == LoopMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                      color: isRepeatActive
                                          ? tokens.accent
                                          : Colors.white.withValues(
                                              alpha: 0.60,
                                            ),
                                      size: 22,
                                    ),
                                    onPressed: () => notifier.cycleRepeat(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Volume Control
                              _DesktopVolumeSlider(player: notifier.player),
                            ],
                          ),
                        ),

                        const SizedBox(width: 64),

                        // Right Column: Apple Music Synced Lyrics View
                        Expanded(
                          flex: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: LyricsView(
                              song: song,
                              imageUrl: imageUrl,
                              isEmbedded: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

void _openAppleMusicFullScreen(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _AppleMusicDesktopFullScreenPlayer(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 250),
    ),
  );
}
