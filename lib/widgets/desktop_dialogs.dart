import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../utils/platform_utils.dart';

/// Shows [builder] as an iOS-style sheet: a card sliding up from the bottom on
/// phones, a centred card on desktop (bottom sheets feel wrong with a mouse).
/// [title], when given, is shown as a centred sheet title above the content;
/// otherwise the content supplies its own header.
Future<T?> showPlatformSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 440,
  double maxHeight = 680,
}) {
  final t = ThemeTokens.of(context);

  Widget body(BuildContext ctx) => title == null
      ? builder(ctx)
      : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.headline,
              ),
            ),
            builder(ctx),
          ],
        );

  if (PlatformUtils.isDesktop) {
    final size = MediaQuery.sizeOf(context);
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: t.bgSurface,
        insetPadding: const EdgeInsets.all(Space.xxl),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sheet)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(maxWidth, size.width * 0.9),
            maxHeight: min(maxHeight, size.height * 0.85),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: Space.lg),
            child: body(ctx),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    // Above the tab bar and mini player, which live in the root route.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: t.bgSurface,
    barrierColor: Colors.black54,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
      child: SingleChildScrollView(child: SafeArea(top: false, child: body(ctx))),
    ),
  );
}
