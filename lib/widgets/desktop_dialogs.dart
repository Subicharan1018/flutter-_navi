import 'dart:math' show min;
import 'package:flutter/material.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// desktop_dialogs.dart — Platform-adaptive dialog / bottom sheet helper
//
// On mobile  → showModalBottomSheet  (native slide-up sheet)
// On desktop → showDialog            (centered, size-constrained modal)
//
// Usage:
//   showPlatformSheet(
//     context: context,
//     title: 'Options',              // optional — desktop only, shown as dialog title
//     builder: (_) => MyWidget(),
//   );
// =============================================================================

/// Shows a [ModalBottomSheet] on mobile and a centred [Dialog] on desktop.
///
/// [title] is only shown on desktop (as a small header row above the content).
/// [maxWidth] / [maxHeight] cap the desktop dialog size (in logical pixels).
Future<T?> showPlatformSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 520,
  double maxHeight = 680,
}) {
  if (PlatformUtils.isDesktop) {
    // ── Desktop: centred dialog ──────────────────────────────────────────────
    final screenSize = MediaQuery.of(context).size;
    final effectiveMaxHeight = min(maxHeight, screenSize.height * 0.85);
    final effectiveMaxWidth = min(maxWidth, screenSize.width * 0.90);

    return showDialog<T>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final tokens = Theme.of(ctx).extension<Object>();
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: effectiveMaxWidth,
              maxHeight: effectiveMaxHeight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                color: Theme.of(ctx).colorScheme.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      _DesktopDialogTitleBar(title: title, context: ctx),
                    Flexible(
                      child: SingleChildScrollView(
                        child: builder(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Mobile: native bottom sheet ─────────────────────────────────────────────
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: builder,
  );
}

// ── Private desktop title bar ─────────────────────────────────────────────────

class _DesktopDialogTitleBar extends StatelessWidget {
  const _DesktopDialogTitleBar({
    required this.title,
    required this.context,
  });

  final String title;
  final BuildContext context;

  @override
  Widget build(BuildContext _) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
