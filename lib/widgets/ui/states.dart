import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../art/empty_art.dart';
import 'media.dart';

export '../art/empty_art.dart' show EmptyArtKind;

/// Empty or error content: a quiet glyph, one line saying what's going on,
/// one saying what to do, one action (plus, rarely, a lesser second one).
/// Centred, like iOS.
class MessageState extends StatelessWidget {
  /// Only needed when there is no [art] or [illustration] to show.
  final IconData? icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A lesser second action, shown as plain accent text under [actionLabel].
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// An illustration under `assets/icons/` (name without extension) shown in
  /// place of [icon].
  final String? illustration;

  /// A drawn, code-made illustration (see `EmptyArt`); wins over [icon] but
  /// not over [illustration].
  final EmptyArtKind? art;

  static const double _illustrationSize = 96;

  const MessageState({
    super.key,
    this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.illustration,
    this.art,
  });

  /// Something failed to load.
  factory MessageState.error({
    Key? key,
    required String title,
    String message = 'Check your connection to the server, then try again.',
    required VoidCallback onRetry,
    String? illustration,
  }) =>
      MessageState(
        key: key,
        icon: CupertinoIcons.wifi_exclamationmark,
        art: illustration == null ? EmptyArtKind.offline : null,
        title: title,
        message: message,
        actionLabel: 'Try again',
        onAction: onRetry,
        illustration: illustration,
      );

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.huge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null)
                Image.asset(
                  'assets/icons/$illustration.png',
                  width: _illustrationSize,
                  height: _illustrationSize,
                  cacheWidth: (_illustrationSize * MediaQuery.devicePixelRatioOf(context)).round(),
                  excludeFromSemantics: true,
                )
              else if (art != null)
                ExcludeSemantics(child: EmptyArt(art!, width: 128))
              else if (icon != null)
                Icon(icon, size: 48, color: t.textMuted),
              const SizedBox(height: Space.lg),
              Text(title, textAlign: TextAlign.center, style: t.title3),
              const SizedBox(height: Space.sm),
              Text(message, textAlign: TextAlign.center, style: t.subheadline),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Space.xl),
                TintedButton(label: actionLabel!, onTap: onAction),
              ],
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(height: Space.sm),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  minimumSize: const Size(44, 44),
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!, style: t.subheadline.copyWith(color: t.accent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A shelf that failed to load, said in one line with Try again beside it —
/// for sections inside a page (Home), where a full [MessageState] is too loud.
class InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const InlineError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Row(
        children: [
          Expanded(child: Text(message, style: t.footnote)),
          const SizedBox(width: Space.md),
          TintedButton(label: 'Try again', onTap: onRetry),
        ],
      ),
    );
  }
}

/// iOS activity indicator centred in the available space.
class LoadingState extends StatelessWidget {
  final String? label;
  const LoadingState({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 12),
            if (label != null) ...[
              const SizedBox(height: Space.md),
              Text(label!, style: t.footnote),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grey placeholder block shaped like the content it stands in for.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, required this.width, required this.height, this.radius = Radii.thumb});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: ThemeTokens.of(context).bgSurface,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder rows matching a track list while it loads.
class TrackListSkeleton extends StatelessWidget {
  final int rows;
  final bool artwork;
  const TrackListSkeleton({super.key, this.rows = 8, this.artwork = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.sm),
            child: Row(
              children: [
                if (artwork) ...[
                  const SkeletonBox(width: 48, height: 48),
                  const SizedBox(width: Space.md),
                ],
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 170, height: 13),
                    SizedBox(height: Space.sm),
                    SkeletonBox(width: 110, height: 11),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
