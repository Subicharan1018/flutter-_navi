import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import 'preview_feed_screen.dart';

/// Home's door to Swipe to fetch. Hidden unless this account may download (the feed's hearts fetch songs).
class PreviewFeedEntry extends ConsumerWidget {
  const PreviewFeedEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onlineFetchEnabledProvider).asData?.value != true) {
      return const SizedBox.shrink();
    }
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Swipe to fetch: 30-second previews of songs you don’t own',
      child: InkWell(
        onTap: () => openPreviewFeed(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.md,
          ),
          child: Row(
            children: [
              NaviIcon(NaviGlyph.heart, size: 22, color: t.textPrimary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Swipe to fetch', style: t.headline),
                    const SizedBox(height: 2),
                    Text(
                      '30-second previews of songs you don’t own',
                      style: t.subheadline,
                    ),
                  ],
                ),
              ),
              NaviIcon(NaviGlyph.chevron, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
