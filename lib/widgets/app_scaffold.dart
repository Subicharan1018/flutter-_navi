import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/keyboard_shortcuts.dart';
import '../core/layout/window_size.dart';
import '../core/theme.dart';
import '../features/online_fetch/logic/online_fetch_providers.dart';
import '../features/online_fetch/ui/fetch_activity.dart';
import '../models/song.dart';
import '../player/artwork.dart';
import '../player/lyrics_pane.dart';
import '../player/now_playing_style.dart';
import '../player/player_controls.dart';
import '../player/queue_pane.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/now_playing_screen.dart';
import '../screens/settings_screen.dart';
import '../services/window_manager_service.dart';
import '../utils/platform_utils.dart';
import 'art/navi_icons.dart';
import 'ui/dock_ground.dart';
import 'shell/dock_glass.dart';
import '../features/social/ui/jam/jam_pill.dart';
import '../providers/session_sync_provider.dart';
import '../player/playing_on.dart';
import 'shell/app_tab.dart';
import 'shell/nav_stack.dart';
import 'shell/system_back.dart';
import 'shell/title_bar.dart';
import 'shell/desktop/desktop_layout.dart';
import 'shell/desktop/library_rail.dart';
import 'shell/desktop/resize_handle.dart';
import 'shell/desktop/top_bar.dart';
import 'shell/tab_navigators.dart';
import 'shell/tv_shell.dart';
import '../providers/id_migration_provider.dart';

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

export 'shell/app_tab.dart' show AppTab;
export 'shell/nav_stack.dart' show navigateInApp, selectAppTab;

/// Pages stop growing here on a wide window, so rows and text stay readable;
/// the page colour still runs edge to edge behind them.
const double kContentMaxWidth = 1180;

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WindowLifecycleMixin {
  AppTab _tab = AppTab.home;

  /// Tabs built so far. A tab is built the first time it's opened and kept
  /// alive after that, so Stats and Shuffle don't fetch at launch.
  final Set<AppTab> _visited = {AppTab.home};

  void _onTabRequest() {
    final tab = tabRequest.value;
    if (tab == null) return;
    tabRequest.value = null;
    if (mounted) _select(tab);
  }

  @override
  void dispose() {
    tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    tabRequest.addListener(_onTabRequest);
    // Open the live link at launch so this device is in the "Playing on" list
    // before anything plays here.
    ref.read(sessionSyncServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // After a server upgrade that renamed song ids, move local history and
      // downloads to the new ids first (a no-op otherwise; gives up after 8 s).
      await ref.read(idMigrationProvider).runIfNeeded();
      if (!mounted) return;
      // Mirror the library now rather than when the Library tab first opens:
      // Home, Stats, Replay and Shuffle resolve titles from it.
      ref.read(allSongsProvider.future).ignore();
    });
  }

  void _select(AppTab tab) {
    if (tab == _tab) return reselectTab(tab);
    HapticFeedback.selectionClick();
    // Each tab keeps its own stack, so leaving one never loses where you were.
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    activeTab.value = tab;
  }

  /// Esc / Alt+← / the mouse's back button: close what's on top (the player,
  /// a dialog), else go up one level in the current tab.
  bool _back() {
    final root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      root.pop();
      return true;
    }
    return popActiveTab();
  }

  Widget _scoped(Widget shell) => SystemBackScope(
    tab: _tab,
    onGoHome: () => _select(AppTab.home),
    child: shell,
  );

  /// Ctrl+F and '/': Search, with the caret already in its field.
  void _focusSearch() {
    _select(AppTab.search);
    // Desktop: the field is in the top bar (Ctrl+K); elsewhere it is Search's own.
    if (PlatformUtils.isDesktop) {
      desktopSearchFocus.requestFocus();
    } else {
      searchFieldRequest.value = true;
    }
  }

  late final ShellCommands _commands = ShellCommands(
    openSearch: () => _select(AppTab.search),
    focusSearch: _focusSearch,
    openSettings: () => navigateInApp(context, const SettingsScreen()),
    selectTab: (i) => _select(AppTab.values[i]),
    goBack: _back,
    goForward: () => goForward(context),
  );

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    return NaviKeyboardShortcuts(
      commands: _commands,
      child: LayoutBuilder(
        builder: (context, c) {
          var kind = ShellKind.of(Size(c.maxWidth, c.maxHeight));
          // A narrow Windows window keeps the desktop shell (icon rail, top bar); it never becomes phone tabs.
          if (PlatformUtils.isDesktop && kind == ShellKind.phone) kind = ShellKind.sidebar;
          return switch (kind) {
            ShellKind.tv => TvShell(
              tab: _tab,
              visited: _visited,
              onSelect: _select,
            ),
            ShellKind.sidebar => _scoped(
              _DesktopShell(
                tab: _tab,
                visited: _visited,
                onSelect: _select,
                offline: offline,
              ),
            ),
            ShellKind.phone => _scoped(
              _PhoneShell(
                tab: _tab,
                visited: _visited,
                onSelect: _select,
                offline: offline,
              ),
            ),
          };
        },
      ),
    );
  }
}

