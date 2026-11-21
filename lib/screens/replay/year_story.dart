import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/month/ui/story/story_cards.dart';
import '../../features/month/ui/story/story_pager.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../utils/format.dart';
import '../../widgets/art/generated_cover.dart';
import '../../widgets/motion/number_roll.dart';
import '../../widgets/motion/play_once.dart';
import 'year_scrubber.dart' show monthNames;
import 'year_shape.dart' show busiestMonth;

// Like the month story: always white on black, so it reads the same in every theme.
const _ink = Color(0xFFFFFFFF);
const _dim = Color(0xFF9E9EA4);
const _bar = Color(0xFF4A4A4E);

/// Opens the year as a full-screen story.
Future<void> showYearStory(BuildContext context, YearlyReplayResponse replay) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Motion.slow,
        reverseTransitionDuration: Motion.standard,
        pageBuilder: (_, _, _) => CupertinoPageScaffold(
          backgroundColor: const Color(0xFF000000),
          child: YearStory(replay: replay, onClose: () => Navigator.of(context).maybePop()),
        ),
        transitionsBuilder: (context, a, _, child) => MediaQuery.disableAnimationsOf(context)
            ? child
            : FadeTransition(
                opacity: a,
                child: ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.ease)),
                  child: child,
                ),
              ),
      ),
    );

/// Minutes, No. 1 song, your artists, the shape of the year, the receipt.
/// Tap right/left to move, hold to pause (see [StoryPager]).
class YearStory extends StatelessWidget {
  final YearlyReplayResponse replay;
  final VoidCallback? onClose;
  const YearStory({super.key, required this.replay, this.onClose});

  @override
  Widget build(BuildContext context) {
    const long = Duration(seconds: 7);
    final r = replay;
    return StoryPager(
      onClose: onClose,
      pages: [
        StoryPage(duration: long, builder: (_, p) => _MinutesCard(r: r, p: p)),
        if (r.topTracks.isNotEmpty) StoryPage(duration: long, builder: (_, p) => _TopSongCard(track: r.topTracks.first, p: p)),
        if (r.topArtists.isNotEmpty) StoryPage(duration: long, builder: (_, p) => _ArtistsCard(artists: r.topArtists, p: p)),
        if (busiestMonth(r.monthlyCards) != null) StoryPage(duration: long, builder: (_, p) => _ShapeCard(r: r, p: p)),
        StoryPage(duration: long, builder: (_, p) => _ReceiptCard(r: r, p: p)),
      ],
    );
  }
}

