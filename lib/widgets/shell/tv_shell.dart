import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../models/song.dart';
import '../../player/artwork.dart';
import '../../player/player_controls.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../screens/now_playing_screen.dart';
import '../../screens/settings_screen.dart';
import '../../features/social/ui/jam/jam_pill.dart';
import '../art/navi_icons.dart';
import '../ui/dock_ground.dart';
import 'app_tab.dart';
import 'nav_stack.dart';
import 'tab_navigators.dart';

// =============================================================================
// tv_shell.dart — the 10-foot shell for Android TV.
//
//   ┌──────┬───────────────────────────────┐
//   │ rail │ the tab's content (shelves)   │
//   │      │                               │
//   │      ├───────────────────────────────┤
//   │      │ player bar                    │
//   └──────┴───────────────────────────────┘
//
// Focus order is rail → content → player bar. Right from the rail enters the
// content, Left from the content's left edge returns to the rail, and Back on
// a tab's root returns to the rail before it leaves the app.
// =============================================================================

class TvShell extends ConsumerStatefulWidget {
  final AppTab tab;
  final Set<AppTab> visited;
  final ValueChanged<AppTab> onSelect;
  const TvShell({
    super.key,
    required this.tab,
    required this.visited,
    required this.onSelect,
  });

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  /// Marks the rail's subtree (not a FocusScope: a scope would trap the D-pad inside it).
  final FocusNode _rail = FocusNode(
    debugLabel: 'tv-rail',
    skipTraversal: true,
    canRequestFocus: false,
  );

  /// The rail item for the current tab: where Back returns to.
  final FocusNode _selectedItem = FocusNode(debugLabel: 'tv-rail-selected');

  @override
  void initState() {
    super.initState();
    _rail.addListener(_railFocusChanged);
  }

  @override
  void dispose() {
    _rail.removeListener(_railFocusChanged);
    _rail.dispose();
    _selectedItem.dispose();
    super.dispose();
  }

  void _railFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Back: up one level, else to the rail, else leave the app.
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (!popActiveTab()) _selectedItem.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AnimatedBuilder(
      animation: tabTrails[widget.tab]!.routes,
      builder: (context, _) {
        final atRoot = !tabTrails[widget.tab]!.canPop;
        return PopScope(
          canPop: atRoot && _rail.hasFocus,
          onPopInvokedWithResult: _onBack,
          child: ValueListenableBuilder<Color?>(
            valueListenable: DockGround.value,
            builder: (context, ground, _) => Scaffold(
              backgroundColor: ground ?? t.bgBase,
              body: Row(
                children: [
                  FocusTraversalGroup(
                    child: Focus(
                      focusNode: _rail,
                      child: TvRail(
                        tab: widget.tab,
                        onSelect: widget.onSelect,
                        selectedNode: _selectedItem,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: MediaQuery.paddingOf(context).right,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: FocusTraversalGroup(
                              child: TabNavigators(
                                tab: widget.tab,
                                visited: widget.visited,
                              ),
                            ),
                          ),
                          const Center(child: JamLivePill()),
                          ValueListenableBuilder<Color?>(
                            valueListenable: DockGround.value,
                            builder: (_, _, _) =>
                                FocusTraversalGroup(child: TvPlayerBar()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class TvRail extends StatelessWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  final FocusNode? selectedNode;
  const TvRail({
    super.key,
    required this.tab,
    required this.onSelect,
    this.selectedNode,
  });

  /// Canvas units (see TvFrame): 200 of 1280.
  static const double width = 200;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final inset = MediaQuery.paddingOf(context);
    // A list, not a column: seven items always fit the 720-high canvas, but a
    // smaller font setting or a taller label must scroll rather than overflow.
    return ValueListenableBuilder<Color?>(
      valueListenable: DockGround.value,
      builder: (context, ground, _) => Container(
        width: width,
        color: tvTint(ground ?? t.bgBase),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.md,
            inset.top + Space.md,
            Space.md,
            inset.bottom + Space.md,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                0,
                Space.md,
                Space.lg,
              ),
              child: Text('NaviVibe', style: t.title3),
            ),
            for (final dest in AppTab.values)
              _RailItem(
                glyph: dest.icon,
                label: dest.label,
                selected: dest == tab,
                autofocus: dest == tab,
                focusNode: dest == tab ? selectedNode : null,
                onTap: () => onSelect(dest),
              ),
            const SizedBox(height: Space.lg),
            _RailItem(
              glyph: NaviGlyph.gear,
              label: 'Settings',
              selected: false,
              onTap: () => navigateInApp(context, const SettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final bool selected;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  const _RailItem({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.xs),
        child: NaviFocusRing(
          autofocus: autofocus,
          focusNode: focusNode,
          radius: Radii.control,
          lift: false,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              decoration: BoxDecoration(
                color: selected ? t.bgOverlay : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Row(
                children: [
                  NaviIcon(
                    glyph,
                    size: 22,
                    filled: selected,
                    color: selected ? t.accent : t.textPrimary,
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.headline.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What's playing, with transport, along the bottom. Select on the artwork or
/// title opens Now Playing; the three transport buttons are focus stops.
class TvPlayerBar extends ConsumerWidget {
  const TvPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final playing = ref.watch(playerProvider.select((s) => s.isPlaying));
    final n = ref.read(playerProvider.notifier);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      color: tvTint(DockGround.value.value ?? t.bgBase),
      child: Row(
        children: [
          Expanded(
            child: CupertinoClickable(
              onTap: () => openNowPlaying(context),
              semanticLabel: 'Open Now Playing',
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.cover),
                    child: CoverImage(
                      url: url,
                      cacheKey: coverCacheKey(song),
                      width: 52,
                      height: 52,
                      cacheWidth: 156,
                    ),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.headline,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.subheadline,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _TvTransport(
            glyph: NaviGlyph.previous,
            label: 'Previous',
            onTap: n.playPrev,
          ),
          _TvTransport(
            glyph: playing ? NaviGlyph.pause : NaviGlyph.play,
            label: playing ? 'Pause' : 'Play',
            big: true,
            onTap: n.togglePlay,
          ),
          _TvTransport(glyph: NaviGlyph.next, label: 'Next', onTap: n.playNext),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: Space.xl),
              child: _TvProgress(player: n.player, song: song),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvTransport extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool big;
  const _TvTransport({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: big ? 72 : 60,
        height: 64,
        child: Center(
          child: NaviIcon(glyph, size: big ? 36 : 28, color: t.textPrimary),
        ),
      ),
    );
  }
}

class _TvProgress extends StatelessWidget {
  final AudioPlayer player;
  final Song song;
  const _TvProgress({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return RepaintBoundary(
      child: PlaybackProgressBuilder(
        player: player,
        song: song,
        builder: (context, progress) => ClipRRect(
          borderRadius: BorderRadius.circular(Radii.capsule),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress.fraction,
            backgroundColor: t.fill,
            valueColor: AlwaysStoppedAnimation(t.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The rail and player bar are a faint lift of whatever colour the page is
/// (never a different-coloured box): one continuous surface, edge to edge.
Color tvTint(Color ground) => Color.lerp(ground, Colors.white, 0.045)!;
