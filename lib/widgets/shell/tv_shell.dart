import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../player/artwork.dart';
import '../../player/player_controls.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../screens/now_playing_screen.dart';
import '../../screens/settings_screen.dart';
import '../../utils/platform_utils.dart';
import '../art/navi_icons.dart';
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

/// Overscan margin and larger type for a TV, applied once for the whole app
/// (so Now Playing, sheets and dialogs scale with it).
class TvFrame extends StatelessWidget {
  final Widget child;
  const TvFrame({super.key, required this.child});

  /// Android TV's recommended overscan-safe margins.
  static const EdgeInsets overscan = EdgeInsets.symmetric(horizontal: 48, vertical: 27);
  static const double textScale = 1.25;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isTv) return child;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: const TextScaler.linear(textScale),
        padding: mq.padding + overscan,
        viewPadding: mq.viewPadding + overscan,
      ),
      child: Padding(padding: overscan, child: child),
    );
  }
}

class TvShell extends ConsumerStatefulWidget {
  final AppTab tab;
  final Set<AppTab> visited;
  final ValueChanged<AppTab> onSelect;
  const TvShell({super.key, required this.tab, required this.visited, required this.onSelect});

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  final FocusScopeNode _rail = FocusScopeNode(debugLabel: 'tv-rail');

  @override
  void initState() {
    super.initState();
    _rail.addListener(_railFocusChanged);
  }

  @override
  void dispose() {
    _rail.removeListener(_railFocusChanged);
    _rail.dispose();
    super.dispose();
  }

  void _railFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Back: up one level, else to the rail, else leave the app.
  void _onBack(bool didPop, Object? _) {
    if (didPop) return;
    if (!popActiveTab()) _rail.requestFocus();
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
          child: Scaffold(
            backgroundColor: t.bgBase,
            body: Row(
              children: [
                FocusTraversalGroup(
                  child: FocusScope(
                    node: _rail,
                    child: TvRail(tab: widget.tab, onSelect: widget.onSelect),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: FocusTraversalGroup(
                          child: TabNavigators(tab: widget.tab, visited: widget.visited),
                        ),
                      ),
                      FocusTraversalGroup(child: const TvPlayerBar()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The destinations as a vertical rail: glyph and label, large targets.
class TvRail extends StatelessWidget {
  final AppTab tab;
  final ValueChanged<AppTab> onSelect;
  const TvRail({super.key, required this.tab, required this.onSelect});

  static const double width = 232;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: width,
      color: t.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
            child: Text('NaviVibe', style: t.title2),
          ),
          for (final dest in AppTab.values)
            _RailItem(
              glyph: dest.icon,
              label: dest.label,
              selected: dest == tab,
              autofocus: dest == tab,
              onTap: () => onSelect(dest),
            ),
          const Spacer(),
          _RailItem(
            glyph: NaviGlyph.gear,
            label: 'Settings',
            selected: false,
            onTap: () => navigateInApp(context, const SettingsScreen()),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;
  const _RailItem({
    required this.glyph,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
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
          radius: Radii.control,
          lift: false,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              decoration: BoxDecoration(
                color: selected ? t.bgOverlay : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Row(
                children: [
                  NaviIcon(glyph, size: 26, filled: selected, color: selected ? t.accent : t.textPrimary),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.headline.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
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
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      decoration: BoxDecoration(
        color: t.bgSurface,
        border: Border(top: BorderSide(color: t.separatorOpaque, width: 0.5)),
      ),
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
                    child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: 64, height: 64, cacheWidth: 192),
                  ),
                  const SizedBox(width: Space.lg),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headline),
                        const SizedBox(height: 2),
                        Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _TvTransport(glyph: NaviGlyph.previous, label: 'Previous', onTap: n.playPrev),
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
              child: _TvProgress(player: n.player, songId: song.id, total: song.duration * 1000),
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
  const _TvTransport({required this.glyph, required this.label, required this.onTap, this.big = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: big ? 72 : 60,
        height: 64,
        child: Center(child: NaviIcon(glyph, size: big ? 36 : 28, color: t.textPrimary)),
      ),
    );
  }
}

class _TvProgress extends StatelessWidget {
  final AudioPlayer player;
  final String songId;
  final int total;
  const _TvProgress({required this.player, required this.songId, required this.total});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return RepaintBoundary(
      child: PlaybackPosition(
        player: player,
        songId: songId,
        builder: (context, pos) => ClipRRect(
          borderRadius: BorderRadius.circular(Radii.capsule),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: total > 0 ? (pos.inMilliseconds / total).clamp(0.0, 1.0) : 0,
            backgroundColor: t.fill,
            valueColor: AlwaysStoppedAnimation(t.textPrimary),
          ),
        ),
      ),
    );
  }
}
