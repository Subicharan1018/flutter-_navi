import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../lyrics/controllers/lyrics_controller.dart';
import '../lyrics/controllers/lyrics_translation_controller.dart';
import '../lyrics/models/lyric_line.dart';
import '../lyrics/models/lyric_translation.dart';
import '../providers/player_provider.dart';
import '../utils/platform_utils.dart';
import 'lyric_gap_dots.dart';
import 'lyric_word_sweep.dart';
import 'lyrics_motion.dart';
import 'lyrics_source_chip.dart';
import 'now_playing_style.dart';

/// Time-synced lyrics in the Apple manner: big, bold, left-aligned lines; the
/// sung line at full white, the rest receded. Tap a line to jump there.
///
/// Lines never animate their font size (that relayouts text every frame);
/// emphasis is opacity + a slight scale, which the compositor handles.
class LyricsPane extends ConsumerStatefulWidget {
  final NowPlayingStyle style;

  /// 30 on phones, larger on wide layouts.
  final double fontSize;
  final EdgeInsets padding;

  const LyricsPane({
    super.key,
    required this.style,
    this.fontSize = 30,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 0),
  });

  @override
  ConsumerState<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends ConsumerState<LyricsPane> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  Timer? _userHold;
  bool _following = true;

  /// Drives the scroll offset with a spring; ticks only while the view moves,
  /// and (as a ticker) stops by itself when the pane is hidden.
  late final AnimationController _spring = AnimationController.unbounded(vsync: this)..addListener(_onSpring);
  int? _lastFollowed;
  SyncedLyrics? _lyricsSeen;

  @override
  void dispose() {
    _spring.dispose();
    _scroll.dispose();
    _userHold?.cancel();
    super.dispose();
  }

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _onSpring() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final v = _spring.value.clamp(p.minScrollExtent, p.maxScrollExtent);
    if ((v - p.pixels).abs() > 0.01) _scroll.jumpTo(v);
  }

  /// Offset that puts line [index] a third of the way down, or null while the
  /// line is not laid out.
  double? _targetFor(int index) {
    final box = _keys[index]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scroll.hasClients) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return null;
    final p = _scroll.position;
    return LyricsMotion.scrollTarget(
      lineTop: p.pixels + box.localToGlobal(Offset.zero, ancestor: viewport).dy,
      lineHeight: box.size.height,
      viewport: p.viewportDimension,
      minExtent: p.minScrollExtent,
      maxExtent: p.maxScrollExtent,
    );
  }

  void _follow(int index, {bool instant = false}) {
    if (!_following || index < 0) return;
    final target = _targetFor(index);
    if (target == null) return;
    final previous = _lastFollowed;
    _lastFollowed = index;
    final pos = _scroll.position;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (instant || reduce || previous == null || !TickerMode.valuesOf(context).enabled) {
      _spring.stop();
      if ((target - pos.pixels).abs() > 0.5) _scroll.jumpTo(target);
      return;
    }
    // A new target mid-glide carries on from the current speed, so quick
    // successive lines never stop and restart the motion.
    final velocity = _spring.isAnimating ? _spring.velocity : 0.0;
    final seek = LyricsMotion.isSeek(previous, index);
    _spring.animateWith(
      SpringSimulation(
        seek ? LyricsMotion.seekSpring : LyricsMotion.scrollSpring,
        pos.pixels,
        target,
        velocity,
        snapToEnd: true,
      ),
    );
  }

  bool _onUserScroll(UserScrollNotification n) {
    if (n.direction != ScrollDirection.idle) {
      _spring.stop();
      _following = false;
      _userHold?.cancel();
      _userHold = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        _following = true;
        _follow(ref.read(lyricsControllerProvider).activeLineIndex);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(lyricsControllerProvider.select((s) => s.activeLineIndex), (prev, next) {
      if (next != prev) WidgetsBinding.instance.addPostFrameCallback((_) => _follow(next));
    });
    // Everything but the active line index: that changes every few seconds and
    // is read by the two lines that change look, not by this whole list.
    final state = ref.watch(
      lyricsControllerProvider.select(
        (s) => (s.status, s.lyrics, s.source, s.wordSynced, s.errorMessage, s.cooling),
      ),
    );
    final st = widget.style;

    // New lyrics: forget the old song's scroll and settle on the current line
    // without gliding, so a song resumed mid-way opens at the right place.
    if (!identical(state.$2, _lyricsSeen)) {
      _lyricsSeen = state.$2;
      _lastFollowed = null;
      _spring.stop();
      if (state.$2 != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow(ref.read(lyricsControllerProvider).activeLineIndex, instant: true);
        });
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: switch (state.$1) {
        LyricsStatus.loading => _Skeleton(key: const ValueKey('loading'), style: st, padding: widget.padding),
        LyricsStatus.synced => _withChip(_synced(state.$2!), st, state.$3, state.$4 ? 'WORD' : 'SYNC'),
        LyricsStatus.plain => _withChip(_plain(state.$2!, st), st, state.$3, 'TEXT'),
        LyricsStatus.empty => _Message(
            key: const ValueKey('empty'),
            style: st,
            title: 'No lyrics for this song',
            body: 'Lyrics appear here when your server, lrc.red, BetterLyrics, YouTube Music or LRCLIB has them. '
                'Choose the sources in Settings.',
            action: TextButton(
              key: const ValueKey('search-again'),
              // Disabled for a short while after a search that found nothing.
              onPressed: state.$6 ? null : () => ref.read(lyricsControllerProvider.notifier).searchAgain(),
              child: Text(
                state.$6 ? 'Searched just now' : 'Search again',
                style: naviText(15, FontWeight.w600, state.$6 ? st.textSecondary : st.textPrimary),
              ),
            ),
          ),
        LyricsStatus.error => _Message(
            key: const ValueKey('error'),
            style: st,
            title: 'Couldn’t load lyrics',
            body: state.$5 ?? 'Check your connection and try again.',
            action: TextButton(
              key: const ValueKey('lyrics-retry'),
              onPressed: () => ref.read(lyricsControllerProvider.notifier).retry(),
              child: Text('Try again', style: naviText(15, FontWeight.w600, st.textPrimary)),
            ),
          ),
      },
    );
  }

  /// The lyrics with a small "where from" chip under them (`lrc.red · WORD`),
  /// which is also the credit some sources' terms require.
  Widget _withChip(Widget lyrics, NowPlayingStyle st, String? source, String kind) {
    final label = lyricsSourceLabel(source);
    if (label == null) return lyrics;
    return Stack(
      key: lyrics.key,
      fit: StackFit.expand,
      children: [
        lyrics,
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(child: LyricsSourceChip(style: st, label: label, kind: kind)),
        ),
      ],
    );
  }

  Widget _synced(SyncedLyrics lyrics) {
    final lines = lyrics.lines;
    final st = widget.style;
    final firstAt = lines.isEmpty ? Duration.zero : lines.first.timestamp;
    final tr = ref.watch(lyricsTranslationProvider);

    return NotificationListener<UserScrollNotification>(
      key: const ValueKey('synced'),
      onNotification: _onUserScroll,
      // No edge-fade mask: a ShaderMask re-renders the whole list off-screen
      // every frame. Far lines are already dim, so the cut is soft anyway.
      child: SingleChildScrollView(
          controller: _scroll,
          physics: PlatformUtils.isDesktop ? const ClampingScrollPhysics() : const BouncingScrollPhysics(),
          padding: widget.padding.copyWith(bottom: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslateBar(style: st),
              if (isInstrumentalGap(Duration.zero, firstAt))
                // Keeps its height once the singing starts, so nothing jumps.
                Consumer(
                  builder: (context, ref, _) => LyricGapDots(
                    active: ref.watch(lyricsControllerProvider.select((s) => s.activeLineIndex < 0)),
                    startMs: 0,
                    endMs: firstAt.inMilliseconds,
                    positionMs: () => ref.read(playerProvider.notifier).player.position.inMilliseconds,
                    size: widget.fontSize,
                    color: st.textPrimary,
                  ),
                ),
              for (int i = 0; i < lines.length; i++) ...[
                _Line(
                  key: _keyFor(i),
                  index: i,
                  line: lines[i],
                  endsAt: i + 1 < lines.length ? lines[i + 1].timestamp : lines[i].timestamp + const Duration(seconds: 6),
                  extra: _extraFor(tr, i),
                  showTranslation: tr.showTranslation,
                  showPronunciation: tr.showPronunciation,
                  fontSize: widget.fontSize,
                  style: st,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _following = true;
                    final ts = lines[i].timestamp;
                    ref.read(playerProvider.notifier).player.seek(ts < Duration.zero ? Duration.zero : ts);
                  },
                ),
                // A long silence after this line: dots fill across it.
                if (i + 1 < lines.length && isInstrumentalGap(sungUntil(lines[i]), lines[i + 1].timestamp))
                  Consumer(
                    builder: (context, ref, _) => LyricGapDots(
                      active: ref.watch(lyricsControllerProvider.select((s) => s.activeLineIndex == i)),
                      startMs: sungUntil(lines[i]).inMilliseconds,
                      endMs: lines[i + 1].timestamp.inMilliseconds,
                      positionMs: () => ref.read(playerProvider.notifier).player.position.inMilliseconds,
                      size: widget.fontSize,
                      color: st.textPrimary,
                    ),
                  ),
              ],
            ],
          ),
        ),
    );
  }

  /// Line [i]'s translation, or null while there's nothing to show under it.
  LineTranslation? _extraFor(LyricsTranslationState tr, int i) {
    final data = tr.data;
    return tr.wanted && data != null ? data[i] : null;
  }

  Widget _plain(SyncedLyrics lyrics, NowPlayingStyle st) {
    final tr = ref.watch(lyricsTranslationProvider);
    final lines = lyrics.lines;
    final plainStyle = naviText(widget.fontSize * 0.72, FontWeight.w700, st.textPrimary.withValues(alpha: 0.86))
        .copyWith(height: 1.5);
    return SingleChildScrollView(
      key: const ValueKey('plain'),
      physics: PlatformUtils.isDesktop ? const ClampingScrollPhysics() : const BouncingScrollPhysics(),
      padding: widget.padding.copyWith(bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TranslateBar(style: st),
          if (!tr.wanted || tr.data == null)
            Text(lines.map((l) => l.text).join('\n'), style: plainStyle)
          else
            for (var i = 0; i < lines.length; i++)
              _PlainLine(
                text: lines[i].text.trim(),
                extra: tr.data![i],
                showTranslation: tr.showTranslation,
                showPronunciation: tr.showPronunciation,
                fontSize: widget.fontSize * 0.72,
                style: st,
                textStyle: plainStyle,
              ),
        ],
      ),
    );
  }
}

