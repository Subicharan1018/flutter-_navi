import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/keyboard_shortcuts.dart';
import '../core/layout/window_size.dart';
import '../core/theme.dart';
import '../features/online_fetch/logic/online_fetch_providers.dart';
import '../features/online_fetch/ui/fetch_activity.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
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
import 'shell/desktop/focus_regions.dart';
import 'shell/desktop/now_playing_panel.dart';
import 'shell/desktop/player_bar.dart';
import 'shell/shortcuts_help.dart';
import 'shell/desktop/desktop_layout.dart';
import 'shell/desktop/library_rail.dart';
import 'shell/desktop/resize_handle.dart';
import 'shell/desktop/top_bar.dart';
import 'shell/desktop/window_ground.dart';
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
    showShortcuts: () => showShortcutsHelp(context),
  );

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(isOfflineProvider);
    return NaviKeyboardShortcuts(
      commands: _commands,
      child: LayoutBuilder(
        builder: (context, c) {
          var kind = ShellKind.of(Size(c.maxWidth, c.maxHeight));

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
  PanelKind? _panel = PanelKind.about;

  /// The panel opened over the content when the window is too narrow to dock it.
  PanelKind? _overlay;

  void _toggleOverlay(PanelKind p) => setState(() => _overlay = _overlay == p ? null : p);

  void _togglePanel(PanelKind p) =>
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
    final overlay = !size.hasSidePanel && hasSong ? _overlay : null;
    // ONE tint for the whole window: the playing song's art, else (nothing
    // playing) the page's own cover. Everything below is transparent over it.
    return DesktopWindowGround(
            child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            DesktopTopBar(
              dragsWindow: NaviTitleBar.enabled,
              trailing: NaviTitleBar.enabled ? const NaviCaptionButtons(height: DesktopTopBar.height) : null,
            ),
            Expanded(
              child: Row(
                children: [
                  FocusRegion(
                    order: 1,
                    name: 'Library',
                    child: LibraryRail(
                      tab: widget.tab,
                      onSelect: widget.onSelect,
                      forceCollapsed: size == WindowSize.medium || size == WindowSize.compact,
                    ),
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
                    // A window too narrow to dock the Now Playing panel opens it over the content.
                    child: PanelOverlay(
                      panel: overlay,
                      onChange: (p) => setState(() => _overlay = p),
                      onClose: () => setState(() => _overlay = null),
                      child: FocusRegion(
                        order: 2,
                        name: 'Page',
                        child: FocusTraversalGroup(
                        child: Column(
                          children: [
                            if (widget.offline) const _OfflineBanner(),
                            Expanded(
                              // Full width: no centred column, no black margins.
                              child: ClipRect(
                                child: TabNavigators(
                                  tab: widget.tab,
                                  visited: widget.visited,
                                ),
                              ),
                            ),
                            const Center(child: JamLivePill()),
                            const FetchFinishedBanner(),
                          ],
                        ),
                        ),
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
                    FocusRegion(
                      order: 3,
                      name: 'Now Playing',
                      child: FocusTraversalGroup(
                        child: NowPlayingPanel(
                          panel: panel,
                          onChange: (p) => setState(() => _panel = p),
                          onClose: () => setState(() => _panel = null),
                        ),
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
              FocusRegion(
                order: 4,
                name: 'Player',
                child: DesktopPlayerBar(
                  panel: panel ?? overlay,
                  onTogglePanel: size.hasSidePanel ? _togglePanel : _toggleOverlay,
                  compact: size == WindowSize.compact,
                ),
              ),
          ],
        ),
            ),
    );
  }
}

