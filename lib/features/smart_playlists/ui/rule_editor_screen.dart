import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/catalog.dart';
import '../../../providers/catalog_provider.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../data/smart_evaluator.dart';
import '../data/smart_rules.dart';
import '../logic/smart_playlist_providers.dart';

/// Opens the rule editor as a full-screen sheet. With no [playlist] it
/// creates one. Returns the saved playlist, or null when cancelled.
Future<SmartPlaylist?> showSmartPlaylistEditor(BuildContext context, {SmartPlaylist? playlist}) =>
    Navigator.of(context, rootNavigator: true).push<SmartPlaylist>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => SmartPlaylistEditor(playlist: playlist)),
    );

/// New / Edit Smart Playlist: a title, the rules (AND / OR groups, one level
/// of nesting), a sort and a limit, with a live count of matching songs.
class SmartPlaylistEditor extends ConsumerStatefulWidget {
  final SmartPlaylist? playlist;
  const SmartPlaylistEditor({super.key, this.playlist});

  @override
  ConsumerState<SmartPlaylistEditor> createState() => _SmartPlaylistEditorState();
}

class _SmartPlaylistEditorState extends ConsumerState<SmartPlaylistEditor> {
  late final _title = TextEditingController(text: widget.playlist?.name ?? '');
  late final _limitText = TextEditingController(text: '${widget.playlist?.limit ?? 50}');
  late SmartGroup _rules = widget.playlist?.rules ?? SmartGroup(children: [SmartRule.blank(SmartField.language)]);
  late SmartSort _sort = widget.playlist?.sort ?? SmartSort.title;
  late bool _asc = widget.playlist?.ascending ?? true;
  late bool _limitOn = widget.playlist?.limit != null;

  bool get _creating => widget.playlist == null;

  int? get _limit {
    if (!_limitOn) return null;
    final n = int.tryParse(_limitText.text.trim());
    return n != null && n > 0 ? n : null;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _limitText.dispose();
    super.dispose();
  }

