import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';

import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/playlist_details_screen.dart';
import '../screens/album_details_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/offline_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../services/replay_upload_service.dart';
import '../services/listening_log_service.dart';
import '../services/window_manager_service.dart';
import '../core/theme.dart';
import '../core/keyboard_shortcuts.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../utils/platform_utils.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/lyrics_pane.dart';
import '../player/now_playing_style.dart';
import '../player/player_controls.dart';
import '../player/queue_pane.dart';
import '../screens/now_playing_screen.dart';
import 'mini_player.dart';
import 'art/navi_icons.dart';
import 'create_playlist_dialog.dart';

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
    _NavItem(glyph: NaviGlyph.home, label: 'Home'),
    _NavItem(glyph: NaviGlyph.search, label: 'Search'),
    _NavItem(glyph: NaviGlyph.aiShuffle, label: 'AI Shuffle'),
    _NavItem(glyph: NaviGlyph.dashboard, label: 'Dashboard'),
    _NavItem(glyph: NaviGlyph.library, label: 'Library'),
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
    final isOffline = ref.watch(isOfflineProvider);

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
              isOffline: isOffline,
              tokens: tokens,
            );
          }

          return _MobileScaffold(
            currentIndex: _currentIndex,
            onNavTap: (i) => setState(() => _currentIndex = i),
            items: _items,
            screens: _screens,
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
  final bool isOffline;
  final AppThemeTokens tokens;

  const _Desktop3PaneScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
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
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(12),
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
      color: tokens.bgBase,
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

    return Scaffold(backgroundColor: tokens.bgBase, body: body);
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

  const _DesktopLeftSidebar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.tokens,
  });

  @override
  ConsumerState<_DesktopLeftSidebar> createState() =>
      _DesktopLeftSidebarState();
}

class _DesktopLeftSidebarState extends ConsumerState<_DesktopLeftSidebar> {
  String _libFilter = 'all'; // 'all', 'playlists', 'albums', 'downloaded'
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
      color: tokens.bgBase,
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
                  glyph: NaviGlyph.home,
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
                  glyph: NaviGlyph.aiShuffle,
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
                  glyph: NaviGlyph.dashboard,
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

                  // Filter Chips (Playlists, Albums, Downloaded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                          const SizedBox(width: 6),
                          _LibFilterChip(
                            label: 'Downloaded',
                            selected: _libFilter == 'downloaded',
                            onTap: () => setState(() => _libFilter = 'downloaded'),
                            tokens: tokens,
                          ),
                        ],
                      ),
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
                        // Downloaded songs, pinned first
                        if (_libFilter == 'all' || _libFilter == 'downloaded')
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: tokens.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.download_done_rounded,
                                color: tokens.accent,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Downloaded Songs',
                              style: TextStyle(
                                color: tokens.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Offline audio \u2022 Local storage',
                              style: TextStyle(color: tokens.textMuted, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => navigateInApp(context, const OfflineScreen()),
                          ),
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
  final int activeTab; // 0 About · 1 Lyrics · 2 Queue
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
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final palette = ref.watch(albumPaletteProvider);
    final style = NowPlayingStyle.fromTokens(tokens);

    return Container(
      width: 340,
      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(palette.base, tokens.bgSurface, 0.3)!, tokens.bgSurface],
          stops: const [0, 0.6],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: NowPlayingStyleScope(
        style: style,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  for (final (i, label) in const [(0, 'About'), (1, 'Lyrics'), (2, 'Queue')]) ...[
                    _PanelTab(label: label, selected: activeTab == i, onTap: () => onTabChanged(i)),
                    const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close panel',
                    icon: Icon(Icons.close_rounded, color: tokens.textSecondary, size: 20),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (activeTab) {
                  1 => LyricsPane(
                      key: const ValueKey('lyrics'),
                      style: style,
                      fontSize: 24,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    ),
                  2 => QueuePane(key: const ValueKey('queue'), style: style, showCurrent: true),
                  _ => _AboutTab(key: const ValueKey('about'), song: song, tokens: tokens),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PanelTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.textPrimary : t.textPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: naviText(13, FontWeight.w600, selected ? t.bgBase : t.textPrimary),
        ),
      ),
    );
  }
}

