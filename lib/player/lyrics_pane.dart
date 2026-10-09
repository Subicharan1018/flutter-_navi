import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../lyrics/controllers/lyrics_controller.dart';
import '../lyrics/models/lyric_line.dart';
import '../providers/player_provider.dart';
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
    final state = ref.watch(lyricsControllerProvider);
    final st = widget.style;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: switch (state.status) {
        LyricsStatus.loading => _Skeleton(key: const ValueKey('loading'), style: st, padding: widget.padding),
        LyricsStatus.synced => _synced(state),
        LyricsStatus.plain => _plain(state.lyrics!, st),
        LyricsStatus.empty => _Message(
            key: const ValueKey('empty'),
            style: st,
            title: 'No lyrics for this song',
            body: 'Lyrics appear here when your server or LRCLIB has them.',
          ),
        LyricsStatus.error => _Message(
            key: const ValueKey('error'),
            style: st,
            title: 'Couldn’t load lyrics',
            body: state.errorMessage ?? 'Check your connection and try again.',
            action: TextButton(
              onPressed: () => ref.read(lyricsControllerProvider.notifier).retry(),
              child: Text('Try again', style: naviText(15, FontWeight.w600, st.textPrimary)),
            ),
          ),
      },
    );
  }

  Widget _synced(LyricsState state) {
    final lines = state.lyrics!.lines;
    final active = state.activeLineIndex;
    final st = widget.style;
    final firstAt = lines.isEmpty ? Duration.zero : lines.first.timestamp;

    return NotificationListener<UserScrollNotification>(
      key: const ValueKey('synced'),
      onNotification: _onUserScroll,
      child: ShaderMask(
        // Soft fade at both edges instead of hard clipping.
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.07, 0.86, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: widget.padding.copyWith(bottom: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (active < 0 && firstAt > const Duration(seconds: 3))
                _Breathing(style: st, size: widget.fontSize),
              for (int i = 0; i < lines.length; i++)
                _Line(
                  key: _keyFor(i),
                  line: lines[i],
                  state: i == active ? _LineState.active : (i < active ? _LineState.past : _LineState.upcoming),
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

  Widget _plain(SyncedLyrics lyrics, NowPlayingStyle st) {
    return SingleChildScrollView(
      key: const ValueKey('plain'),
      physics: const BouncingScrollPhysics(),
      padding: widget.padding.copyWith(bottom: 120),
      child: Text(
        lyrics.lines.map((l) => l.text).join('\n'),
        style: naviText(widget.fontSize * 0.72, FontWeight.w700, st.textPrimary.withValues(alpha: 0.86))
            .copyWith(height: 1.5),
      ),
    );
  }
}

enum _LineState { past, active, upcoming }

class _Line extends StatelessWidget {
  final LyricLine line;
  final _LineState state;
  final double fontSize;
  final NowPlayingStyle style;
  final VoidCallback onTap;

  const _Line({
    super.key,
    required this.line,
    required this.state,
    required this.fontSize,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = line.text.trim();
    if (text.isEmpty) return SizedBox(height: fontSize * 0.9);
    final active = state == _LineState.active;
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
              child: Text(
                text,
                style: naviText(fontSize, FontWeight.w800, style.textPrimary).copyWith(height: 1.18),
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