  SmartPlaylist _draft() {
    final base = widget.playlist ??
        SmartPlaylist(id: ref.read(smartPlaylistsProvider.notifier).newId(), name: '', createdAt: DateTime.now().millisecondsSinceEpoch);
    return base.copyWith(name: _title.text.trim(), rules: _rules, sort: _sort, ascending: _asc, limit: _limit);
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final saved = _draft();
    ref.read(smartPlaylistsProvider.notifier).upsert(saved);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final canSave = _title.text.trim().isNotEmpty;
    final facts = ref.watch(smartFactsProvider);

    return Scaffold(
      backgroundColor: t.bgSurface,
      appBar: AppBar(
        backgroundColor: t.bgSurface,
        automaticallyImplyLeading: false,
        leadingWidth: 96,
        leading: CupertinoButton(
          padding: const EdgeInsets.only(left: Space.lg),
          onPressed: () => Navigator.of(context).pop(),
          child: Align(alignment: Alignment.centerLeft, child: Text('Cancel', style: t.body.copyWith(color: t.accent))),
        ),
        title: Text(_creating ? 'New Smart Playlist' : 'Edit Smart Playlist', style: t.headline),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            onPressed: canSave ? _save : null,
            child: Text(_creating ? 'Create' : 'Done', style: t.headline.copyWith(color: canSave ? t.accent : t.textMuted)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.huge * 2),
        children: [
          CupertinoTextField(
            controller: _title,
            autofocus: _creating,
            placeholder: 'Playlist Title',
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            style: t.title2,
            placeholderStyle: t.title2.copyWith(color: t.textMuted),
            cursorColor: t.accent,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
            padding: const EdgeInsets.symmetric(vertical: Space.md),
          ),
          const SizedBox(height: Space.lg),
          _MatchCount(
            state: facts.whenData((f) => SmartEvaluator.evaluate(_draft(), f, now: DateTime.now()).length),
            onRetry: () => ref.invalidate(smartFactsProvider),
          ),
          const _SectionLabel('Rules'),
          _GroupEditor(group: _rules, depth: 0, onChanged: (g) => setState(() => _rules = g)),
          const _SectionLabel('Sort and limit'),
          _Line(
            label: 'Sort by',
            child: _Pill(
              label: _sort.label,
              onTap: () async {
                final v = await showChoiceSheet<SmartSort>(
                  context,
                  title: 'Sort by',
                  options: SmartSort.values,
                  selected: _sort,
                  label: (s) => s.label,
                );
                if (v != null) setState(() => _sort = v);
              },
            ),
          ),
          if (_sort != SmartSort.random)
            _Line(
              label: 'Highest first',
              child: CupertinoSwitch(
                value: !_asc,
                activeTrackColor: t.accent,
                onChanged: (v) => setState(() => _asc = !v),
              ),
            ),
          _Line(
            label: 'Limit',
            child: CupertinoSwitch(
              value: _limitOn,
              activeTrackColor: t.accent,
              onChanged: (v) => setState(() => _limitOn = v),
            ),
          ),
          if (_limitOn)
            _Line(
              label: 'Songs',
              child: SizedBox(
                width: 96,
                child: _NumberField(controller: _limitText, onChanged: () => setState(() {}), hint: '50'),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Live count ──────────────────────────────────────────────────────────────

class _MatchCount extends StatelessWidget {
  final AsyncValue<int> state;
  final VoidCallback onRetry;
  const _MatchCount({required this.state, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Column(
      children: [
        state.when(
          loading: () => Text('Counting…', style: t.title1.copyWith(color: t.textMuted)),
          error: (_, _) => CupertinoButton(
            onPressed: onRetry,
            child: Text('Couldn’t read your library. Tap to retry.', style: t.body.copyWith(color: t.accent)),
          ),
          data: (n) => Text(songCount(n), style: t.title1),
        ),
        const SizedBox(height: 2),
        Text('match these rules. Updates as you edit.', style: t.footnote),
      ],
    );
  }
}

// ── Rules ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.sm),
        child: Text(text.toUpperCase(), style: ThemeTokens.of(context).footnote),
      );
}

/// A labelled row with the control on the right, hairline below.
class _Line extends StatelessWidget {
  final String label;
  final Widget child;
  const _Line({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
      child: Row(children: [Expanded(child: Text(label, style: t.body)), child]),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  final SmartGroup group;
  final int depth;
  final ValueChanged<SmartGroup> onChanged;
  final VoidCallback? onRemove;

  const _GroupEditor({super.key, required this.group, required this.depth, required this.onChanged, this.onRemove});

  /// One level of nesting is enough for "(A or B) and C" and keeps the
  /// editor readable on a phone.
  static const maxDepth = 1;

  void _set(int i, SmartNode? node) {
    final next = [...group.children];
    node == null ? next.removeAt(i) : next[i] = node;
    onChanged(group.copyWith(children: next));
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Match', style: t.body),
            const SizedBox(width: Space.md),
            CupertinoSlidingSegmentedControl<bool>(
              groupValue: group.matchAll,
              thumbColor: t.bgElevated,
              backgroundColor: t.fill,
              children: {
                true: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md), child: Text('All', style: t.subheadline.copyWith(color: t.textPrimary))),
                false: Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md), child: Text('Any', style: t.subheadline.copyWith(color: t.textPrimary))),
              },
              onValueChanged: (v) => onChanged(group.copyWith(matchAll: v ?? true)),
            ),
            const SizedBox(width: Space.md),
            Expanded(child: Text('of these', style: t.body)),
            if (onRemove != null) _IconButton(glyph: NaviGlyph.trash, label: 'Remove group', onTap: onRemove!),
          ],
        ),
        const SizedBox(height: Space.sm),
        for (var i = 0; i < group.children.length; i++)
          switch (group.children[i]) {
            final SmartRule r => _RuleRow(
                key: ValueKey('rule_${depth}_$i'),
                rule: r,
                onChanged: (v) => _set(i, v),
                onRemove: () => _set(i, null),
              ),
            final SmartGroup g => Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: _GroupEditor(
                  key: ValueKey('group_${depth}_$i'),
                  group: g,
                  depth: depth + 1,
                  onChanged: (v) => _set(i, v),
                  onRemove: () => _set(i, null),
                ),
              ),
          },
        _AddRow(
          label: 'Add Rule',
          onTap: () => onChanged(group.copyWith(children: [...group.children, SmartRule.blank(SmartField.language)])),
        ),
        if (depth < maxDepth)
          _AddRow(
            label: 'Add Group',
            onTap: () => onChanged(group.copyWith(children: [
              ...group.children,
              SmartGroup(matchAll: !group.matchAll, children: [SmartRule.blank(SmartField.language)]),
            ])),
          ),
      ],
    );
    if (depth == 0) return body;
    return Container(
      padding: const EdgeInsets.only(left: Space.md),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: t.textMuted, width: 1.5))),
      child: body,
    );
  }
}

class _AddRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.99,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            NaviIcon(NaviGlyph.plus, size: 20, color: t.accent),
            const SizedBox(width: Space.md),
            Text(label, style: t.body.copyWith(color: t.accent)),
          ],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback onTap;
  const _IconButton({required this.glyph, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => CupertinoClickable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: 44,
          child: Center(child: NaviIcon(glyph, size: 20, color: ThemeTokens.of(context).textSecondary)),
        ),
      );
}

/// Tappable value that opens a picker: a capsule with a small chevron.
class _Pill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.97,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body)),
            const SizedBox(width: Space.xs),
            Transform.rotate(angle: 1.5708, child: NaviIcon(NaviGlyph.chevron, size: 14, color: t.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String hint;
  final bool decimal;
  const _NumberField({required this.controller, required this.onChanged, this.hint = '0', this.decimal = false});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoTextField(
      controller: controller,
      placeholder: hint,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))],
      textAlign: TextAlign.center,
      style: t.body,
      placeholderStyle: t.body.copyWith(color: t.textMuted),
      cursorColor: t.accent,
      decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
      padding: const EdgeInsets.symmetric(vertical: Space.sm + 2, horizontal: Space.md),
      onChanged: (_) => onChanged(),
    );
  }
}

