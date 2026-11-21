import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'edge_fade.dart';
import 'lyric_word_sweep.dart';
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

class _LyricsPaneState extends ConsumerState<LyricsPane> {
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  Timer? _userHold;
  bool _following = true;

  @override
  void dispose() {
    _scroll.dispose();
    _userHold?.cancel();
    super.dispose();
  }

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  void _follow(int index, {bool instant = false}) {
    if (!_following || index < 0) return;
    final ctx = _keys[index]?.currentContext;
    if (ctx == null) return;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3, // the sung line sits a third of the way down
      duration: instant || reduce ? Duration.zero : const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onUserScroll(UserScrollNotification n) {
    if (n.direction != ScrollDirection.idle) {
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
        (s) => (s.status, s.lyrics, s.source, s.wordSynced, s.errorMessage),
      ),
    );
    final st = widget.style;

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
            body: 'Lyrics appear here when your server, lrc.red, BetterLyrics or LRCLIB has them. '
                'Choose the sources in Settings.',
          ),
        LyricsStatus.error => _Message(
            key: const ValueKey('error'),
            style: st,
            title: 'Couldn’t load lyrics',
            body: state.$5 ?? 'Check your connection and try again.',
            action: TextButton(
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
      child: EdgeFade(
        top: 0.07,
        bottom: 0.14,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: PlatformUtils.isDesktop ? const ClampingScrollPhysics() : const BouncingScrollPhysics(),
          padding: widget.padding.copyWith(bottom: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslateBar(style: st),
              if (firstAt > const Duration(seconds: 3))
                Consumer(
                  builder: (context, ref, _) => ref.watch(lyricsControllerProvider.select((s) => s.activeLineIndex < 0))
                      ? _Breathing(style: st, size: widget.fontSize)
                      : const SizedBox.shrink(),
                ),
              for (int i = 0; i < lines.length; i++)
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
            ],
          ),
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

  const _Extras({
    required this.extra,
    required this.showTranslation,
    required this.showPronunciation,
    required this.fontSize,
    required this.style,
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
              style: naviText(fontSize, FontWeight.w600, style.textPrimary.withValues(alpha: 0.78))
                  .copyWith(height: 1.25, fontStyle: FontStyle.italic),
            ),
          if (trans.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: pron.isNotEmpty ? fontSize * 0.1 : 0),
              child: Text(
                trans,
                style: naviText(fontSize, FontWeight.w600, style.textSecondary).copyWith(height: 1.25),
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

enum _LineState { past, active, upcoming }

/// One lyric line. It watches only whether it is past, sung now or upcoming, so
/// when the song moves on exactly two lines rebuild, not the whole list.
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
    final state = ref.watch(
      lyricsControllerProvider.select(
        (s) => index == s.activeLineIndex
            ? _LineState.active
            : (index < s.activeLineIndex ? _LineState.past : _LineState.upcoming),
      ),
    );
    final text = line.text.trim();
    if (text.isEmpty) return SizedBox(height: fontSize * 0.9);
    final active = state == _LineState.active;
    final textStyle = naviText(fontSize, FontWeight.w800, style.textPrimary).copyWith(height: 1.18);
    return Semantics(
      button: true,
      label: text,
      hint: 'Jump to this line',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: fontSize * 0.36),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            opacity: active ? 1 : (state == _LineState.past ? 0.26 : 0.38),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              scale: active ? 1 : 0.965,
              alignment: Alignment.centerLeft,
              child: Column(
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

/// Three breathing dots for the instrumental intro, as in Apple Music.
class _Breathing extends StatefulWidget {
  final NowPlayingStyle style;
  final double size;
  const _Breathing({required this.style, required this.size});

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    reduce ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.size * 0.32;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.size * 0.5),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          children: List.generate(3, (i) {
            // Each dot breathes on the same sine, a fifth of a cycle apart.
            final t = 0.5 + 0.5 * math.sin(2 * math.pi * (_c.value - i * 0.2));
            return Container(
              width: d,
              height: d,
              margin: EdgeInsets.only(right: d * 0.6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.style.textPrimary.withValues(alpha: 0.3 + 0.6 * t),
              ),
            );
          }),
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
