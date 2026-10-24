import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../art/navi_icons.dart';
import '../cover_art.dart';
import '../desktop_dialogs.dart';

/// Header of an action sheet: the item's artwork, title and subtitle, so the
/// person always sees what the actions apply to.
class SheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// A third, quieter line for facts about the item (language, genre, year).
  final String? detail;
  final String? artUrl;
  final NaviGlyph placeholderIcon;
  final bool circularArt;

  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.detail,
    this.artUrl,
    this.placeholderIcon = NaviGlyph.note,
    this.circularArt = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      child: Row(
        children: [
          CoverArt(url: artUrl, size: 56, radius: Radii.cover, circular: circularArt, placeholderIcon: placeholderIcon),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.headline),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                ],
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A group of actions on one rounded surface, separated by hairlines — the
/// iOS context-menu look.
class SheetGroup extends StatelessWidget {
  final List<Widget> children;
  const SheetGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final visible = children.whereType<Widget>().toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.group),
        child: ColoredBox(
          color: t.bgElevated,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                visible[i],
                if (i < visible.length - 1) Container(height: 0.5, color: t.outline),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One action row: label on the left, glyph on the right (as iOS context
/// menus lay them out). Closes the sheet before running [onTap] unless
/// [keepOpen] — used by progress rows such as Download.
class SheetAction extends StatelessWidget {
  final String label;
  final String? detail;
  final NaviGlyph? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool keepOpen;

  const SheetAction({
    super.key,
    required this.label,
    this.detail,
    this.icon,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.keepOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final enabled = onTap != null;
    final color = !enabled ? t.textMuted : (destructive ? t.danger : t.textPrimary);
    return InkWell(
      onTap: !enabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              if (!keepOpen) Navigator.of(context).pop();
              onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: t.body.copyWith(color: color)),
                    if (detail != null) Text(detail!, style: t.footnote),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              if (trailing != null)
                trailing!
              else if (icon != null)
                NaviIcon(icon!, size: 21, color: destructive ? t.danger : t.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-of-many picker as a sheet: each option with an optional explanation,
/// a checkmark on the current one. Returns the picked value, or null.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
  required String Function(T) label,
  String Function(T)? detail,
}) {
  return showPlatformSheet<T>(
    context: context,
    title: title,
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          for (final o in options)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(o);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label(o), style: t.body),
                          if (detail != null) ...[
                            const SizedBox(height: Space.xxs),
                            Text(detail(o), style: t.footnote),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    SizedBox(
                      width: 22,
                      child: o == selected ? NaviIcon(NaviGlyph.check, size: 22, color: t.accent) : null,
                    ),
                  ],
                ),
              ),
            ),
        ]),
      );
    },
  );
}

/// iOS confirmation for destructive actions. Returns true when confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final t = ThemeTokens.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: t.body.copyWith(color: t.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: t.headline.copyWith(color: t.danger)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Brief confirmation toast after an action ("Added to Queue").
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}
