import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../providers/settings_provider.dart';
import '../../../../widgets/cover_art.dart';
import '../../data/trending_models.dart';

/// One chart song, as in Apple Music's Top charts: today's rank with its
/// movement underneath, the cover, title and artist. A song that isn't in
/// the library is dimmed and says why instead of the album.
class ChartRow extends ConsumerWidget {
  static const double height = 60;
  static const double _art = 46;

  final ChartEntry entry;
  final VoidCallback onTap;
  final bool showSeparator;

  const ChartRow({super.key, required this.entry, required this.onTap, this.showSeparator = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    // The library's own cover once the song is in it; the chart's until then.
    final art = entry.playable ? ref.read(subsonicServiceProvider).getCoverArtUrl(entry.songId!) : entry.coverUrl;
    final why = entry.unavailableLine;
    final dim = !entry.playable;
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.99,
      semanticLabel: [
        '${entry.rank}. ${entry.title} by ${entry.artist}',
        ?movementLabel(entry),
        ?why,
      ].join(', '),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            const SizedBox(width: Space.gutter),
            SizedBox(width: 30, child: _Rank(entry: entry)),
            Opacity(opacity: dim ? 0.45 : 1, child: CoverArt(url: art, size: _art, radius: Radii.thumb)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Container(
                height: height,
                padding: const EdgeInsets.only(right: Space.gutter),
                decoration: BoxDecoration(
                  border: showSeparator ? Border(bottom: BorderSide(color: t.outline, width: 0.5)) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: dim ? t.textMuted : t.textPrimary),
                    ),
                    Text(
                      why == null ? entry.artist : '${entry.artist} · $why',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.footnote.copyWith(color: dim ? t.textMuted : t.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Up 3", "New" … for screen readers; null when there's nothing to say.
String? movementLabel(ChartEntry e) => switch (e.movement) {
      ChartMovement.up => 'up ${e.change}',
      ChartMovement.down => 'down ${e.change}',
      ChartMovement.isNew => 'new entry',
      ChartMovement.same || null => null,
    };

class _Rank extends StatelessWidget {
  final ChartEntry entry;
  const _Rank({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.rank}',
          style: t.callout.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 1),
        MovementMark(entry: entry),
      ],
    );
  }
}

/// The small marker under a rank: ▲ / ▼ (monochrome, like the rest of the
/// chrome), "NEW", or a dash when the song held its place.
class MovementMark extends StatelessWidget {
  final ChartEntry entry;
  const MovementMark({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final small = t.caption2.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ExcludeSemantics(
      child: switch (entry.movement) {
        ChartMovement.up => Icon(CupertinoIcons.arrowtriangle_up_fill, size: 8, color: t.textPrimary),
        ChartMovement.down => Icon(CupertinoIcons.arrowtriangle_down_fill, size: 8, color: t.textMuted),
        ChartMovement.isNew => Text('NEW', style: small.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700)),
        ChartMovement.same => Text('–', style: small.copyWith(color: t.textMuted)),
        null => const SizedBox(height: 8),
      },
    );
  }
}
