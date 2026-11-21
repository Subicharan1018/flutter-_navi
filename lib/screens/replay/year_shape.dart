import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../utils/format.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/ui/media.dart';
import '../stats/widgets/stat_card.dart';

/// The card with the most minutes, or null when nothing was played.
ReplayMonthlyCard? busiestMonth(List<ReplayMonthlyCard> cards) {
  ReplayMonthlyCard? best;
  for (final c in cards) {
    if (c.totalMinutes > 0 && (best == null || c.totalMinutes > best.totalMinutes)) best = c;
  }
  return best;
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
