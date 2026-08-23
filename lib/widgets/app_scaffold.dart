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
import '../screens/album_details_screen.dart';
import '../screens/settings_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../services/replay_upload_service.dart';
import '../services/listening_log_service.dart';
import '../services/window_manager_service.dart';
import '../core/theme.dart';
import '../core/palette_cache.dart';
import '../core/keyboard_shortcuts.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../fluid_background.dart';
import '../utils/platform_utils.dart';
import '../lyrics/views/lyrics_view.dart';
import 'mini_player.dart';
import 'options_menu.dart';
import 'create_playlist_dialog.dart';
import 'desktop_dialogs.dart';

// =============================================================================
// Desktop Center Pane Navigator & App Navigation Helper
// =============================================================================

final GlobalKey<NavigatorState> desktopNavigatorKey = GlobalKey<NavigatorState>();

void navigateInApp(BuildContext context, Widget screen) {
  if (PlatformUtils.isDesktop) {
    desktopNavigatorKey.currentState?.push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 160),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

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
          final useDesktopLayout = PlatformUtils.isDesktop &&
              (PlatformUtils.prefersSidebarNavigation ||
                  constraints.maxWidth >= PlatformUtils.kDesktopBreakpoint);

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

    final centerContent = Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          topHeader,
          if (widget.isOffline) _OfflineBanner(tokens: tokens),
          Expanded(
            child: Navigator(
              key: desktopNavigatorKey,
              onGenerateRoute: (settings) {
                return MaterialPageRoute(
                  builder: (_) => _DesktopTabHost(
                    currentIndex: widget.currentIndex,
                    screens: widget.screens,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final workspaceBody = Container(
      color: const Color(0xFF000000),
      child: Row(
        children: [
          leftSidebar,
          Expanded(child: centerContent),
          ?rightPanel,
        ],
      ),
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

    return Scaffold(backgroundColor: const Color(0xFF000000), body: body);
  }
}

// =============================================================================
// Desktop Tab Host
// =============================================================================

class _DesktopTabHost extends StatelessWidget {
  final int currentIndex;
  final List<Widget> screens;

  const _DesktopTabHost({
    required this.currentIndex,
    required this.screens,
  });

  @override
  Widget build(BuildContext context) {
    if (currentIndex >= 0 && currentIndex < screens.length) {
      return screens[currentIndex];
    }
    return const HomeScreen();
  }
}

// =============================================================================
// Desktop Top Header Bar (Navigation History, Universal Search, Profile)
// =============================================================================

class _DesktopTopHeader extends ConsumerStatefulWidget {
  final ValueChanged<int> onNavTap;
  final AppThemeTokens tokens;

  const _DesktopTopHeader({
    required this.onNavTap,
    required this.tokens,
  });

  @override
  ConsumerState<_DesktopTopHeader> createState() => _DesktopTopHeaderState();
}

class _DesktopTopHeaderState extends ConsumerState<_DesktopTopHeader> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);

    if (_controller.text != searchQuery) {
      _controller.value = _controller.value.copyWith(
        text: searchQuery,
        selection: TextSelection.collapsed(offset: searchQuery.length),
      );
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212).withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          // Navigation History Button (Back)
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () {
                if (desktopNavigatorKey.currentState?.canPop() == true) {
                  desktopNavigatorKey.currentState?.pop();
                } else if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              tooltip: 'Go Back',
            ),
          ),
          const SizedBox(width: 8),

          // Forward button
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.50),
                size: 22,
              ),
              onPressed: null,
            ),
          ),
          const SizedBox(width: 16),

          // Central Universal Search Input Bar (Spotify Style)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _controller,
                    onTap: () {
                      if (desktopNavigatorKey.currentState?.canPop() == true) {
                        desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                      }
                      widget.onNavTap(1);
                    },
                    onChanged: (val) {
                      if (desktopNavigatorKey.currentState?.canPop() == true) {
                        desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                      }
                      widget.onNavTap(1);
                      ref.read(searchQueryProvider.notifier).state = val;
                    },
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'What do you want to play?',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.white.withValues(alpha: 0.65),
                        size: 20,
                      ),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: Colors.white70,
                                size: 16,
                              ),
                              onPressed: () {
                                _controller.clear();
                                ref.read(searchQueryProvider.notifier).state = '';
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF242424),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: Color(0xFF1DB954),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Settings Button (User profile / options style)
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.settings_outlined,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: () => navigateInApp(context, const SettingsScreen()),
              tooltip: 'Settings',
            ),
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
      width: 290,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: const Color(0xFF000000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation Box (Spotify style card)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF121212),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Brand Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.graphic_eq_rounded,
                        color: Color(0xFF1DB954),
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'NaviVibe',
                        style: tokens.textStyle(19, FontWeight.w800, Colors.white),
                      ),
                    ],
                  ),
                ),

                // Primary Navigation Menu: Home, AI Shuffle, Dashboard
                _SidebarNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  active: widget.currentIndex == 0,
                  tokens: tokens,
                  onTap: () {
                    if (desktopNavigatorKey.currentState?.canPop() == true) {
                      desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    }
                    widget.onTap(0);
                  },
                ),
                _SidebarNavItem(
                  icon: Icons.auto_awesome_outlined,
                  activeIcon: Icons.auto_awesome,
                  label: 'AI Shuffle',
                  active: widget.currentIndex == 2,
                  tokens: tokens,
                  onTap: () {
                    if (desktopNavigatorKey.currentState?.canPop() == true) {
                      desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    }
                    widget.onTap(2);
                  },
                ),
                _SidebarNavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  active: widget.currentIndex == 3,
                  tokens: tokens,
                  onTap: () {
                    if (desktopNavigatorKey.currentState?.canPop() == true) {
                      desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                    }
                    widget.onTap(3);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Lower "Your Library" Box (Spotify style card)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spotify-style "Your Library" Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
                    child: Row(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              if (desktopNavigatorKey.currentState?.canPop() == true) {
                                desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
                              }
                              widget.onTap(4); // Open full LibraryScreen
                            },
                            child: Row(
                              children: [
                                Icon(
                                  Icons.library_music_rounded,
                                  color: widget.currentIndex == 4 ? tokens.accent : tokens.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Your Library',
                                  style: TextStyle(
                                    color: widget.currentIndex == 4 ? tokens.accent : tokens.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.add_rounded,
                            color: tokens.textSecondary,
                            size: 22,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                          fillColor: tokens.bgElevated.withValues(alpha: 0.60),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                                      navigateInApp(
                                        context,
                                        PlaylistDetailsScreen(
                                          playlist: playlist,
                                        ),
                                      );
                                    },
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => const SizedBox.shrink(),
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
                                        errorWidget: (_, _, _) => Container(
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
                                    onTap: () {
                                      navigateInApp(
                                        context,
                                        AlbumDetailsScreen(album: album),
                                      );
                                    },
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
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
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        border: Border(
          top: BorderSide(color: Color(0xFF282828), width: 1),
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
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.artist,
                            style: const TextStyle(
                              color: Color(0xFFB3B3B3),
                              fontSize: 11,
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
                        ? const Color(0xFF1DB954)
                        : Colors.white70,
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
                            ? const Color(0xFF1DB954)
                            : Colors.white60,
                        size: 20,
                      ),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      onPressed: () => notifier.playPrev(),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
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
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 26,
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
                            ? const Color(0xFF1DB954)
                            : Colors.white60,
                        size: 20,
                      ),
                      onPressed: () => notifier.cycleRepeat(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: StreamBuilder<Duration>(
                    stream: notifier.player.positionStream,
                    builder: (context, snapshot) {
                      final pos = snapshot.data ?? Duration.zero;
                      final dur = Duration(seconds: song.duration);
                      return avpb.ProgressBar(
                        progress: pos,
                        total: dur,
                        onSeek: (d) => notifier.player.seek(d),
                        barHeight: 4,
                        thumbRadius: 5,
                        baseBarColor: const Color(0xFF4D4D4D),
                        bufferedBarColor: const Color(0xFF707070),
                        progressBarColor: Colors.white,
                        thumbColor: Colors.white,
                        timeLabelTextStyle: const TextStyle(
                          color: Color(0xFFB3B3B3),
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
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
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
                active ? widget.activeIcon : widget.icon,
                color: active
                    ? tokens.accent
                    : _hovered
                    ? tokens.textPrimary
                    : tokens.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                widget.label,
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
    return Consumer(
      builder: (context, ref, _) {
        final playerState = ref.watch(playerProvider);
        final hasTrack = playerState.queue.isNotEmpty &&
            playerState.currentIndex < playerState.queue.length;

        // System gesture inset (home bar on Android / iOS).
        final bottomInset = MediaQuery.of(context).padding.bottom;

        // Exact heights — no Flutter NavigationBar surprises.
        const double kNavBarHeight = 58.0;
        const double kMiniPlayerHeight = 72.0;

        final double bottomOffset =
            (hasTrack ? kMiniPlayerHeight : 0.0) + kNavBarHeight + bottomInset;

        // ── Screen content (scrolls behind floating bar) ─────────────────────
        final content = Column(
          children: [
            if (isOffline) _OfflineBanner(tokens: tokens),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomOffset),
                child: IndexedStack(index: currentIndex, children: screens),
              ),
            ),
          ],
        );

        // ── Hand-built Spotify-style bottom tab bar ───────────────────────────
        // We build this ourselves so we have 100% control over the height.
        // Flutter's NavigationBar adds internal safe-area padding on top of
        // whatever height you specify in NavigationBarThemeData, which is
        // exactly what caused the "black gap above icons" bug.
        final bottomNav = Container(
          color: tokens.bgSurface.withValues(alpha: 0.97),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thin separator line between MiniPlayer and tab bar
              Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.white.withValues(alpha: 0.10),
              ),
              SizedBox(
                height: kNavBarHeight,
                child: Row(
                  children: List.generate(items.length, (i) {
                    final item = items[i];
                    final selected = i == currentIndex;
                    return Expanded(
                      child: InkWell(
                        onTap: () => onNavTap(i),
                        splashColor: tokens.accent.withValues(alpha: 0.12),
                        highlightColor: Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Selected indicator pill
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              width: selected ? 40 : 0,
                              height: 2,
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: tokens.accent,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            Icon(
                              selected ? item.activeIcon : item.icon,
                              color: selected
                                  ? tokens.accent
                                  : tokens.textSecondary,
                              size: 22,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: selected
                                    ? tokens.accent
                                    : tokens.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // System gesture strip — same color as bar, exactly bottomInset tall.
              ColoredBox(
                color: tokens.bgSurface.withValues(alpha: 0.97),
                child: SizedBox(width: double.infinity, height: bottomInset),
              ),
            ],
          ),
        );

        // ── Stack: content behind, player + nav bar floating at bottom ────────
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
      },
    );
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

class _AppleMusicDesktopFullScreenPlayer extends ConsumerStatefulWidget {
  const _AppleMusicDesktopFullScreenPlayer();

  @override
  ConsumerState<_AppleMusicDesktopFullScreenPlayer> createState() =>
      _AppleMusicDesktopFullScreenPlayerState();
}

class _AppleMusicDesktopFullScreenPlayerState
    extends ConsumerState<_AppleMusicDesktopFullScreenPlayer> {
  List<Color>? _extractedColors;
  String? _currentSongId;

  @override
  void initState() {
    super.initState();
    _syncPalette();
  }

  void _syncPalette() {
    final playerState = ref.read(playerProvider);
    if (playerState.queue.isEmpty ||
        playerState.currentIndex >= playerState.queue.length) {
      return;
    }
    final song = playerState.queue[playerState.currentIndex];
    if (_currentSongId == song.id && _extractedColors != null) return;
    _currentSongId = song.id;

    final cached = PaletteCache.instance.getColorsFor(song.id);
    if (cached != null) {
      _extractedColors = cached;
    } else {
      final service = ref.read(subsonicServiceProvider);
      final url = service.getCoverArtUrl(song.coverArt);
      PaletteCache.instance.extractAndCache(song.id, url).then((colors) {
        if (mounted && _currentSongId == song.id) {
          setState(() => _extractedColors = colors);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final service = ref.watch(subsonicServiceProvider);
    final tokens = ThemeTokens.of(context);

    if (playerState.queue.isEmpty ||
        playerState.currentIndex >= playerState.queue.length) {
      return const SizedBox.shrink();
    }

    final song = playerState.queue[playerState.currentIndex];
    if (_currentSongId != song.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPalette();
      });
    }

    final imageUrl = service.getCoverArtUrl(song.coverArt);
    final isShuffleActive = playerState.shuffleMode;
    final isRepeatActive = playerState.repeatMode != LoopMode.off;

    final activeColors = _extractedColors ??
        PaletteCache.instance.peekColorsFor(song.id) ??
        [
          tokens.accent,
          const Color(0xFF8B5CF6),
          const Color(0xFF06B6D4),
          const Color(0xFFEC4899),
        ];

    final primaryColor = activeColors[0];
    final vibrantColor = activeColors.length > 1 ? activeColors[1] : primaryColor;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (playerState.isPlaying) {
            notifier.player.pause();
          } else {
            notifier.player.play();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF060606),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // ── Apple Music Animated Live Canvas (Cover Art Texture + Fluid Mesh)
              Positioned.fill(
                child: AppleMusicLiveBackground(
                  imageUrl: imageUrl,
                  colors: activeColors,
                  isPlaying: playerState.isPlaying,
                ),
              ),

              // ── Main Fullscreen UI Layer ───────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    // Top Action Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => Navigator.pop(context),
                              tooltip: 'Exit Fullscreen (Esc)',
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => showPlatformSheet(
                                context: context,
                                builder: (_) => OptionsMenu(song: song),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Main Split View: Left (Cover + Controls) & Right (Lyrics)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 56),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Column: Artwork, Song Info, Seekbar, Controls
                            Expanded(
                              flex: 5,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Cover Artwork with 3D Ambient Drop Shadow
                                  Container(
                                    width: 380,
                                    height: 380,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: vibrantColor.withValues(alpha: 0.60),
                                          blurRadius: 56,
                                          spreadRadius: 4,
                                          offset: const Offset(0, 18),
                                        ),
                                        const BoxShadow(
                                          color: Colors.black54,
                                          blurRadius: 28,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 760,
                                        memCacheHeight: 760,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 26),

                                  // Song Title & Artist / Favorite Toggle
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 26,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -0.8,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${song.artist} \u2014 ${song.album}',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.75),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.graphic_eq_rounded,
                                                    size: 12,
                                                    color: Colors.white.withValues(alpha: 0.85),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Lossless',
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.85),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          playerState.starredIds.contains(song.id)
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          color: playerState.starredIds.contains(song.id)
                                              ? const Color(0xFF1DB954)
                                              : Colors.white70,
                                          size: 28,
                                        ),
                                        onPressed: () => notifier.toggleStar(song.id),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

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
                                            baseBarColor: Colors.white.withValues(alpha: 0.25),
                                            bufferedBarColor: Colors.white.withValues(alpha: 0.40),
                                            progressBarColor: Colors.white,
                                            thumbColor: Colors.white,
                                            timeLabelLocation: avpb.TimeLabelLocation.none,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatDuration(pos),
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.70),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                '-${_formatDuration(remaining.isNegative ? Duration.zero : remaining)}',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.70),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
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
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isShuffleActive
                                              ? Icons.shuffle_on_rounded
                                              : Icons.shuffle_rounded,
                                          color: isShuffleActive
                                              ? const Color(0xFF1DB954)
                                              : Colors.white70,
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
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 16,
                                              offset: Offset(0, 6),
                                            ),
                                          ],
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
                                              ? const Color(0xFF1DB954)
                                              : Colors.white70,
                                          size: 22,
                                        ),
                                        onPressed: () => notifier.cycleRepeat(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Volume Slider
                                  _DesktopVolumeSlider(player: notifier.player),
                                ],
                              ),
                            ),

                            const SizedBox(width: 64),

                            // Right Column: Apple Music Synced Lyrics Glass View
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
        ),
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
