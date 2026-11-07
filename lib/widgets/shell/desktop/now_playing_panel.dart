import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../player/artwork.dart';
import '../../../player/lyrics_pane.dart';
import '../../../player/now_playing_style.dart';
import '../../../player/player_controls.dart';
import '../../../player/queue_pane.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../art/navi_icons.dart';
import '../../ui/dock_ground.dart';
import '../desktop/desktop_layout.dart';
import '../desktop/resize_handle.dart';

/// Which part of the Now Playing panel is showing.
enum PanelKind { about, lyrics, queue }

/// Now Playing side panel: About (artwork + credits), Lyrics, Queue.
class NowPlayingPanel extends ConsumerWidget {
  final PanelKind panel;
  final ValueChanged<PanelKind> onChange;
  final VoidCallback onClose;

  const NowPlayingPanel({
    super.key,
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
                      child: CupertinoSlidingSegmentedControl<PanelKind>(
                        groupValue: panel,
                        backgroundColor: t.fill,
                        thumbColor: t.bgOverlay,
                        onValueChanged: (p) => p == null ? null : onChange(p),
                        children: {
                          for (final (p, label) in const [
                            (PanelKind.about, 'About'),
                            (PanelKind.lyrics, 'Lyrics'),
                            (PanelKind.queue, 'Queue'),
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
                    PanelKind.lyrics => LyricsPane(
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
                    PanelKind.queue => QueuePane(
                      key: const ValueKey('queue'),
                      style: style,
                      showCurrent: true,
                    ),
                    PanelKind.about => _AboutSong(
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


/// The Now Playing panel opened over [child] (a window too narrow to dock it
/// beside the content): a dim backdrop, the panel on the right edge with a drag
/// handle on its left, closed by Esc, a click on the backdrop or the panel's
/// close button. [panel] null means closed. Its width is [DesktopLayout.panelWidth],
/// shared with the docked panel, and remembered.
class PanelOverlay extends StatefulWidget {
  final Widget child;
  final PanelKind? panel;
  final ValueChanged<PanelKind> onChange;
  final VoidCallback onClose;
  const PanelOverlay({super.key, required this.child, required this.panel, required this.onChange, required this.onClose});

  @override
  State<PanelOverlay> createState() => _PanelOverlayState();
}

class _PanelOverlayState extends State<PanelOverlay> {
  /// What had focus when the panel opened (the bar's Lyrics or Queue button),
  /// so closing the panel puts the keyboard back where it was.
  FocusNode? _opener;

  /// The panel's own focus, taken when it opens, so Esc reaches it even though
  /// the control that opened it still held focus.
  final _panelFocus = FocusNode(debugLabel: 'now-playing-overlay');

  @override
  void initState() {
    super.initState();
    if (widget.panel != null) _opener = FocusManager.instance.primaryFocus;
  }

  @override
  void dispose() {
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PanelOverlay old) {
    super.didUpdateWidget(old);
    if (old.panel == null && widget.panel != null) {
      _opener = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _panelFocus.context != null) _panelFocus.requestFocus();
      });
    } else if (old.panel != null && widget.panel == null) {
      final back = _opener;
      _opener = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (back != null && back.context != null && back.canRequestFocus) back.requestFocus();
      });
    }
  }

  PanelKind? get panel => widget.panel;
  Widget get child => widget.child;
  ValueChanged<PanelKind> get onChange => widget.onChange;
  VoidCallback get onClose => widget.onClose;

  @override
  Widget build(BuildContext context) {
    final open = panel;
    return Stack(
      children: [
        child,
        if (open != null) ...[
          Positioned.fill(
            child: GestureDetector(
              key: const Key('panel-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              // No dimming (opaque chrome, no scrims): the backdrop only catches the click that closes the panel.
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
              child: Focus(
                focusNode: _panelFocus,
                autofocus: true,
                child: DecoratedBox(
                  // The drag handle's hairline is the edge and the panel's own tinted ground is the
                  // lift: no shadow, no scrim.
                  decoration: const BoxDecoration(),
                  child: Row(
                    children: [
                      ResizeHandle(
                        label: 'Resize the Now Playing panel',
                        growsRight: false,
                        onDrag: (d) => DesktopLayout.dragPanel(DesktopLayout.panelWidth.value + d),
                        onEnd: DesktopLayout.savePanel,
                        onReset: DesktopLayout.resetPanel,
                      ),
                      FocusTraversalGroup(child: NowPlayingPanel(panel: open, onChange: onChange, onClose: onClose)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
