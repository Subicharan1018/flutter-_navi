import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../core/pointer_anchor.dart';
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
  bool menu = false,
}) {
  final t = ThemeTokens.of(context);
  if (menu && PlatformUtils.isDesktop) {
    return showDesktopMenu<T>(context: context, builder: builder);
  }

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

/// True inside a desktop context menu: the sheet primitives ([SheetHeader],
/// [SheetGroup], [SheetAction]) draw their compact, hover-highlighted form.
class MenuMode extends InheritedWidget {
  const MenuMode({super.key, required super.child});
  static bool of(BuildContext context) => context.getInheritedWidgetOfExactType<MenuMode>() != null;
  @override
  bool updateShouldNotify(MenuMode old) => false;
}

/// A desktop context menu: a small popover opened where the pointer is (or, when
/// there was no pointer, centred), clamped inside the window, closed by Esc or a
/// click outside. The content is the same widgets a phone shows as a sheet.
Future<T?> showDesktopMenu<T>({required BuildContext context, required WidgetBuilder builder, double width = 252}) {
  final t = ThemeTokens.of(context);
  final screen = MediaQuery.sizeOf(context);
  final at = PointerAnchor.recent();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    pageBuilder: (ctx, _, _) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(ctx).pop()},
      child: Focus(
        autofocus: true,
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(at, screen),
          child: MenuMode(
            child: Material(
              color: t.bgElevated,
              elevation: 12,
              shadowColor: Colors.black,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: t.outline, width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: width,
                  maxWidth: width,
                  maxHeight: min(screen.height - 24, 640),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: builder(ctx),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _MenuLayout extends SingleChildLayoutDelegate {
  final Offset? at;
  final Size screen;
  _MenuLayout(this.at, this.screen);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints.loose(screen);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final a = at ?? Offset((size.width - child.width) / 2, (size.height - child.height) / 3);
    final x = a.dx.clamp(8.0, (size.width - child.width - 8).clamp(8.0, double.infinity));
    final y = a.dy.clamp(8.0, (size.height - child.height - 8).clamp(8.0, double.infinity));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.at != at || old.screen != screen;
}
