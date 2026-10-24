import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/ui/states.dart';
import '../../../listen/data/listen_models.dart';
import '../../../share/card_capture.dart';
import '../../logic/month_providers.dart';
import 'month_summary_card.dart';
import 'story_cards.dart';
import 'story_pager.dart';

/// Opens your month as a full-screen story. [month] null is this month.
Future<void> showMonthStory(BuildContext context, {MonthKey? month}) =>
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Motion.slow,
        reverseTransitionDuration: Motion.standard,
        pageBuilder: (_, _, _) => MonthStoryScreen(month: month),
        transitionsBuilder: (context, a, _, child) => MediaQuery.disableAnimationsOf(context)
            ? child
            : FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Motion.ease)), child: child)),
      ),
    );

/// Loads the month, then plays it.
class MonthStoryScreen extends ConsumerWidget {
  final MonthKey? month;
  const MonthStoryScreen({super.key, this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(monthStatsProvider(month));
    final stats = async.asData?.value;
    void close() => Navigator.of(context).maybePop();
    return CupertinoPageScaffold(
      backgroundColor: ThemeTokens.of(context).bgBase,
      child: stats != null && !stats.isEmpty
          ? MonthStory(stats: stats, onClose: close)
          : SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: async.when(
                      loading: () => const CupertinoActivityIndicator(),
                      error: (_, _) => MessageState.error(
                        title: 'Your story didn’t load',
                        message: 'Check your connection, then try again.',
                        onRetry: () => ref.invalidate(monthStatsProvider(month)),
                      ),
                      data: (_) => const MessageState(
                        icon: NaviGlyph.calendar,
                        title: 'Nothing played this month',
                        message: 'Play some music and your story builds here.',
                      ),
                    ),
                  ),
                  Positioned(
                    top: Space.sm,
                    right: Space.md,
                    child: CupertinoClickable(
                      onTap: close,
                      semanticLabel: 'Close',
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(child: NaviIcon(NaviGlyph.close, size: 20, color: ThemeTokens.of(context).textPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The story for one month of stats: minutes, top song, who you played, the
/// calendar, the streak, and a closing card you can send as a picture.
class MonthStory extends StatelessWidget {
  final MonthStats stats;
  final VoidCallback? onClose;
  const MonthStory({super.key, required this.stats, this.onClose});

  @override
  Widget build(BuildContext context) {
    const long = Duration(seconds: 7);
    final song = stats.topSongs.firstOrNull;
    return StoryPager(
      onClose: onClose,
      pages: [
        StoryPage(duration: long, builder: (_, p) => MinutesCard(stats: stats, p: p)),
        if (song != null) StoryPage(duration: long, builder: (_, p) => TopSongCard(song: song, p: p)),
        if (stats.topArtists.isNotEmpty)
          StoryPage(
            duration: long,
            builder: (_, p) => PeopleCard(kicker: 'Your top artists', headline: '${stats.topArtists.first.name} led the month', people: stats.topArtists, p: p),
          ),
        if (stats.topComposers.isNotEmpty)
          StoryPage(
            duration: long,
            builder: (_, p) => PeopleCard(kicker: 'Your top composers', headline: '${stats.topComposers.first.name} wrote your month', people: stats.topComposers, p: p),
          ),
        StoryPage(duration: long, builder: (_, p) => CalendarCard(stats: stats, p: p)),
        if (stats.streakDays > 0) StoryPage(duration: long, builder: (_, p) => StreakCard(stats: stats, p: p)),
        StoryPage(duration: long, builder: (_, p) => SummaryPage(stats: stats, p: p)),
      ],
    );
  }
}

/// The closing card, shown at size, with a button that sends it as an image.
class SummaryPage extends StatefulWidget {
  final MonthStats stats;
  final Animation<double> p;
  const SummaryPage({super.key, required this.stats, required this.p});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = widget.stats;
      final file = await renderCardPng(_key, logicalWidth: MonthSummaryCard.width, name: 'navivibe_month_${s.year}_${s.month}');
      await SharePlus.instance.share(
        ShareParams(
          text: 'My ${s.monthName} on NaviVibe: ${minutesLabel(s.totalMinutes)} listened.',
          files: file == null ? null : [XFile(file.path, mimeType: 'image/png')],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return StoryFrame(
      p: widget.p,
      kicker: 'That’s your ${widget.stats.monthName}',
      child: Column(
        children: [
          Expanded(
            child: StoryIn(
              p: widget.p,
              begin: 0.05,
              end: 0.3,
              child: Center(
                child: FittedBox(
                  child: RepaintBoundary(key: _key, child: MonthSummaryCard(stats: widget.stats)),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),
          CupertinoClickable(
            onTap: _share,
            semanticLabel: 'Share your month as an image',
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(25)),
              child: _busy
                  ? const CupertinoActivityIndicator(color: Color(0xFF000000))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NaviIcon(NaviGlyph.share, size: 18, color: Color(0xFF000000)),
                        const SizedBox(width: Space.sm),
                        Text('Share', style: t.headline.copyWith(color: const Color(0xFF000000))),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