class _RuleRow extends ConsumerStatefulWidget {
  final SmartRule rule;
  final ValueChanged<SmartRule> onChanged;
  final VoidCallback onRemove;
  const _RuleRow({super.key, required this.rule, required this.onChanged, required this.onRemove});

  @override
  ConsumerState<_RuleRow> createState() => _RuleRowState();
}

class _RuleRowState extends ConsumerState<_RuleRow> {
  late final _value = TextEditingController(text: widget.rule.value);
  late final _window = TextEditingController(text: '${widget.rule.window}');

  SmartRule get _rule => widget.rule;

  @override
  void didUpdateWidget(_RuleRow old) {
    super.didUpdateWidget(old);
    // The field or operator changed from outside the text box (a picker).
    if (_value.text != _rule.value) _value.text = _rule.value;
  }

  @override
  void dispose() {
    _value.dispose();
    _window.dispose();
    super.dispose();
  }

  Future<void> _pickField() async {
    final f = await showChoiceSheet<SmartField>(
      context,
      title: 'Rule',
      options: SmartField.values,
      selected: _rule.field,
      label: (f) => f.label,
    );
    if (f == null || f == _rule.field) return;
    // A different field starts from a clean rule: its operators and values
    // differ, and a stale "Tamil" makes no sense against a year.
    widget.onChanged(SmartRule.blank(f).copyWith(window: _rule.window));
  }

  Future<void> _pickOp() async {
    final op = await showChoiceSheet<SmartOp>(
      context,
      title: _rule.field.label,
      options: _rule.field.ops,
      selected: _rule.op,
      label: (o) => o.label,
    );
    if (op != null) widget.onChanged(_rule.copyWith(op: op));
  }

  Future<void> _pickChoice() async {
    final isLanguage = _rule.field == SmartField.language;
    final doc = ref.read(catalogProvider).asData?.value;
    final names = isLanguage
        ? {
            if (doc != null) for (final c in doc.languages) c.key: c.name,
            for (final e in languageNames.entries) e.key: e.value,
          }
        : {for (final m in moodLabels) m: '${m[0].toUpperCase()}${m.substring(1)}'};
    final key = await showChoiceSheet<String>(
      context,
      title: _rule.field.label,
      options: names.keys.toList(),
      selected: _rule.value,
      label: (k) => names[k] ?? k,
    );
    if (key != null) widget.onChanged(_rule.copyWith(value: key));
  }

  String get _choiceLabel {
    if (_rule.value.isEmpty) return 'Choose…';
    if (_rule.field == SmartField.language) return languageNames[_rule.value] ?? _rule.value.toUpperCase();
    return '${_rule.value[0].toUpperCase()}${_rule.value.substring(1)}';
  }

  Widget _valueEditor() {
    final t = ThemeTokens.of(context);
    final field = _rule.field;
    switch (field.kind) {
      case SmartFieldKind.flag:
        return _Pill(
          label: _rule.value == 'false' ? 'Not starred' : 'Starred',
          onTap: () => widget.onChanged(_rule.copyWith(value: _rule.value == 'false' ? 'true' : 'false')),
        );
      case SmartFieldKind.text when field.isChoice:
        return _Pill(label: _choiceLabel, onTap: _pickChoice);
      case SmartFieldKind.text:
        return CupertinoTextField(
          controller: _value,
          placeholder: field.label,
          style: t.body,
          placeholderStyle: t.body.copyWith(color: t.textMuted),
          cursorColor: t.accent,
          decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
          padding: const EdgeInsets.symmetric(vertical: Space.sm + 2, horizontal: Space.md),
          onChanged: (v) => widget.onChanged(_rule.copyWith(value: v)),
        );
      case SmartFieldKind.days:
        return Row(
          children: [
            SizedBox(
              width: 80,
              child: _NumberField(controller: _value, hint: '30', onChanged: () => widget.onChanged(_rule.copyWith(value: _value.text))),
            ),
            const SizedBox(width: Space.sm),
            Text('days', style: t.body),
          ],
        );
      case SmartFieldKind.number:
        final recent = field == SmartField.recentPlays;
        return Row(
          children: [
            SizedBox(
              width: 80,
              child: _NumberField(
                controller: _value,
                decimal: field == SmartField.length,
                onChanged: () => widget.onChanged(_rule.copyWith(value: _value.text)),
              ),
            ),
            if (recent) ...[
              const SizedBox(width: Space.sm),
              Text('in', style: t.body),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: 64,
                child: _NumberField(
                  controller: _window,
                  hint: '30',
                  onChanged: () => widget.onChanged(_rule.copyWith(window: int.tryParse(_window.text) ?? 30)),
                ),
              ),
              const SizedBox(width: Space.sm),
              Text('days', style: t.body),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline, width: 0.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    _Pill(label: _rule.field.label, onTap: _pickField),
                    if (_rule.field.kind != SmartFieldKind.flag) _Pill(label: _rule.op.label, onTap: _pickOp),
                  ],
                ),
                const SizedBox(height: Space.sm),
                _valueEditor(),
              ],
            ),
          ),
          _IconButton(glyph: NaviGlyph.minus, label: 'Remove rule', onTap: widget.onRemove),
        ],
      ),
    );
  }
}
