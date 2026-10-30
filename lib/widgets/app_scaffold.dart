import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/focus/navi_focus.dart';
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
import '../providers/search_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/library/albums_page.dart';
import '../screens/library/playlists_page.dart';
import '../screens/library/songs_page.dart';
import '../screens/now_playing_screen.dart';
import '../screens/playlist_details_screen.dart';
import '../screens/settings_screen.dart';
import '../services/window_manager_service.dart';
import 'art/navi_icons.dart';
import 'cover_art.dart';
import '../screens/playlist_editor.dart';
import 'ui/dock_ground.dart';
import 'ui/one_shot_icon.dart';
import '../features/social/ui/jam/jam_pill.dart';
import '../providers/session_sync_provider.dart';
import '../player/playing_on.dart';
import 'shell/app_tab.dart';
import 'shell/breadcrumb_bar.dart';
import 'shell/nav_stack.dart';
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

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> with WindowLifecycleMixin {
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
    if (tab == _tab) {
      // Re-selecting the current tab returns to its root (iOS behaviour).
      tabNavigators[tab]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
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

  late final ShellCommands _commands = ShellCommands(
    focusSearch: () => _select(AppTab.search),
    openSettings: () => navigateInApp(context, const SettingsScreen()),
    selectTab: (i) => _select(AppTab.values[i]),
    goBack: _back,
  );

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    return NaviKeyboardShortcuts(
      commands: _commands,
      child: LayoutBuilder(
        builder: (context, c) {
          return switch (ShellKind.of(Size(c.maxWidth, c.maxHeight))) {
            ShellKind.tv => TvShell(tab: _tab, visited: _visited, onSelect: _select),
            ShellKind.sidebar => _DesktopShell(tab: _tab, visited: _visited, onSelect: _select, offline: offline),
            ShellKind.phone => _PhoneShell(tab: _tab, visited: _visited, onSelect: _select, offline: offline),
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

  const _PhoneShell({required this.tab, required this.visited, required this.onSelect, required this.offline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Stack(
        children: [
          // System back pops inside the active tab before leaving the app.
          AnimatedBuilder(
            animation: tabTrails[tab]!.routes,
            builder: (context, child) => NavigatorPopHandler(
              enabled: tabTrails[tab]!.canPop,
              onPopWithResult: (_) => popActiveTab(),
              child: child!,
            ),
            child: TabNavigators(tab: tab, visited: visited),
          ),
          // The dock: one solid band in the visible page's own colour, with
          // the mini player and tab bar floating on it. Nothing scrolls into
          // view between or beside the controls, and an artwork-coloured page
          // keeps its colour right to the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<Color?>(
              valueListenable: DockGround.value,
              builder: (context, ground, _) {
                final band = ground ?? t.bgBase;
                return AnimatedContainer(
                  duration: Motion.standard,
                  color: band,
                  padding: const EdgeInsets.only(top: Space.sm),
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
  const _TabBar({required this.tab, required this.onSelect, required this.ground});

  static final _main = AppTab.mainTabs;

  /// [ground] lifted toward white by [amount], fully opaque.
  static Color _lift(Color ground, double amount) => Color.lerp(ground, Colors.white, amount)!;

  BoxDecoration _surface({bool circle = false}) => BoxDecoration(
        color: _lift(ground, 0.09),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(Radii.capsule),
        border: Border.all(color: _lift(ground, 0.16), width: 0.5),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final fetchAvailable = ref.watch(onlineFetchAvailableProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final index = _main.indexOf(tab);
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, bottom > 0 ? bottom : Space.md),
      child: SizedBox(
        height: _height,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: _surface(),
                padding: const EdgeInsets.all(4),
                child: LayoutBuilder(builder: (context, c) {
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
                              color: _lift(ground, 0.18),
                              borderRadius: BorderRadius.circular(Radii.capsule),
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
                }),
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
                    decoration: _surface(circle: true),
                    alignment: Alignment.center,
                    child: NaviIcon(
                      NaviGlyph.search,
                      size: 26,
                      color: tab == AppTab.search ? t.accent : t.textPrimary,
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

class _TabButton extends StatefulWidget {
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  static const double _illustrationSize = 34;
  final _icon = GlobalKey<OneShotIconState>();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final tab = widget.tab;
    final selected = widget.selected;
    final color = selected ? t.accent : t.textPrimary;
    final illustration = tab.illustration;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Plays once per tap, then rests on its still frame.
          _icon.currentState?.play();
          widget.onTap();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (illustration != null)
              OneShotIcon(
                key: _icon,
                name: illustration,
                size: _illustrationSize,
                duration: tab.illustrationDuration,
              )
            else
              NaviIcon(tab.icon, filled: selected, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              tab.label,
              style: t.caption2.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
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
          Text('Offline. Playing your downloads.', style: t.caption1.copyWith(color: t.textPrimary)),
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
  const _DesktopShell({required this.tab, required this.visited, required this.onSelect, required this.offline});

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  _Panel? _panel = _Panel.about;

  void _togglePanel(_Panel p) => setState(() => _panel = _panel == p ? null : p);

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final size = WindowSize.ofContext(context);
    final hasSong = ref.watch(playerProvider.select((s) => s.currentSong != null));
    final remote = ref.watch(playerProvider.select((s) => s.syncMode == SyncMode.passive));
    // medium: icon-only sidebar, no side panel; expanded: both.
    final panel = size.hasSidePanel && hasSong ? _panel : null;
    return Scaffold(
      backgroundColor: t.bgBase,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                FocusTraversalGroup(
                  child: _Sidebar(tab: widget.tab, onSelect: widget.onSelect, collapsed: size == WindowSize.medium),
                ),
                Container(width: 0.5, color: t.separatorOpaque),
                Expanded(
                  child: FocusTraversalGroup(
                    child: Column(
                      children: [
                        if (widget.offline) const _OfflineBanner(),
                        const BreadcrumbBar(),
                        Expanded(
                          child: ClipRect(
                            // Android back on a tablet goes up a level first.
                            child: AnimatedBuilder(
                              animation: tabTrails[widget.tab]!.routes,
                              builder: (context, child) => NavigatorPopHandler(
                                enabled: tabTrails[widget.tab]!.canPop,
                                onPopWithResult: (_) => popActiveTab(),
                                child: child!,
                              ),
                              child: TabNavigators(tab: widget.tab, visited: widget.visited),
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
                  Container(width: 0.5, color: t.separatorOpaque),
                  FocusTraversalGroup(
                    child: _SidePanel(panel: panel, onChange: (p) => setState(() => _panel = p), onClose: () => setState(() => _panel = null)),
                  ),
                ],
              ],
            ),
          ),
          // Another of your devices is playing: this one is the remote, with or without a song of its own.
          if (remote)
            const Padding(padding: EdgeInsets.only(top: Space.sm), child: RemoteMiniPlayer())
          else if (hasSong)
            _PlayerBar(panel: panel, onTogglePanel: _togglePanel, compact: !size.hasSidePanel),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;

  /// Medium windows: icons only, 72 wide.
  final bool collapsed;
  const _Sidebar({required this.tab, required this.onSelect, this.collapsed = false});

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
    final collapsed = widget.collapsed;
    final playlists = collapsed ? const [] : ref.watch(playlistsProvider).asData?.value ?? const [];
    final service = ref.read(subsonicServiceProvider);

    return AnimatedContainer(
      duration: Motion.standard,
      width: collapsed ? 72 : 248,
      color: t.bgSurface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(collapsed ? Space.sm : Space.md, Space.lg, collapsed ? Space.sm : Space.md, Space.lg),
        children: [
          if (!collapsed) ...[
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
          ],
          const _DownloadsRow(),
          for (final dest in AppTab.browseTabs)
            _SidebarRow(
              icon: dest.icon,
              label: dest.label,
              iconOnly: collapsed,
              selected: widget.tab == dest,
              onTap: () => widget.onSelect(dest),
            ),
          if (collapsed)
            _SidebarRow(
              icon: AppTab.search.icon,
              label: 'Search (Ctrl+F)',
              iconOnly: true,
              selected: widget.tab == AppTab.search,
              onTap: () => widget.onSelect(AppTab.search),
            )
          else
            const _SidebarHeader('Library'),
          _SidebarRow(
            icon: NaviGlyph.library,
            label: 'Library',
            iconOnly: collapsed,
            selected: widget.tab == AppTab.library,
            onTap: () => widget.onSelect(AppTab.library),
          ),
          _SidebarRow(
            icon: NaviGlyph.playlist,
            label: 'Playlists',
            iconOnly: collapsed,
            onTap: () => navigateInApp(context, const PlaylistsPage()),
          ),
          _SidebarRow(
            icon: NaviGlyph.stack,
            label: 'Albums',
            iconOnly: collapsed,
            onTap: () => navigateInApp(context, const AlbumsPage()),
          ),
          _SidebarRow(
            icon: NaviGlyph.note,
            label: 'Songs',
            iconOnly: collapsed,
            onTap: () => navigateInApp(context, const SongsPage()),
          ),
          _SidebarRow(
            icon: NaviGlyph.downloadCircle,
            label: 'Downloaded',
            iconOnly: collapsed,
            onTap: () => navigateInApp(context, const SongsPage(downloadedOnly: true), title: 'Downloaded'),
          ),
          if (!collapsed)
            _SidebarHeader(
              'Playlists',
              action: IconButton(
                tooltip: 'New Playlist',
                visualDensity: VisualDensity.compact,
                icon: NaviIcon(NaviGlyph.plus, size: 18, color: t.textSecondary),
                onPressed: () => showPlaylistEditor(context),
              ),
            ),
          for (final p in playlists)
            _SidebarRow(
              art: CoverArt(
                url: (p.coverArt ?? '').isEmpty ? null : service.getCoverArtUrl(p.coverArt),
                size: 22,
                radius: Radii.thumb,
                placeholderIcon: NaviGlyph.playlist,
              ),
              label: p.name,
              onTap: () => navigateInApp(context, PlaylistDetailsScreen(playlist: p), title: p.name),
            ),
          const SizedBox(height: Space.lg),
          _SidebarRow(
            icon: NaviGlyph.gear,
            label: 'Settings (Ctrl+,)',
            iconOnly: collapsed,
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

/// "Downloads" in the sidebar while anything from Search online is (or was,
/// this session) downloading, with a thin progress ring.
class _DownloadsRow extends ConsumerWidget {
  const _DownloadsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    if (!ref.watch(onlineFetchAvailableProvider) || ref.watch(fetchJobsProvider.select((d) => d.isEmpty))) {
      return const SizedBox.shrink();
    }
    return _SidebarRow(
      art: SizedBox(
        width: 18,
        height: 18,
        child: FetchActivityRing(child: NaviIcon(NaviGlyph.download, size: 12, color: t.accent)),
      ),
      label: 'Downloads',
      onTap: () => showFetchDownloads(context),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  final NaviGlyph? icon;
  final Widget? art;
  final String label;
  final bool selected;
  final bool iconOnly;
  final VoidCallback onTap;

  const _SidebarRow({
    this.icon,
    this.art,
    required this.label,
    this.selected = false,
    this.iconOnly = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final row = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      decoration: BoxDecoration(
        color: selected ? t.bgOverlay : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: iconOnly ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          art ?? NaviIcon(icon!, size: 18, color: t.accent),
          if (!iconOnly) ...[
            const SizedBox(width: Space.sm + 2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.subheadline.copyWith(color: t.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      selected: selected,
      child: NaviFocusable(
        radius: 6,
        onTap: onTap,
        semanticLabel: label,
        // Hover tint is the row's; the selected row keeps its own fill.
        hoverTint: !selected,
        child: iconOnly ? Tooltip(message: label, child: row) : row,
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
                    icon: NaviIcon(NaviGlyph.close, size: 16, color: t.textSecondary),
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

  /// Medium windows: no side panel, so only volume and the full-screen button.
  final bool compact;
  const _PlayerBar({required this.panel, required this.onTogglePanel, this.compact = false});

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
            width: compact ? 220 : 300,
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _BarButton(icon: NaviGlyph.shuffle, tooltip: 'Shuffle', active: shuffle, onTap: n.toggleShuffle),
                        const SizedBox(width: Space.sm),
                        _BarButton(icon: NaviGlyph.previous, tooltip: 'Previous', size: 22, onTap: n.playPrev),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: playing ? NaviGlyph.pause : NaviGlyph.play,
                          tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                          size: 28,
                          prominent: true,
                          onTap: n.togglePlay,
                        ),
                        const SizedBox(width: Space.sm),
                        _BarButton(icon: NaviGlyph.next, tooltip: 'Next', size: 22, onTap: n.playNext),
                        const SizedBox(width: Space.sm),
                        _BarButton(
                          icon: repeat == LoopMode.one ? NaviGlyph.repeatOne : NaviGlyph.repeat,
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
            width: compact ? 150 : 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!compact) _BarButton(icon: NaviGlyph.lyrics, tooltip: 'Lyrics', active: panel == _Panel.lyrics, onTap: () => onTogglePanel(_Panel.lyrics)),
                if (!compact) _BarButton(icon: NaviGlyph.queue, tooltip: 'Queue', active: panel == _Panel.queue, onTap: () => onTogglePanel(_Panel.queue)),
                if (!compact) _BarButton(icon: NaviGlyph.info, tooltip: 'About this song', active: panel == _Panel.about, onTap: () => onTogglePanel(_Panel.about)),
                const SizedBox(width: Space.sm),
                SizedBox(
                  width: compact ? 70 : 110,
                  child: VolumeBar(player: n.player, color: t.textPrimary, trackColor: t.fill, iconColor: t.textSecondary),
                ),
                _BarButton(icon: NaviGlyph.expand, tooltip: 'Full-screen player', size: 16, onTap: () => openNowPlaying(context)),
              ],
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
