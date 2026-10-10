import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/keyboard_shortcuts.dart';
import '../core/theme.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/lyrics_pane.dart';
import '../player/now_playing_style.dart';
import '../player/player_controls.dart';
import '../player/queue_pane.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/stats/stats_screen.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/library/albums_page.dart';
import '../screens/library/playlists_page.dart';
import '../screens/library/songs_page.dart';
import '../screens/now_playing_screen.dart';
import '../screens/playlist_details_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../services/listening_log_service.dart';
import '../services/replay_upload_service.dart';
import '../services/window_manager_service.dart';
import '../utils/platform_utils.dart';
import 'cover_art.dart';
import 'create_playlist_dialog.dart';
import 'mini_player.dart';

// =============================================================================
// App shell.
//
// Phone: Apple Music's structure — each tab keeps its own navigation stack, so
// the translucent tab bar and the floating mini player stay on screen while
// you drill into albums and playlists. Back (gesture or button) pops within
// the tab; tapping the current tab returns to its root.
//
// Desktop: Apple Music for Mac — a sidebar (search, destinations, library,
// playlists), the content pane, an optional Now Playing side panel, and the
// player bar along the bottom.
// =============================================================================

/// The app's top-level destinations, in Apple Music's order (Search last).
/// Everything that switches tabs refers to these by name, never by position.
enum AppTab {
  home('Home', CupertinoIcons.house, CupertinoIcons.house_fill),
  shuffle('Shuffle', CupertinoIcons.sparkles, CupertinoIcons.sparkles),
  stats('Stats', CupertinoIcons.chart_bar, CupertinoIcons.chart_bar_fill),
  library('Library', CupertinoIcons.music_albums, CupertinoIcons.music_albums_fill),
  search('Search', CupertinoIcons.search, CupertinoIcons.search);

  const AppTab(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;

  Widget get screen => switch (this) {
        AppTab.home => const HomeScreen(),
        AppTab.shuffle => const AiShuffleScreen(),
        AppTab.stats => const StatsScreen(),
        AppTab.library => const LibraryScreen(),
        AppTab.search => const SearchScreen(),
      };
}

/// Content navigator for the desktop centre pane.
final GlobalKey<NavigatorState> desktopNavigatorKey = GlobalKey<NavigatorState>();

/// One navigator per phone tab (see [_PhoneShell]).
final Map<AppTab, GlobalKey<NavigatorState>> _tabNavigators = {
  for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>(debugLabel: 'tab-${tab.name}'),
};

/// The phone tab currently showing; used to route pushes into its stack.
AppTab _activeTab = AppTab.home;

/// Opens [screen] inside the app chrome: the desktop content pane, or the
/// active phone tab's stack (so the tab bar and mini player stay visible).
/// Works from sheets and dialogs too, since it doesn't depend on [context]'s
/// own navigator.
void navigateInApp(BuildContext context, Widget screen) {
  final route = MaterialPageRoute<void>(builder: (_) => screen);
  final target = PlatformUtils.isDesktop
      ? desktopNavigatorKey.currentState
      : _tabNavigators[_activeTab]?.currentState;
  (target ?? Navigator.of(context)).push(route);
}

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> with WidgetsBindingObserver, WindowLifecycleMixin {
  AppTab _tab = AppTab.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(replayUploadServiceProvider).performUploadIfNeeded();
      // Mirror the library now rather than when the Library tab first opens:
      // Home, Stats, Replay and Shuffle resolve titles from it.
      ref.read(allSongsProvider.future).ignore();
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

  void _select(AppTab tab) {
    if (tab == _tab) {
      // Re-selecting the current tab returns to its root (iOS behaviour).
      final nav = PlatformUtils.isDesktop ? desktopNavigatorKey.currentState : _tabNavigators[tab]?.currentState;
      nav?.popUntil((r) => r.isFirst);
      return;
    }
    HapticFeedback.selectionClick();
    if (PlatformUtils.isDesktop) desktopNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() => _tab = tab);
    _activeTab = tab;
    _desktopTab.value = tab;
  }

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    return NaviKeyboardShortcuts(
      child: LayoutBuilder(
        builder: (context, c) {
          final desktop = PlatformUtils.isDesktop &&
              (PlatformUtils.prefersSidebarNavigation || c.maxWidth >= PlatformUtils.kDesktopBreakpoint);
          return desktop
              ? _DesktopShell(tab: _tab, onSelect: _select, offline: offline)
              : _PhoneShell(tab: _tab, onSelect: _select, offline: offline);
        },
      ),
    );
  }
}

// ── Phone ───────────────────────────────────────────────────────────────────

