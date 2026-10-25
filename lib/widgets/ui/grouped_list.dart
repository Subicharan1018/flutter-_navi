import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../art/navi_icons.dart';
import '../../utils/platform_utils.dart';
import 'voice_search_button.dart';

/// iOS "inset grouped" list section: optional header and footer, rows on a
/// rounded #1C1C1E surface with separators inset past the leading icon.
class GroupedSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;

  const GroupedSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: _separatorInset(children[i])),
            child: Container(height: 0.5, color: t.outline),
          ),
        );
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        0,
        Space.gutter,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Text(header!, style: t.footnote),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.group),
            child: ColoredBox(
              color: t.bgSurface,
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                0,
              ),
              child: Text(footer!, style: t.footnote),
            ),
        ],
      ),
    );
  }

  static double _separatorInset(Widget row) => switch (row) {
    GroupedRow(icon: final NaviGlyph _) ||
    GroupedSwitchRow(icon: final NaviGlyph _) ||
    GroupedTextFieldRow(icon: final NaviGlyph _) => _iconInset,
    _ => Space.lg,
  };

  /// Where row text starts when the row has an icon square.
  static const double _iconInset = Space.lg + _iconSize + Space.md + 2;
}

const double _iconSize = 30;

/// The iOS Settings square behind a row's glyph. Monochrome — every row gets
/// the same neutral tile ([AppThemeTokens.iconTile]) with a white glyph.
class _IconSquare extends StatelessWidget {
  static const double _glyph = 18;
  final NaviGlyph icon;
  const _IconSquare({required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: _iconSize,
      height: _iconSize,
      decoration: BoxDecoration(
        color: AppThemeTokens.iconTile,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: NaviIcon(icon, size: _glyph, color: t.textPrimary),
    );
  }
}

/// One row in a [GroupedSection]. Pass [icon] for the iOS Settings-style
/// square; [value] for trailing secondary text; [onTap] adds a chevron
/// unless [trailing] is given.
class GroupedRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final NaviGlyph? icon;

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
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm + 2,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                _IconSquare(icon: icon!),
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
                NaviIcon(NaviGlyph.chevron, size: 17, color: t.textMuted),
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
  final NaviGlyph? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const GroupedSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
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
      trailing: CupertinoSwitch(
        value: value,
        activeTrackColor: t.accent,
        // Monochrome: the accent track is white, so the "on" thumb is black;
        // "off" keeps the white thumb on the dark track.
        thumbColor: t.onAccent,
        inactiveThumbColor: t.textPrimary,
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
  final NaviGlyph? icon;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  /// A microphone at the end of the row for dictating the value.
  final bool voice;

  const GroupedTextFieldRow({
    super.key,
    required this.title,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.icon,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.autofocus = false,
    this.autofillHints,
    this.voice = false,
  });

  @override
  State<GroupedTextFieldRow> createState() => _GroupedTextFieldRowState();
}

class _GroupedTextFieldRowState extends State<GroupedTextFieldRow> {
  late bool _hidden = widget.obscure;
  FocusNode? _own;
  FocusNode get _node =>
      widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'grouped-field'));
  bool _ring = false;

  /// On a TV the keyboard opens only when Select is pressed on a field: moving
  /// over it with the D-pad must not throw the on-screen keyboard up.
  bool _editing = false;
  bool get _readOnly => PlatformUtils.isTv && !_editing;

  @override
  void initState() {
    super.initState();
    _node.addListener(_focusChanged);
    FocusManager.instance.addHighlightModeListener(_modeChanged);
    if (PlatformUtils.isTv) _node.onKeyEvent = _tvKey;
  }

  @override
  void didUpdateWidget(GroupedTextFieldRow old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _own)?.removeListener(_focusChanged);
      _node.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _node.removeListener(_focusChanged);
    _own?.dispose();
    super.dispose();
  }

  /// TV remote on a text field. Flutter treats arrows in a text field as caret
  /// movement and never moves focus, which would trap the D-pad here; so while
  /// the field is not being edited the arrows move focus and Select starts
  /// editing (and opens the on-screen keyboard).
  KeyEventResult _tvKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final vertical =
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    // Up and Down always leave a one-line field (they reach us only when the
    // on-screen keyboard is closed); Left and Right move the caret while editing.
    if (!_readOnly && !vertical) return KeyEventResult.ignored;
    if (!_readOnly) setState(() => _editing = false);
    final k = event.logicalKey;
    final direction = switch (k) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction != null) {
      node.focusInDirection(direction);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
      if (event is KeyDownEvent) setState(() => _editing = true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _modeChanged(FocusHighlightMode _) => _focusChanged();

  /// A focus ring on the whole row while the person is moving with keys or a
  /// D-pad (the caret alone is invisible across a living room).
  void _focusChanged() {
    if (!_node.hasFocus && _editing && mounted) {
      setState(() => _editing = false);
    }
    final ring =
        _node.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (ring != _ring && mounted) setState(() => _ring = ring);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: _ring
            ? Border.all(color: t.accent, width: PlatformUtils.isTv ? 3 : 2)
            : null,
      ),
      child: _row(t),
    );
  }

  Widget _row(AppThemeTokens t) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.lg, right: Space.xs),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              _IconSquare(icon: widget.icon!),
              const SizedBox(width: Space.md + 2),
            ],
            SizedBox(width: 104, child: Text(widget.title, style: t.body)),
            Expanded(
              child: CupertinoTextField(
                controller: widget.controller,
                focusNode: _node,
                readOnly: _readOnly,
                showCursor: true,
                onTap: PlatformUtils.isTv
                    ? () => setState(() => _editing = true)
                    : null,
                textInputAction: widget.textInputAction,
                onSubmitted: (v) {
                  if (_editing) setState(() => _editing = false);
                  widget.onSubmitted?.call(v);
                },
                autofocus: widget.autofocus,
                autofillHints: widget.autofillHints,
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
                minimumSize: const Size(44, 44),
                onPressed: () => setState(() => _hidden = !_hidden),
                child: NaviIcon(
                  _hidden ? NaviGlyph.eye : NaviGlyph.eyeOff,
                  size: 20,
                  color: t.textSecondary,
                  semanticLabel: _hidden ? 'Show password' : 'Hide password',
                ),
              )
            else if (widget.voice)
              VoiceSearchButton(controller: widget.controller)
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
      child: NaviFocusRing(
        radius: Radii.control,
        onTap: widget.onTap,
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
      ),
    );
  }
}
