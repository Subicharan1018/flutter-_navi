import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/media.dart' show TintedButton;
import '../data/mood_labels.dart';
import '../logic/flow_mood_actions.dart';
import '../logic/mood_overrides_provider.dart';

/// The mood selector (the web mood editor has the same one).
///
/// An admin taps up to [maxSongMoods] moods, in order (the first is the
/// song's main mood), and saves them for everyone. Anyone else sees the song's
/// moods and taps one to say it isn't that mood for them; they can't add moods.
/// [onSave] gets the moods the song should have.
class MoodPicker extends StatefulWidget {
  final String title;
  final List<String> labels;      // the song's moods (server labels)
  final Set<String> notMine;      // the listener's "Not this mood" marks
  final bool admin;
  final ValueChanged<List<String>> onSave;

  const MoodPicker({
    super.key,
    required this.title,
    required this.labels,
    required this.admin,
    required this.onSave,
    this.notMine = const {},
  });

  @override
  State<MoodPicker> createState() => _MoodPickerState();
}

class _MoodPickerState extends State<MoodPicker> {
  late List<String> _picked;
  String? _note;

  @override
  void initState() {
    super.initState();
    _picked = widget.admin
        ? [...widget.labels.take(maxSongMoods)]
        : [for (final m in widget.labels) if (!widget.notMine.contains(m)) m];
  }

  void _tap(String mood) {
    setState(() {
      _note = null;
      if (_picked.contains(mood)) {
        _picked.remove(mood);
      } else if (widget.admin && _picked.length >= maxSongMoods) {
        _note = 'Pick at most $maxSongMoods moods. Tap one to remove it first.';
      } else {
        _picked.add(mood);
      }
    });
  }

  bool get _changed {
    final before = widget.admin
        ? widget.labels.take(maxSongMoods).toList()
        : [for (final m in widget.labels) if (!widget.notMine.contains(m)) m];
    if (before.length != _picked.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (widget.admin ? before[i] != _picked[i] : !_picked.contains(before[i])) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final options = widget.admin ? pickableMoods : widget.labels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.title3),
          const SizedBox(height: Space.xs),
          Text(
            widget.admin
                ? 'Tap up to $maxSongMoods moods, most fitting first. Saved for everyone.'
                : options.isEmpty
                    ? 'This song has no mood yet. Only an admin can add one.'
                    : 'Tap a mood this song isn’t for you. Only an admin can add moods.',
            style: t.footnote,
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in options)
                _PickChip(
                  key: ValueKey('mood-$m'),
                  label: moodTitle(m),
                  order: widget.admin && _picked.contains(m) ? _picked.indexOf(m) + 1 : null,
                  selected: _picked.contains(m),
                  struck: !widget.admin && !_picked.contains(m),
                  onTap: () => _tap(m),
                ),
            ],
          ),
          if (_note != null) ...[
            const SizedBox(height: Space.sm),
            Text(_note!, style: t.footnote.copyWith(color: t.danger)),
          ],
          const SizedBox(height: Space.xl),
          SizedBox(
            width: double.infinity,
            child: TintedButton(
              label: widget.admin ? 'Save for Everyone' : 'Save',
              filled: true,
              height: 50,
              onTap: _changed ? () => widget.onSave(List.unmodifiable(_picked)) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool struck;
  final int? order;
  final VoidCallback onTap;

  const _PickChip({super.key, required this.label, required this.selected, required this.onTap, this.struck = false, this.order});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = selected ? t.onAccent : (struck ? t.textMuted : t.textPrimary);
    return Semantics(
      selected: selected,
      button: true,
      label: order == null ? label : '$label, ${order == 1 ? 'first' : 'second'}',
      excludeSemantics: true,
      child: CupertinoClickable(
        semanticLabel: label,
        onTap: onTap,
        focusRadius: 22,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(color: selected ? t.accentFill : t.fill, borderRadius: BorderRadius.circular(22)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order != null) ...[
                Text('$order', style: t.footnote.copyWith(color: fg, fontWeight: FontWeight.w700)),
                const SizedBox(width: Space.xs),
              ],
              Text(
                label,
                maxLines: 1,
                style: t.subheadline.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  decoration: struck ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the mood selector for [song] and applies what was picked (an admin:
/// for everyone; anyone else: for themself). [context] is the page under the
/// sheet.
Future<void> showSongMoodPicker(BuildContext context, Song song) async {
  final c = ProviderScope.containerOf(context);
  final admin = await c.read(moodAdminProvider.future).catchError((_) => false);
  if (!context.mounted) return;
  final labels = c.read(songMoodEditsProvider)[song.id] ?? c.read(catalogSongProvider(song.id))?.moods ?? const <String>[];
  final notMine = c.read(moodOverridesProvider)[song.id] ?? const <String>{};
  List<String>? picked;
  await showPlatformSheet<void>(
    context: context,
    title: 'Change Mood',
    builder: (sheet) => MoodPicker(
      title: song.title,
      labels: labels,
      notMine: notMine,
      admin: admin,
      onSave: (moods) {
        picked = moods;
        Navigator.of(sheet).pop();
      },
    ),
  );
  final moods = picked;
  if (moods == null) return;
  final ok = await c.read(flowMoodActionsProvider).setMoods(song, moods: moods, labels: labels, admin: admin);
  if (!context.mounted) return;
  showToast(
    context,
    !ok
        ? 'Couldn’t save the moods. Check your connection and try again.'
        : admin
            ? 'Moods saved for everyone'
            : 'Saved for you',
  );
}