class _MinutesCard extends StatelessWidget {
  final YearlyReplayResponse r;
  final Animation<double> p;
  const _MinutesCard({required this.r, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return StoryFrame(
      p: p,
      kicker: 'Replay ${r.year}',
      headline: 'You listened for',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumberRoll(
              value: r.totalMinutes.round(),
              format: listeningTime,
              progress: p,
              window: 0.45,
              style: t.textStyle(88, FontWeight.w800, _ink).copyWith(
                height: 1.05,
                letterSpacing: -4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          StoryIn(
            p: p,
            begin: 0.45,
            end: 0.65,
            child: Text(
              '${compactCount(r.totalPlays)} plays · ${r.uniqueSongs} different songs\n${r.listeningDays} days with music',
              style: t.body.copyWith(color: _dim, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopSongCard extends ConsumerWidget {
  final ReplayTrack track;
  final Animation<double> p;
  const _TopSongCard({required this.track, required this.p});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final url = ref.watch(songCoverUrlProvider('${track.title}|${track.artist}')).asData?.value;
    return StoryFrame(
      p: p,
      kicker: 'Your song of the year',
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: p,
                        builder: (context, _) => CustomPaint(painter: PulseRingsPainter(p.value)),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: 0.66,
                      heightFactor: 0.66,
                      child: StoryIn(p: p, begin: 0, end: 0.2, child: StoryCover(url: url, name: track.title)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          StoryIn(
            p: p,
            begin: 0.2,
            end: 0.4,
            child: Column(
              children: [
                Text(track.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textStyle(26, FontWeight.w700, _ink)),
                const SizedBox(height: Space.xs),
                Text(track.artist, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(color: _dim)),
                const SizedBox(height: Space.md),
                Text('${track.playCount} plays', style: t.subheadline.copyWith(color: _dim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular artist photo (their own, via [artistCoverUrlProvider]) over a
/// generated cover, so an artist with no photo still gets a handsome circle.
class _Portrait extends ConsumerWidget {
  final String name;
  final double size;
  const _Portrait({required this.name, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(artistCoverUrlProvider(name)).asData?.value;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GeneratedCover(name: name),
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: (size * 3).round(),
                fadeInDuration: Motion.standard,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

/// No. 1 large, the next four below; each rises into place in turn.
class _ArtistsCard extends StatelessWidget {
  final List<ReplayArtist> artists;
  final Animation<double> p;
  const _ArtistsCard({required this.artists, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final top = artists.take(5).toList();
    Widget rise(int i, Widget child) => AnimatedBuilder(
      animation: p,
      child: child,
      builder: (context, child) {
        final k = sliceOf(p.value, 0.04 + i * 0.09, 0.3 + i * 0.09);
        return Opacity(opacity: k, child: Transform.translate(offset: Offset(0, 40 * (1 - k)), child: child));
      },
    );
    return StoryFrame(
      p: p,
      kicker: 'Your top artists',
      headline: '${top.first.artist} led the year',
      child: LayoutBuilder(
        builder: (context, c) {
          final big = (c.maxHeight * 0.5).clamp(120.0, c.maxWidth * 0.7);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              rise(0, _Portrait(name: top.first.artist, size: big)),
              const SizedBox(height: Space.md),
              rise(
                0,
                Text('${compactCount(top.first.playCount)} plays', style: t.body.copyWith(color: _dim)),
              ),
              const Spacer(),
              Row(
                children: [
                  for (final (i, a) in top.skip(1).indexed)
                    Expanded(
                      child: rise(
                        i + 1,
                        Column(
                          children: [
                            _Portrait(name: a.artist, size: ((c.maxWidth - 3 * Space.md) / 4).clamp(48.0, 84.0)),
                            const SizedBox(height: Space.xs),
                            Text(
                              a.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: t.caption1.copyWith(color: _ink, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The year set in type: each month's name sized by its minutes, the busiest
/// in white and largest, the rest dimmer; lines rise in turn.
class _ShapeCard extends StatelessWidget {
  final YearlyReplayResponse r;
  final Animation<double> p;
  const _ShapeCard({required this.r, required this.p});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final best = busiestMonth(r.monthlyCards)!;
    final byMonth = {for (final c in r.monthlyCards) c.month: c};
    return StoryFrame(
      p: p,
      kicker: 'The shape of ${r.year}',
      headline: '${best.monthName} was your biggest month',
      child: LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: box.maxWidth,
            child: AnimatedBuilder(
              animation: p,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var m = 1; m <= 12; m++)
                    Builder(
                      builder: (context) {
                        final c = byMonth[m];
                        final share = c == null || best.totalMinutes == 0 ? 0.0 : c.totalMinutes / best.totalMinutes;
                        final k = sliceOf(p.value, 0.04 + m * 0.045, 0.3 + m * 0.045);
                        final lead = c == best;
                        return Opacity(
                          opacity: k,
                          child: Transform.translate(
                            offset: Offset(0, 24 * (1 - k)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  c?.monthName ?? monthNames[m - 1],
                                  style: t
                                      .textStyle(20 + 44 * share, FontWeight.w800, lead ? _ink : (share > 0 ? _dim : _bar))
                                      .copyWith(height: 1.12, letterSpacing: -1),
                                ),
                                const Spacer(),
                                Text(
                                  c == null || c.totalPlays == 0 ? '' : listeningTime(c.totalMinutes.round()),
                                  style: t.callout.copyWith(color: lead ? _ink : _dim, fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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

class _ReceiptCard extends StatelessWidget {
  final YearlyReplayResponse r;
  final Animation<double> p;
  const _ReceiptCard({required this.r, required this.p});

  @override
  Widget build(BuildContext context) => StoryFrame(
    p: p,
    kicker: 'Your ${r.year} in one line',
    child: Center(
      child: StoryIn(p: p, begin: 0.05, end: 0.35, child: YearReceipt(replay: r, ink: _ink, dim: _dim)),
    ),
  );
}

/// The year as a receipt: a label, a dotted leader and a value per line, set
/// as type on the page with a hairline dash above and below. No container.
class YearReceipt extends StatelessWidget {
  final YearlyReplayResponse replay;
  final Color ink;
  final Color dim;
  const YearReceipt({super.key, required this.replay, required this.ink, required this.dim});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final r = replay;
    final best = busiestMonth(r.monthlyCards);
    final lines = <(String, String)>[
      if (r.topTracks.isNotEmpty) ('TOP SONG', r.topTracks.first.title),
      if (r.topArtists.isNotEmpty) ('TOP ARTIST', r.topArtists.first.artist),
      ('LISTENED', listeningTime(r.totalMinutes.round())),
      ('PLAYS', compactCount(r.totalPlays)),
      if (best != null) ('BIGGEST MONTH', best.monthName),
      ('PEAK HOUR', hourLabel(r.peakHourIst)),
      ('DAYS WITH MUSIC', '${r.listeningDays}'),
      ('SKIPPED', r.skipRateLabel),
    ];
    final label = t.caption1.copyWith(color: dim, letterSpacing: 1.2, fontWeight: FontWeight.w600);
    final value = t.callout.copyWith(color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    final rule = _Dashes(color: dim.withValues(alpha: 0.5));
    return Semantics(
      container: true,
      label: 'Your ${r.year} in one line',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rule,
          const SizedBox(height: Space.md),
          for (final (k, v) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(k, style: label),
                  Expanded(child: _Leader(color: dim.withValues(alpha: 0.6))),
                  // The value takes what it needs up to half the screen; the leader fills the rest.
                  LayoutBuilder(
                    builder: (context, _) => ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                      child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: value),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.md),
          rule,
        ],
      ),
    );
  }
}

class _Leader extends StatelessWidget {
  final Color color;
  const _Leader({required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 3),
    child: SizedBox(height: 2, child: CustomPaint(painter: _DotPainter(color, dot: 1.2, gap: 4))),
  );
}

class _Dashes extends StatelessWidget {
  final Color color;
  const _Dashes({required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(height: 1, child: CustomPaint(painter: _DotPainter(color, dot: 4, gap: 4)));
}

class _DotPainter extends CustomPainter {
  final Color color;
  final double dot;
  final double gap;
  const _DotPainter(this.color, {required this.dot, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height.clamp(1.0, 2.0);
    for (var x = 0.0; x < size.width; x += dot + gap) {
      canvas.drawLine(Offset(x, size.height / 2), Offset((x + dot).clamp(0, size.width), size.height / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color || old.dot != dot || old.gap != gap;
}