// ── Phone ───────────────────────────────────────────────────────────────────

class _PhoneShell extends ConsumerWidget {
  final AppTab tab;
  final Set<AppTab> visited;
  final ValueChanged<AppTab> onSelect;
  final bool offline;

  const _PhoneShell({
    required this.tab,
    required this.visited,
    required this.onSelect,
    required this.offline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Stack(
        children: [
          // Pages end above the dock: it is part of their bottom padding.
          // (System back is handled by the shell's back dispatcher.)
          DockInsetScope(
            child: TabNavigators(tab: tab, visited: visited),
          ),
          // The dock: one sheet of frosted glass in the visible page's own
          // colour (a solid band when glass is off, see `GlassDock`), with
          // the Jam pill, mini player and tab bar on it. One blur layer for
          // all three; content scrolls visibly beneath.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<Color?>(
              valueListenable: DockGround.value,
              builder: (context, ground, _) {
                final band = ground ?? t.bgBase;
                return GlassDock(
                  ground: band,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (offline) const _OfflineBanner(),
                      const FetchFinishedBanner(),
                      const JamLivePill(),
                      const AdaptiveMiniPlayer(),
                      _TabBar(tab: tab, onSelect: onSelect, ground: band),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS 26 tab bar: a floating capsule holding the main tabs, with Search
/// split off into its own circle at the trailing end. Solid surfaces lifted
/// from the dock band's colour with a hairline edge (no blur, no shadow);
/// the selected tab sits on a lighter pill that slides between positions.
class _TabBar extends ConsumerWidget {
  static const double _height = 62;

  final AppTab tab;
  final ValueChanged<AppTab> onSelect;

  /// The dock band this bar floats on; its surfaces are lighter solid steps
  /// of it, so the bar belongs to whatever page is showing.
  final Color ground;
  const _TabBar({
    required this.tab,
    required this.onSelect,
    required this.ground,
  });

  static final _main = AppTab.mainTabs;

  /// [ground] lifted toward white by [amount], fully opaque.
  static Color _lift(Color ground, double amount) =>
      Color.lerp(ground, Colors.white, amount)!;

  /// Lighter than the dock it floats on: an opaque step of the band, or a
  /// veil of white over the glass.
  BoxDecoration _surface(BuildContext context, {bool circle = false}) {
    final glass = DockGlass.of(context);
    return BoxDecoration(
      color: glass ? const Color(0x14FFFFFF) : _lift(ground, 0.09),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(Radii.capsule),
      border: Border.all(
        color: glass ? const Color(0x2BFFFFFF) : _lift(ground, 0.16),
        width: 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final fetchAvailable = ref.watch(onlineFetchAvailableProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final index = _main.indexOf(tab);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        bottom > 0 ? bottom : Space.md,
      ),
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: _surface(context),
                padding: const EdgeInsets.all(4),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth / _main.length;
                    return Stack(
                      children: [
                        if (index >= 0)
                          AnimatedPositioned(
                            duration: Motion.standard,
                            curve: Curves.easeOutBack,
                            left: index * w,
                            top: 0,
                            bottom: 0,
                            width: w,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: DockGlass.of(context)
                                    ? const Color(0x24FFFFFF)
                                    : _lift(ground, 0.18),
                                borderRadius: BorderRadius.circular(
                                  Radii.capsule,
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            for (final destination in _main)
                              Expanded(
                                child: _TabButton(
                                  tab: destination,
                                  selected: destination == tab,
                                  onTap: () => onSelect(destination),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: Space.sm + 2),
            Semantics(
              button: true,
              selected: tab == AppTab.search,
              label: 'Search',
              onLongPressHint: fetchAvailable ? 'Show downloads' : null,
              child: GestureDetector(
                onTap: () => onSelect(AppTab.search),
                // Search online downloads: a thin ring while they run; long
                // press lists them.
                onLongPress: fetchAvailable
                    ? () {
                        HapticFeedback.mediumImpact();
                        showFetchDownloads(context);
                      }
                    : null,
                child: FetchActivityRing(
                  child: Container(
                    width: _height,
                    height: _height,
                    decoration: _surface(context, circle: true),
                    alignment: Alignment.center,
                    child: NaviIcon(
                      NaviGlyph.search,
                      size: 26,
                      color: tab == AppTab.search ? t.accent : t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One tab: our monochrome glyph over its label. White and filled when
/// selected, muted otherwise.
class _TabButton extends StatelessWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

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
            NaviIcon(tab.icon, filled: selected, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: t.caption2.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
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
    // Sits on the dock band above the mini player, clear of page titles.
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NaviIcon(NaviGlyph.wifiOff, size: 13, color: t.warning),
          const SizedBox(width: Space.xs + 2),
          Text(
            'Offline. Playing your downloads.',
            style: t.caption1.copyWith(color: t.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ── Desktop ─────────────────────────────────────────────────────────────────

/// Which part of the Now Playing side panel is showing.
enum _Panel { about, lyrics, queue }

class _DesktopShell extends ConsumerStatefulWidget {
  final AppTab tab;
  final Set<AppTab> visited;
  final ValueChanged<AppTab> onSelect;
  final bool offline;
  const _DesktopShell({
    required this.tab,
    required this.visited,
    required this.onSelect,
    required this.offline,
  });

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  _Panel? _panel = _Panel.about;

  void _togglePanel(_Panel p) =>
      setState(() => _panel = _panel == p ? null : p);

  @override
  void initState() {
    super.initState();
    // The window's own title bar steps aside: the top bar below is the title bar.
    WidgetsBinding.instance.addPostFrameCallback((_) => desktopShellActive.value = true);
  }

  @override
  void dispose() {
    desktopShellActive.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final size = WindowSize.ofContext(context);
    final hasSong = ref.watch(
      playerProvider.select((s) => s.currentSong != null),
    );
    final remote = ref.watch(
      playerProvider.select((s) => s.syncMode == SyncMode.passive),
    );
    // Narrow: icon-only rail, no side panel; wide enough: both.
    final panel = size.hasSidePanel && hasSong ? _panel : null;
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, ground, _) => Scaffold(
        backgroundColor: ground ?? t.bgBase,
        body: Column(
          children: [
            DesktopTopBar(
              dragsWindow: NaviTitleBar.enabled,
              trailing: NaviTitleBar.enabled ? const NaviCaptionButtons(height: DesktopTopBar.height) : null,
            ),
            Expanded(
              child: Row(
                children: [
                  LibraryRail(
                    tab: widget.tab,
                    onSelect: widget.onSelect,
                    forceCollapsed: size == WindowSize.medium || size == WindowSize.compact,
                  ),
                  // Drag the seam to resize the rail; double-click puts it back.
                  ValueListenableBuilder<bool>(
                    valueListenable: DesktopLayout.railCollapsed,
                    builder: (context, collapsed, _) => collapsed || size != WindowSize.expanded
                        ? GroundDivider(color: t.separatorOpaque)
                        : ResizeHandle(
                            label: 'Resize the library',
                            growsRight: true,
                            onDrag: (d) => DesktopLayout.dragRail(DesktopLayout.railWidth.value + d),
                            onEnd: DesktopLayout.saveRail,
                            onReset: DesktopLayout.resetRail,
                          ),
                  ),
                  Expanded(
                    child: FocusTraversalGroup(
                      child: Column(
                        children: [
                          if (widget.offline) const _OfflineBanner(),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: kContentMaxWidth,
                                ),
                                child: ClipRect(
                                  child: TabNavigators(
                                    tab: widget.tab,
                                    visited: widget.visited,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Center(child: JamLivePill()),
                          const FetchFinishedBanner(),
                        ],
                      ),
                    ),
                  ),
                  if (panel != null) ...[
                    ResizeHandle(
                      label: 'Resize the Now Playing panel',
                      growsRight: false,
                      onDrag: (d) => DesktopLayout.dragPanel(DesktopLayout.panelWidth.value + d),
                      onEnd: DesktopLayout.savePanel,
                      onReset: DesktopLayout.resetPanel,
                    ),
                    FocusTraversalGroup(
                      child: _SidePanel(
                        panel: panel,
                        onChange: (p) => setState(() => _panel = p),
                        onClose: () => setState(() => _panel = null),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Another of your devices is playing: this one is the remote, with or without a song of its own.
            if (remote)
              const Padding(
                padding: EdgeInsets.only(top: Space.sm),
                child: RemoteMiniPlayer(),
              )
            else if (hasSong)
              _PlayerBar(
                panel: panel,
                onTogglePanel: _togglePanel,
                compact: !size.hasSidePanel,
              ),
          ],
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

  const _SidePanel({
    required this.panel,
    required this.onChange,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final style = NowPlayingStyle.fromTokens(t);
    return GroundSurface(
      darken: 0.4,
      child: ValueListenableBuilder<double>(
        valueListenable: DesktopLayout.panelWidth,
        builder: (context, w, child) => SizedBox(width: w, child: child),
        child: NowPlayingStyleScope(
          style: style,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.md,
                  Space.xs,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoSlidingSegmentedControl<_Panel>(
                        groupValue: panel,
                        backgroundColor: t.fill,
                        thumbColor: t.bgOverlay,
                        onValueChanged: (p) => p == null ? null : onChange(p),
                        children: {
                          for (final (p, label) in const [
                            (_Panel.about, 'About'),
                            (_Panel.lyrics, 'Lyrics'),
                            (_Panel.queue, 'Queue'),
                          ])
                            p: Text(
                              label,
                              style: t.footnote.copyWith(color: t.textPrimary),
                            ),
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: NaviIcon(
                        NaviGlyph.close,
                        size: 16,
                        color: t.textSecondary,
                      ),
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
                      padding: const EdgeInsets.fromLTRB(
                        Space.xl,
                        Space.md,
                        Space.xl,
                        0,
                      ),
                    ),
                    _Panel.queue => QueuePane(
                      key: const ValueKey('queue'),
                      style: style,
                      showCurrent: true,
                    ),
                    _Panel.about => _AboutSong(
                      key: const ValueKey('about'),
                      song: song,
                    ),
                  },
                ),
              ),
            ],
          ),
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
          Expanded(
            child: Text(v, style: t.footnote.copyWith(color: t.textPrimary)),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.xs,
        Space.lg,
        Space.xxl,
      ),
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.hero),
            child: CoverImage(
              url: url,
              cacheKey: coverCacheKey(song),
              cacheWidth: 640,
            ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: Space.sm,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(Radii.thumb),
              ),
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

  /// Medium windows: no side panel, so only volume and the full-screen button.
  final bool compact;
  const _PlayerBar({
    required this.panel,
    required this.onTogglePanel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final starred = ref.watch(
      playerProvider.select((s) => s.starredIds.contains(song.id)),
    );
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
          Expanded(
            flex: 3,
            child: Row(
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => openNowPlaying(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.cover),
                      child: CoverImage(
                        url: url,
                        cacheKey: coverCacheKey(song),
                        width: ArtSize.of(context).player,
                        height: ArtSize.of(context).player,
                        cacheWidth: (ArtSize.of(context).player * 3).round(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.subheadline.copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote,
                      ),
                    ],
                  ),
                ),
                _BarButton(
                  icon: NaviGlyph.star,
                  filled: starred,
                  tooltip: starred ? 'Remove from Favorites' : 'Favorite',
                  active: starred,
                  onTap: () => n.toggleStar(song.id),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BarButton(
                          icon: NaviGlyph.shuffle,
                          tooltip: 'Shuffle',
                          active: shuffle,
                          onTap: n.toggleShuffle,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: NaviGlyph.previous,
                          tooltip: 'Previous',
                          size: 22,
                          onTap: n.playPrev,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: playing ? NaviGlyph.pause : NaviGlyph.play,
                          tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                          size: 28,
                          prominent: true,
                          onTap: n.togglePlay,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: NaviGlyph.next,
                          tooltip: 'Next',
                          size: 22,
                          onTap: n.playNext,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: repeat == LoopMode.one
                              ? NaviGlyph.repeatOne
                              : NaviGlyph.repeat,
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
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, c) {
                // Narrow: keep Lyrics / Queue / full screen; the About and volume
                // controls give way instead of overflowing.
                final narrow = c.maxWidth < 300;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!compact)
                      _BarButton(
                        icon: NaviGlyph.lyrics,
                        tooltip: 'Lyrics',
                        active: panel == _Panel.lyrics,
                        onTap: () => onTogglePanel(_Panel.lyrics),
                      ),
                    if (!compact)
                      _BarButton(
                        icon: NaviGlyph.queue,
                        tooltip: 'Queue',
                        active: panel == _Panel.queue,
                        onTap: () => onTogglePanel(_Panel.queue),
                      ),
                    if (!compact && !narrow)
                      _BarButton(
                        icon: NaviGlyph.info,
                        tooltip: 'About this song',
                        active: panel == _Panel.about,
                        onTap: () => onTogglePanel(_Panel.about),
                      ),
                    if (c.maxWidth >= 220) ...[
                      const SizedBox(width: Space.sm),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 70 : 110,
                          ),
                          child: VolumeBar(
                            player: n.player,
                            color: t.textPrimary,
                            trackColor: t.fill,
                            iconColor: t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                    _BarButton(
                      icon: NaviGlyph.expand,
                      tooltip: 'Full-screen player',
                      size: 16,
                      onTap: () => openNowPlaying(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final NaviGlyph icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool filled;
  final bool prominent;
  final double size;

  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.filled = false,
    this.prominent = false,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final color = active
        ? t.accent
        : (prominent ? t.textPrimary : t.textSecondary);
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
          child: NaviIcon(icon, size: size, color: color, filled: filled),
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
    final label = t.caption1.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return RepaintBoundary(
      child: PlaybackProgressBuilder(
        player: player,
        song: widget.song,
        builder: (context, progress) {
          final total = progress.total.inMilliseconds;
          final f = _drag ?? progress.fraction;
          return Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  formatClock(Duration(milliseconds: (f * total).round())),
                  textAlign: TextAlign.right,
                  style: label,
                ),
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
                    progress.seekTo(
                      player,
                      Duration(milliseconds: (v * total).round()),
                    );
                    setState(() => _drag = null);
                  },
                ),
              ),
              const SizedBox(width: Space.sm + 2),
              SizedBox(
                width: 44,
                child: Text(formatClock(progress.total), style: label),
              ),
            ],
          );
        },
      ),
    );
  }
}