class _AboutTab extends ConsumerWidget {
  final Song song;
  final AppThemeTokens tokens;
  const _AboutTab({super.key, required this.song, required this.tokens});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final quality = qualityLabel(song);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Text(k, style: naviText(13, FontWeight.w500, tokens.textMuted))),
              Expanded(child: Text(v, style: naviText(13, FontWeight.w500, tokens.textPrimary))),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CoverImage(url: url, cacheKey: coverCacheKey(song), cacheWidth: 700),
          ),
        ),
        const SizedBox(height: 16),
        Text(song.title, style: naviText(22, FontWeight.w800, tokens.textPrimary)),
        const SizedBox(height: 2),
        Text(song.artist, style: naviText(15, FontWeight.w500, tokens.textSecondary)),
        if (quality != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: tokens.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(quality, style: naviText(12, FontWeight.w600, tokens.textSecondary)),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text('Credits', style: naviText(16, FontWeight.w700, tokens.textPrimary)),
        const SizedBox(height: 12),
        row('Artist', song.artist),
        if (song.composer.isNotEmpty) row('Composer', song.composer),
        row('Album', song.album),
        if (song.year > 0) row('Year', '${song.year}'),
        if (song.genre.isNotEmpty) row('Genre', song.genre),
        if (song.playCount > 0) row('Plays', '${song.playCount}'),
      ],
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
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final repeat = ref.watch(playerProvider.select((s) => s.repeatMode));
    final notifier = ref.read(playerProvider.notifier);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final t = tokens;

    Widget toggle(IconData icon, String tip, bool on, VoidCallback onTap) => _BarIcon(
          icon: icon,
          tooltip: tip,
          active: on,
          onTap: onTap,
        );

    return Container(
      height: 88,
      color: t.bgBase,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // ── Now playing ──────────────────────────────────────────────────
          SizedBox(
            width: 300,
            child: Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => openNowPlaying(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: 56, height: 56, cacheWidth: 168),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: naviText(14, FontWeight.w600, t.textPrimary)),
                      const SizedBox(height: 3),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: naviText(12.5, FontWeight.w500, t.textSecondary)),
                    ],
                  ),
                ),
                _BarIcon(
                  icon: starred ? Icons.star_rounded : Icons.star_outline_rounded,
                  tooltip: starred ? 'Remove from favourites' : 'Add to favourites',
                  active: starred,
                  onTap: () => notifier.toggleStar(song.id),
                ),
              ],
            ),
          ),

          // ── Transport + scrubber ─────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        toggle(Icons.shuffle_rounded, 'Shuffle', shuffle, notifier.toggleShuffle),
                        const SizedBox(width: 10),
                        _BarIcon(icon: Icons.fast_rewind_rounded, tooltip: 'Previous', size: 26, onTap: notifier.playPrev),
                        const SizedBox(width: 12),
                        _BarPlayButton(playing: playing, onTap: notifier.togglePlay),
                        const SizedBox(width: 12),
                        _BarIcon(icon: Icons.fast_forward_rounded, tooltip: 'Next', size: 26, onTap: notifier.playNext),
                        const SizedBox(width: 10),
                        toggle(
                          repeat == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          repeat == LoopMode.one ? 'Repeat one' : 'Repeat',
                          repeat != LoopMode.off,
                          notifier.cycleRepeat,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _BarScrubber(song: song, tokens: t),
                  ],
                ),
              ),
            ),
          ),

          // ── Panels, devices, volume ──────────────────────────────────────
          SizedBox(
            width: 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                toggle(Icons.format_quote_rounded, 'Lyrics', showRightPanel && rightPanelTab == 1,
                    () => onToggleRightPanel(1)),
                toggle(Icons.format_list_bulleted_rounded, 'Queue', showRightPanel && rightPanelTab == 2,
                    () => onToggleRightPanel(2)),
                toggle(Icons.info_outline_rounded, 'About this song', showRightPanel && rightPanelTab == 0,
                    () => onToggleRightPanel(0)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: VolumeBar(
                    player: notifier.player,
                    color: t.textPrimary,
                    trackColor: t.textPrimary.withValues(alpha: 0.18),
                    iconColor: t.textSecondary,
                  ),
                ),
                _BarIcon(icon: Icons.open_in_full_rounded, tooltip: 'Full screen player', size: 18,
                    onTap: () => openNowPlaying(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final double size;

  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 40,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: size, color: active ? t.accent : t.textSecondary),
              // Spotify's "on" dot under an active toggle.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: active ? 1 : 0,
                child: Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarPlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _BarPlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Tooltip(
      message: playing ? 'Pause (Space)' : 'Play (Space)',
      waitDuration: const Duration(milliseconds: 500),
      child: CupertinoClickable(
        onTap: onTap,
        scaleFactor: 0.92,
        semanticLabel: playing ? 'Pause' : 'Play',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: t.onAccent, size: 24),
        ),
      ),
    );
  }
}

