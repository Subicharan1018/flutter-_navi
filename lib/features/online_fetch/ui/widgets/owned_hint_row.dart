import 'package:flutter/cupertino.dart';

import '../../../../core/theme.dart';
import '../../../../utils/platform_utils.dart';
import '../../data/fetch_models.dart';

/// "You may already have: Title · Artist — Play". Sits above the online
/// results (never instead of them): the library may hold this song, but the
/// user can still pick something else from the results below.
class OwnedHintRow extends StatelessWidget {
  final LibraryMatch match;
  final VoidCallback onPlay;
  const OwnedHintRow({super.key, required this.match, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final g = PlatformUtils.isDesktop ? 0.0 : Space.gutter;
    final what = [match.title, if (match.artist.isNotEmpty) match.artist].join(' · ');
    return Padding(
      padding: EdgeInsets.fromLTRB(g, Space.sm, g, Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(style: t.footnote, children: [
                const TextSpan(text: 'You may already have: '),
                TextSpan(text: what, style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            minimumSize: const Size(44, 44),
            onPressed: onPlay,
            child: Text('Play', style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
