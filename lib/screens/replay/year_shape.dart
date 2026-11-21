import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../utils/format.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/ui/media.dart';
import '../stats/widgets/stat_card.dart';

const _initials = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

/// The card with the most minutes, or null when nothing was played.
ReplayMonthlyCard? busiestMonth(List<ReplayMonthlyCard> cards) {
  ReplayMonthlyCard? best;
  for (final c in cards) {
    if (c.totalMinutes > 0 && (best == null || c.totalMinutes > best.totalMinutes)) best = c;
  }
  return best;
}

/// The year as one shape: twelve bars, the busiest month in white.
class YearRibbon extends StatelessWidget {
  final List<ReplayMonthlyCard> cards;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const YearRibbon({super.key, required this.cards, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final best = busiestMonth(cards);
    final byMonth = {for (final c in cards) c.month: c};
    final peak = best?.totalMinutes ?? 0;
    final dim = Color.lerp(t.bgBase, t.accent, 0.32)!;
    final full = context.motionFull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Your Year'),
        if (best != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
            child: Text(
              '${best.monthName} was your biggest month, ${listeningTime(best.totalMinutes.round())}.',
              style: t.subheadline,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: full ? 0 : 1, end: 1),
            duration: full ? const Duration(milliseconds: 700) : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, k, _) => SizedBox(
              height: 112,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var m = 1; m <= 12; m++)
                    Expanded(
                      child: _Bar(
                        card: byMonth[m],
                        initial: _initials[m - 1],
                        share: peak == 0 || byMonth[m] == null ? 0 : byMonth[m]!.totalMinutes / peak,
                        grow: k,
                        color: byMonth[m] == best ? t.accent : dim,
                        lead: byMonth[m] == best,
                        onOpen: onOpen,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final ReplayMonthlyCard? card;
  final String initial;
  final double share;
  final double grow;
  final Color color;
  final bool lead;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const _Bar({
    required this.card,
    required this.initial,
    required this.share,
    required this.grow,
    required this.color,
    required this.lead,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final c = card;
    final active = c != null && c.totalPlays > 0;
    return CupertinoClickable(
      onTap: active ? () => onOpen(c) : null,
      scaleFactor: 0.94,
      semanticLabel: c == null ? initial : '${c.monthName}, ${listeningTime(c.totalMinutes.round())}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: FractionallySizedBox(
              heightFactor: ((share * grow).clamp(0.0, 1.0) * 0.8 + 0.04 * (active ? 1 : 0)).clamp(0.02, 1.0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: active ? color : t.fill,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            initial,
            style: t.caption1.copyWith(
              color: lead ? t.textPrimary : t.textMuted,
              fontWeight: lead ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// The year month by month as a ledger: top song cover, month, top artist,
/// minutes and a hairline bar against the busiest month. No cards.
class MonthLedger extends ConsumerWidget {
  final List<ReplayMonthlyCard> cards;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const MonthLedger({super.key, required this.cards, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final peak = busiestMonth(cards)?.totalMinutes ?? 0;
    final sorted = [...cards]..sort((a, b) => a.month.compareTo(b.month));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Month by Month'),
        for (final c in sorted)
          _LedgerRow(
            card: c,
            share: peak == 0 ? 0 : c.totalMinutes / peak,
            cover: c.topTrack == null
                ? null
                : ref.watch(songCoverUrlProvider('${c.topTrack!.title}|${c.topTrack!.artist}')).asData?.value,
            tokens: t,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  final ReplayMonthlyCard card;
  final double share;
  final String? cover;
  final AppThemeTokens tokens;
  final ValueChanged<ReplayMonthlyCard> onOpen;
  const _LedgerRow({
    required this.card,
    required this.share,
    required this.cover,
    required this.tokens,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final active = card.totalPlays > 0;
    return CupertinoClickable(
      onTap: active ? () => onOpen(card) : null,
      scaleFactor: 0.99,
      semanticLabel: '${card.monthName}, ${card.totalPlays} plays',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.md),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: t.separatorOpaque, width: 0.5))),
        child: Row(
          children: [
            active
                ? CoverArt(url: cover, size: 44, radius: Radii.thumb)
                : SizedBox.square(dimension: 44, child: DecoratedBox(decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.thumb)))),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.monthName,
                          style: t.headline.copyWith(color: active ? t.textPrimary : t.textMuted),
                        ),
                      ),
                      Text(
                        active ? listeningTime(card.totalMinutes.round()) : '—',
                        style: figureStyle(t, 17).copyWith(color: active ? t.textPrimary : t.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active ? (card.topArtist?.artist ?? '${card.totalPlays} plays') : 'No listening',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.footnote,
                  ),
                  const SizedBox(height: Space.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: Stack(
                      children: [
                        Container(height: 2, color: t.fill),
                        FractionallySizedBox(
                          widthFactor: share.clamp(0.0, 1.0),
                          child: Container(height: 2, color: t.accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
