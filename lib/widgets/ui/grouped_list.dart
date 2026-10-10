import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// iOS "inset grouped" list section: optional header and footer, rows on a
/// rounded #1C1C1E surface with separators inset past the leading icon.
class GroupedSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;

  const GroupedSection({super.key, this.header, this.footer, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: _separatorInset(children[i])),
          child: Container(height: 0.5, color: t.outline),
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
              child: Text(header!, style: t.footnote),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.group),
            child: ColoredBox(color: t.bgSurface, child: Column(children: rows)),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
              child: Text(footer!, style: t.footnote),
            ),
        ],
      ),
    );
  }

  static double _separatorInset(Widget row) => switch (row) {
        GroupedRow(icon: final IconData _) ||
        GroupedSwitchRow(icon: final IconData _) ||
        GroupedTextFieldRow(icon: final IconData _) =>
          _iconInset,
        _ => Space.lg,
      };

  /// Where row text starts when the row has an icon square.
  static const double _iconInset = Space.lg + _iconSize + Space.md + 2;
}

const double _iconSize = 30;

/// The iOS Settings coloured square behind a row's glyph.
class _IconSquare extends StatelessWidget {
  final IconData icon;
  final Color? color;
  const _IconSquare({required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: _iconSize,
      height: _iconSize,
      decoration: BoxDecoration(color: color ?? t.accent, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 18, color: t.textPrimary),
    );
  }
}

/// One row in a [GroupedSection]. Pass [icon] for the iOS Settings-style
/// coloured square; [value] for trailing secondary text; [onTap] adds a
/// chevron unless [trailing] is given.
class GroupedRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showChevron;

  const GroupedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final titleColor = destructive ? t.danger : t.textPrimary;
    return _PressableRow(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
          child: Row(
            children: [
              if (icon != null) ...[
                _IconSquare(icon: icon!, color: iconColor),
                const SizedBox(width: Space.md + 2),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.body.copyWith(color: titleColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: t.footnote),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: Space.sm),
                // The title owns the row; the value takes what it needs up
                // to a cap, then ellipsizes (iOS Settings behaviour).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: t.body.copyWith(color: t.textSecondary),
                  ),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: Space.sm),
                trailing!,
              ] else if (onTap != null && showChevron && !destructive) ...[
                const SizedBox(width: Space.sm),
                Icon(CupertinoIcons.chevron_forward, size: 17, color: t.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A [GroupedRow] with an iOS switch.
class GroupedSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  const GroupedSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return GroupedRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: t.accent,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
      ),
    );
  }
}

/// A labelled text field row, as in iOS account settings: label on the left,
/// borderless field filling the rest. [obscure] adds a show/hide toggle.
class GroupedTextFieldRow extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final IconData? icon;
  final Color? iconColor;

  const GroupedTextFieldRow({
    super.key,
    required this.title,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.icon,
    this.iconColor,
  });

  @override
  State<GroupedTextFieldRow> createState() => _GroupedTextFieldRowState();
}

class _GroupedTextFieldRowState extends State<GroupedTextFieldRow> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.lg, right: Space.xs),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              _IconSquare(icon: widget.icon!, color: widget.iconColor),
              const SizedBox(width: Space.md + 2),
            ],
            SizedBox(width: 104, child: Text(widget.title, style: t.body)),
            Expanded(
              child: CupertinoTextField(
                controller: widget.controller,
                placeholder: widget.placeholder,
                obscureText: _hidden,
                keyboardType: widget.keyboardType,
                autocorrect: false,
                enableSuggestions: !widget.obscure,
                style: t.body,
                placeholderStyle: t.body.copyWith(color: t.textMuted),
                cursorColor: t.accent,
                decoration: null,
                padding: const EdgeInsets.symmetric(vertical: Space.md),
              ),
            ),
            if (widget.obscure)
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                minimumSize: const Size(40, 40),
                onPressed: () => setState(() => _hidden = !_hidden),
                child: Icon(
                  _hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 20,
                  color: t.textSecondary,
                  semanticLabel: _hidden ? 'Show password' : 'Hide password',
                ),
              )
            else
              const SizedBox(width: Space.md),
          ],
        ),
      ),
    );
  }
}

/// Row press feedback the iOS way: the row background dims while held.
class _PressableRow extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _PressableRow({required this.onTap, required this.child});

  @override
  State<_PressableRow> createState() => _PressableRowState();
}

class _PressableRowState extends State<_PressableRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    if (widget.onTap == null) return widget.child;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap!();
        },
        child: AnimatedContainer(
          duration: _down ? Duration.zero : Motion.fast,
          color: _down ? t.bgOverlay : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