class _PhoneShell extends ConsumerWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  final bool offline;

  const _PhoneShell({required this.tab, required this.onSelect, required this.offline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final active = _tabNavigators[tab]!;
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Stack(
        children: [
          // System back pops inside the active tab before leaving the app.
          NavigatorPopHandler(
            onPopWithResult: (_) => active.currentState?.maybePop(),
            child: IndexedStack(
              index: tab.index,
              children: [
                for (final destination in AppTab.values)
                  Navigator(
                    key: _tabNavigators[destination],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => destination.screen),
                  ),
              ],
            ),
          ),
          if (offline) const Positioned(top: 0, left: 0, right: 0, child: _OfflineBanner()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                _TabBar(tab: tab, onSelect: onSelect),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS tab bar: translucent material over the content, hairline on top, the
/// selected tab tinted with the accent.
class _TabBar extends StatelessWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  const _TabBar({required this.tab, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 50 + bottom,
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: t.bgBase.withValues(alpha: 0.78),
            border: Border(top: BorderSide(color: t.outline, width: 0.5)),
          ),
          child: Row(
            children: [
              for (final destination in AppTab.values)
                Expanded(
                  child: _TabButton(
                    tab: destination,
                    selected: destination == tab,
                    onTap: () => onSelect(destination),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final color = selected ? t.accent : t.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? tab.activeIcon : tab.icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(tab.label, style: t.caption2.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SafeArea(
      bottom: false,
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: Space.xs),
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
          decoration: BoxDecoration(color: t.bgElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.wifi_slash, size: 13, color: t.warning),
              const SizedBox(width: Space.xs + 2),
              Text('Offline — playing downloads', style: t.caption1.copyWith(color: t.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Desktop ─────────────────────────────────────────────────────────────────

/// Which part of the Now Playing side panel is showing.
enum _Panel { about, lyrics, queue }

class _DesktopShell extends ConsumerStatefulWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  final bool offline;
  const _DesktopShell({required this.tab, required this.onSelect, required this.offline});

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  _Panel? _panel = _Panel.about;

  void _togglePanel(_Panel p) => setState(() => _panel = _panel == p ? null : p);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final hasSong = ref.watch(playerProvider.select((s) => s.currentSong != null));
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _Sidebar(tab: widget.tab, onSelect: widget.onSelect),
                Container(width: 0.5, color: t.separatorOpaque),
                Expanded(
                  child: Column(
                    children: [
                      if (widget.offline) const _OfflineBanner(),
                      Expanded(
                        child: ClipRect(
                          child: Navigator(
                            key: desktopNavigatorKey,
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              builder: (_) => const _DesktopTabHost(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasSong && _panel != null) ...[
                  Container(width: 0.5, color: t.separatorOpaque),
                  _SidePanel(panel: _panel!, onChange: (p) => setState(() => _panel = p), onClose: () => setState(() => _panel = null)),
                ],
              ],
            ),
          ),
          if (hasSong) _PlayerBar(panel: _panel, onTogglePanel: _togglePanel),
        ],
      ),
    );
  }
}

/// The desktop navigator's first route is created once, so the selected tab
/// reaches it through this listenable rather than through constructor args.
final ValueNotifier<AppTab> _desktopTab = ValueNotifier(AppTab.home);

class _DesktopTabHost extends StatelessWidget {
  const _DesktopTabHost();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppTab>(
        valueListenable: _desktopTab,
        builder: (_, tab, _) => KeyedSubtree(key: ValueKey(tab), child: tab.screen),
      );
}

class _Sidebar extends ConsumerStatefulWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  const _Sidebar({required this.tab, required this.onSelect});

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final playlists = ref.watch(playlistsProvider).asData?.value ?? const [];
    final service = ref.read(subsonicServiceProvider);

    return Container(
      width: 248,
      color: t.bgSurface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.lg),
        children: [
          CupertinoSearchTextField(
            controller: _search,
            placeholder: 'Search',
            style: t.subheadline.copyWith(color: t.textPrimary),
            backgroundColor: t.fill,
            itemColor: t.textSecondary,
            onChanged: (q) {
              ref.read(searchQueryProvider.notifier).state = q;
              if (widget.tab != AppTab.search) widget.onSelect(AppTab.search);
            },
          ),
          const SizedBox(height: Space.lg),
          for (final dest in const [AppTab.home, AppTab.shuffle, AppTab.stats])
            _SidebarRow(
              icon: widget.tab == dest ? dest.activeIcon : dest.icon,
              label: dest.label,
              selected: widget.tab == dest,
              onTap: () => widget.onSelect(dest),
            ),
          const _SidebarHeader('Library'),
          _SidebarRow(
            icon: CupertinoIcons.music_albums,
            label: 'Library',
            selected: widget.tab == AppTab.library,
            onTap: () => widget.onSelect(AppTab.library),
          ),
          _SidebarRow(
            icon: CupertinoIcons.music_note_list,
            label: 'Playlists',
            onTap: () => navigateInApp(context, const PlaylistsPage()),
          ),
          _SidebarRow(
            icon: CupertinoIcons.square_stack,
            label: 'Albums',
            onTap: () => navigateInApp(context, const AlbumsPage()),
          ),
          _SidebarRow(
            icon: CupertinoIcons.music_note,
            label: 'Songs',
            onTap: () => navigateInApp(context, const SongsPage()),
          ),
          _SidebarRow(
            icon: CupertinoIcons.arrow_down_circle,
            label: 'Downloaded',
            onTap: () => navigateInApp(context, const SongsPage(downloadedOnly: true)),
          ),
          _SidebarHeader(
            'Playlists',
            action: IconButton(
              tooltip: 'New Playlist',
              visualDensity: VisualDensity.compact,
              icon: Icon(CupertinoIcons.add, size: 18, color: t.textSecondary),
              onPressed: () => showDialog(context: context, builder: (_) => const CreatePlaylistDialog()),
            ),
          ),
          for (final p in playlists)
            _SidebarRow(
              art: CoverArt(
                url: (p.coverArt ?? '').isEmpty ? null : service.getCoverArtUrl(p.coverArt),
                size: 22,
                radius: Radii.thumb,
                placeholderIcon: CupertinoIcons.music_note_list,
              ),
              label: p.name,
              onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p)),
            ),
          const SizedBox(height: Space.lg),
          _SidebarRow(
            icon: CupertinoIcons.gear,
            label: 'Settings',
            onTap: () => navigateInApp(context, const SettingsScreen()),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SidebarHeader(this.title, {this.action});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xl, 0, Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.footnote.copyWith(fontWeight: FontWeight.w600))),
          ?action,
        ],
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  final IconData? icon;
  final Widget? art;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarRow({this.icon, this.art, required this.label, this.selected = false, required this.onTap});

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          decoration: BoxDecoration(
            color: widget.selected ? t.bgOverlay : (_hovered ? t.fill : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              widget.art ?? Icon(widget.icon, size: 18, color: t.accent),
              const SizedBox(width: Space.sm + 2),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.subheadline.copyWith(color: t.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Now Playing side panel: About (artwork + credits), Lyrics, Queue.
class _SidePanel extends ConsumerWidget {
  final _Panel panel;
  final ValueChanged<_Panel> onChange;
  final VoidCallback onClose;

  const _SidePanel({required this.panel, required this.onChange, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final style = NowPlayingStyle.fromTokens(t);
    return SizedBox(
      width: 320,
      child: NowPlayingStyleScope(
        style: style,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.xs, Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSlidingSegmentedControl<_Panel>(
                      groupValue: panel,
                      backgroundColor: t.fill,
                      thumbColor: t.bgOverlay,
                      onValueChanged: (p) => p == null ? null : onChange(p),
                      children: {
                        for (final (p, label) in const [(_Panel.about, 'About'), (_Panel.lyrics, 'Lyrics'), (_Panel.queue, 'Queue')])
                          p: Text(label, style: t.footnote.copyWith(color: t.textPrimary)),
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(CupertinoIcons.xmark, size: 16, color: t.textSecondary),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.standard,
                child: switch (panel) {
                  _Panel.lyrics => LyricsPane(
                      key: const ValueKey('lyrics'),
                      style: style,
                      fontSize: 24,
                      padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, 0),
                    ),
                  _Panel.queue => QueuePane(key: const ValueKey('queue'), style: style, showCurrent: true),
                  _Panel.about => _AboutSong(key: const ValueKey('about'), song: song),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSong extends ConsumerWidget {
  final Song song;
  const _AboutSong({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final quality = qualityLabel(song);
    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, child: Text(k, style: t.footnote)),
              Expanded(child: Text(v, style: t.footnote.copyWith(color: t.textPrimary))),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.xxl),
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.hero),
            child: CoverImage(url: url, cacheKey: coverCacheKey(song), cacheWidth: 640),
          ),
        ),
        const SizedBox(height: Space.lg),
        Text(song.title, style: t.title3),
        const SizedBox(height: 2),
        Text(song.artist, style: t.body.copyWith(color: t.accent)),
        if (quality != null) ...[
          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
              decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.thumb)),
              child: Text(quality, style: t.caption1),
            ),
          ),
        ],
        const SizedBox(height: Space.xxl),
        Text('Credits', style: t.headline),
        const SizedBox(height: Space.md),
        fact('Artist', song.artist),
        if (song.composer.isNotEmpty) fact('Composer', song.composer),
        fact('Album', song.album),
        if (song.year > 0) fact('Year', '${song.year}'),
        if (song.genre.isNotEmpty) fact('Genre', song.genre),
        if (song.playCount > 0) fact('Plays', '${song.playCount}'),
      ],
    );
  }
}

/// Desktop player bar: now playing, transport + scrubber, panels + volume.
class _PlayerBar extends ConsumerWidget {
  final _Panel? panel;
  final ValueChanged<_Panel> onTogglePanel;
  const _PlayerBar({required this.panel, required this.onTogglePanel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final starred = ref.watch(playerProvider.select((s) => s.starredIds.contains(song.id)));
    final shuffle = ref.watch(playerProvider.select((s) => s.shuffleMode));
    final repeat = ref.watch(playerProvider.select((s) => s.repeatMode));
    final n = ref.read(playerProvider.notifier);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: t.bgSurface,
        border: Border(top: BorderSide(color: t.separatorOpaque, width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => openNowPlaying(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.cover),
                      child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: 52, height: 52, cacheWidth: 156),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                    ],
                  ),
                ),
                _BarButton(
                  icon: starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  tooltip: starred ? 'Remove from Favorites' : 'Favorite',
                  active: starred,
                  onTap: () => n.toggleStar(song.id),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BarButton(icon: CupertinoIcons.shuffle, tooltip: 'Shuffle', active: shuffle, onTap: n.toggleShuffle),
                        const SizedBox(width: Space.sm),
                        _BarButton(icon: CupertinoIcons.backward_fill, tooltip: 'Previous', size: 22, onTap: n.playPrev),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                          tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                          size: 28,
                          prominent: true,
                          onTap: n.togglePlay,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(icon: CupertinoIcons.forward_fill, tooltip: 'Next', size: 22, onTap: n.playNext),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: repeat == LoopMode.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
                          tooltip: switch (repeat) {
                            LoopMode.off => 'Repeat',
                            LoopMode.all => 'Repeat queue',
                            LoopMode.one => 'Repeat this song',
                          },
                          active: repeat != LoopMode.off,
                          onTap: n.cycleRepeat,
                        ),
                      ],
                    ),
                    _BarScrubber(song: song),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _BarButton(icon: CupertinoIcons.quote_bubble, tooltip: 'Lyrics', active: panel == _Panel.lyrics, onTap: () => onTogglePanel(_Panel.lyrics)),
                _BarButton(icon: CupertinoIcons.list_bullet, tooltip: 'Queue', active: panel == _Panel.queue, onTap: () => onTogglePanel(_Panel.queue)),
                _BarButton(icon: CupertinoIcons.info, tooltip: 'About this song', active: panel == _Panel.about, onTap: () => onTogglePanel(_Panel.about)),
                const SizedBox(width: Space.sm),
                SizedBox(
                  width: 110,
                  child: VolumeBar(player: n.player, color: t.textPrimary, trackColor: t.fill, iconColor: t.textSecondary),
                ),
                _BarButton(icon: CupertinoIcons.arrow_up_left_arrow_down_right, tooltip: 'Full-screen player', size: 16, onTap: () => openNowPlaying(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool prominent;
  final double size;

  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.prominent = false,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final color = active ? t.accent : (prominent ? t.textPrimary : t.textSecondary);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: CupertinoClickable(
        onTap: onTap,
        scaleFactor: 0.9,
        semanticLabel: tooltip,
        child: SizedBox(
          width: prominent ? 44 : 36,
          height: 40,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _BarScrubber extends ConsumerStatefulWidget {
  final Song song;
  const _BarScrubber({required this.song});

  @override
  ConsumerState<_BarScrubber> createState() => _BarScrubberState();
}

class _BarScrubberState extends ConsumerState<_BarScrubber> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final player = ref.read(playerProvider.notifier).player;
    final total = widget.song.duration * 1000;
    final label = t.caption1.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
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
                child: Text(formatClock(Duration(milliseconds: (f * total).round())), textAlign: TextAlign.right, style: label),
              ),
              const SizedBox(width: Space.sm + 2),
              Expanded(
                child: ElasticTrack(
                  value: f,
                  idleHeight: 4,
                  activeHeight: 6,
                  activeColor: t.textPrimary,
                  inactiveColor: t.fill,
                  semanticLabel: 'Playback position',
                  onChanged: (v) => setState(() => _drag = v),
                  onChangeEnd: (v) {
                    player.seek(Duration(milliseconds: (v * total).round()));
                    setState(() => _drag = null);
                  },
                ),
              ),
              const SizedBox(width: Space.sm + 2),
              SizedBox(width: 44, child: Text(formatClock(Duration(seconds: widget.song.duration)), style: label)),
            ],
          );
        },
      ),
    );
  }
}