class _BarScrubber extends ConsumerStatefulWidget {
  final Song song;
  final AppThemeTokens tokens;
  const _BarScrubber({required this.song, required this.tokens});

  @override
  ConsumerState<_BarScrubber> createState() => _BarScrubberState();
}

class _BarScrubberState extends ConsumerState<_BarScrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final player = ref.read(playerProvider.notifier).player;
    final total = widget.song.duration * 1000;
    final t = widget.tokens;
    final label = naviText(11.5, FontWeight.w500, t.textSecondary, tabular: true);
    return RepaintBoundary(
      child: PlaybackPosition(
        player: player,
        songId: widget.song.id,
        builder: (context, pos) {
          final f = _drag ?? (total > 0 ? pos.inMilliseconds / total : 0.0);
          return Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(formatClock(Duration(milliseconds: (f * total).round())),
                    textAlign: TextAlign.right, style: label),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElasticTrack(
                  value: f,
                  idleHeight: 4,
                  activeHeight: 6,
                  activeColor: _drag != null ? t.accent : t.textPrimary,
                  inactiveColor: t.textPrimary.withValues(alpha: 0.18),
                  semanticLabel: 'Playback position',
                  onChanged: (v) => setState(() => _drag = v),
                  onChangeEnd: (v) {
                    player.seek(Duration(milliseconds: (v * total).round()));
                    setState(() => _drag = null);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: Text(formatClock(Duration(seconds: widget.song.duration)), style: label),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final NaviGlyph glyph;
  final String label;
  final bool active;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.glyph,
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
              NaviIcon(
                widget.glyph,
                filled: active,
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

class _MobileScaffold extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final List<_NavItem> items;
  final List<Widget> screens;
  final bool isOffline;
  final AppThemeTokens tokens;

  const _MobileScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
    required this.isOffline,
    required this.tokens,
  });

  static const double _navHeight = 56;
  static const double _miniHeight = 70; // 62 card + 8 gap

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(playerProvider.select((s) => s.currentSong != null));
    final inset = MediaQuery.paddingOf(context).bottom;
    final chrome = (hasTrack ? _miniHeight : 0) + _navHeight + inset;

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: Stack(
        children: [
          Column(
            children: [
              if (isOffline) _OfflineBanner(tokens: tokens),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: chrome),
                  child: IndexedStack(index: currentIndex, children: screens),
                ),
              ),
            ],
          ),
          // Content fades into the bar instead of meeting a hard edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: chrome + 56,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      tokens.bgBase.withValues(alpha: 0),
                      tokens.bgBase.withValues(alpha: 0.86),
                      tokens.bgBase,
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                SizedBox(
                  height: _navHeight + inset,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: inset),
                    child: Row(
                      children: [
                        for (int i = 0; i < items.length; i++)
                          Expanded(
                            child: _TabButton(
                              item: items[i],
                              selected: i == currentIndex,
                              tokens: tokens,
                              onTap: () {
                                if (i != currentIndex) HapticFeedback.selectionClick();
                                onNavTap(i);
                              },
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
}

class _TabButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  const _TabButton({required this.item, required this.selected, required this.tokens, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? tokens.textPrimary : tokens.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: CupertinoClickable(
        onTap: onTap,
        scaleFactor: 0.9,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: NaviIcon(item.glyph,
                  key: ValueKey(selected), color: color, size: 25, filled: selected),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: naviText(10.5, selected ? FontWeight.w700 : FontWeight.w500, color),
            ),
          ],
        ),
      ),
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
  final NaviGlyph glyph;
  final String label;

  const _NavItem({
    required this.glyph,
    required this.label,
  });
}