/// Smaller lines under an original lyric line: its Latin-script pronunciation
/// and its English translation, each only when switched on and present.
class _Extras extends StatelessWidget {
  final LineTranslation? extra;
  final bool showTranslation;
  final bool showPronunciation;
  final double fontSize;
  final NowPlayingStyle style;

  /// Multiplies the text colours; how far this line has receded.
  final double alpha;

  const _Extras({
    required this.extra,
    required this.showTranslation,
    required this.showPronunciation,
    required this.fontSize,
    required this.style,
    this.alpha = 1,
  });

  @override
  Widget build(BuildContext context) {
    final e = extra;
    if (e == null) return const SizedBox.shrink();
    final pron = showPronunciation ? e.pronunciation : '';
    final trans = showTranslation ? e.translation : '';
    if (pron.isEmpty && trans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: fontSize * 0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pron.isNotEmpty)
            Text(
              pron,
              style: naviText(fontSize, FontWeight.w600, style.textPrimary.withValues(alpha: 0.78 * alpha))
                  .copyWith(height: 1.25, fontStyle: FontStyle.italic),
            ),
          if (trans.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: pron.isNotEmpty ? fontSize * 0.1 : 0),
              child: Text(
                trans,
                style: naviText(fontSize, FontWeight.w600, style.textSecondary.withValues(alpha: style.textSecondary.a * alpha))
                    .copyWith(height: 1.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlainLine extends StatelessWidget {
  final String text;
  final LineTranslation extra;
  final bool showTranslation;
  final bool showPronunciation;
  final double fontSize;
  final NowPlayingStyle style;
  final TextStyle textStyle;

  const _PlainLine({
    required this.text,
    required this.extra,
    required this.showTranslation,
    required this.showPronunciation,
    required this.fontSize,
    required this.style,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return SizedBox(height: fontSize * 0.9);
    return Padding(
      padding: EdgeInsets.only(bottom: fontSize * 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: textStyle),
          _Extras(
            extra: extra,
            showTranslation: showTranslation,
            showPronunciation: showPronunciation,
            fontSize: fontSize * 0.62,
            style: style,
          ),
        ],
      ),
    );
  }
}

/// "Translate" and "Pronounce" switches above the lyrics, with the state of
/// the request beside them. Pill-shaped, in the pane's own colour contract.
class TranslateBar extends ConsumerWidget {
  final NowPlayingStyle style;
  const TranslateBar({super.key, required this.style});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = ref.watch(lyricsTranslationProvider);
    final ctl = ref.read(lyricsTranslationProvider.notifier);
    final data = tr.data;
    final String? note = tr.loading
        ? 'Working on it…'
        : tr.error != null
            ? null
            : (tr.wanted && data != null && data.sameLanguage)
                ? 'Already in English'
                : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Pill(
            key: const ValueKey('translate-pill'),
            label: 'Translate',
            on: tr.showTranslation,
            style: style,
            onTap: () => ctl.setTranslation(!tr.showTranslation),
          ),
          _Pill(
            key: const ValueKey('pronounce-pill'),
            label: 'Pronounce',
            on: tr.showPronunciation,
            style: style,
            onTap: () => ctl.setPronunciation(!tr.showPronunciation),
          ),
          if (note != null)
            Text(note, style: naviText(13, FontWeight.w600, style.textMuted)),
          if (tr.error != null)
            GestureDetector(
              key: const ValueKey('translate-retry'),
              behavior: HitTestBehavior.opaque,
              onTap: ctl.retry,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${tr.error}  Try again',
                  style: naviText(13, FontWeight.w600, style.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool on;
  final NowPlayingStyle style;
  final VoidCallback onTap;

  const _Pill({super.key, required this.label, required this.on, required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: on ? style.pillActive : style.pillIdle,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: naviText(13, FontWeight.w700, on ? style.pillOnActive : style.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One lyric line. It watches only its capped distance from the sung line, so
/// when the song moves on just the lines near it rebuild, not the whole list.
class _Line extends ConsumerWidget {
  final int index;
  final LyricLine line;

  /// When the next line starts: the sung line's last word ends here.
  final Duration endsAt;
  final LineTranslation? extra;
  final bool showTranslation;
  final bool showPronunciation;
  final double fontSize;
  final NowPlayingStyle style;
  final VoidCallback onTap;

  const _Line({
    super.key,
    required this.index,
    required this.line,
    required this.endsAt,
    required this.extra,
    required this.showTranslation,
    required this.showPronunciation,
    required this.fontSize,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Signed distance from the sung line, capped: lines far from it all share
    // one value, so when the song moves on only the lines near it rebuild.
    final distance = ref.watch(
      lyricsControllerProvider.select(
        (s) => (index - s.activeLineIndex).clamp(-LyricsMotion.maxDistance, LyricsMotion.maxDistance),
      ),
    );
    final text = line.text.trim();
    if (text.isEmpty) return SizedBox(height: fontSize * 0.9);
    final active = distance == 0;
    return Semantics(
      button: true,
      label: text,
      hint: 'Jump to this line',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // A shrunk line leaves its full-size box behind, so the padding is
          // tighter than the visual gap it would otherwise suggest.
          padding: EdgeInsets.symmetric(vertical: fontSize * 0.28),
          child: LyricLineMotion(
            distance: distance,
            // Alpha rides in the text colour, so no line needs an off-screen
            // layer to be dimmed.
            builder: (context, alpha) {
              final base = style.textPrimary;
              final textStyle = naviText(fontSize, FontWeight.w800, base.withValues(alpha: base.a * alpha))
                  .copyWith(height: 1.18);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (active && line.hasWordTimestamps)
                    // Only this widget repaints per frame, and only while its
                    // line is the sung one.
                    RepaintBoundary(
                      child: LyricWordSweep(
                        line: line,
                        endsAt: endsAt,
                        style: textStyle,
                        positionMs: () => ref.read(playerProvider.notifier).player.position.inMilliseconds,
                      ),
                    )
                  else
                    Text(text, style: textStyle),
                  _Extras(
                    extra: extra,
                    showTranslation: showTranslation,
                    showPronunciation: showPronunciation,
                    fontSize: fontSize * 0.5,
                    style: style,
                    alpha: alpha,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final NowPlayingStyle style;
  final EdgeInsets padding;
  const _Skeleton({super.key, required this.style, required this.padding});

  @override
  Widget build(BuildContext context) {
    const widths = [0.82, 0.58, 0.74, 0.46, 0.68];
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in widths)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: style.textPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final NowPlayingStyle style;
  final String title;
  final String body;
  final Widget? action;

  const _Message({super.key, required this.style, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: naviText(24, FontWeight.w800, style.textPrimary)),
          const SizedBox(height: 8),
          Text(body, style: naviText(15, FontWeight.w500, style.textSecondary).copyWith(height: 1.45)),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
