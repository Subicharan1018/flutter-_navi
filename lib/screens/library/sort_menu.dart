import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../widgets/art/navi_icons.dart';
import '../../models/library_sort.dart';
import '../../providers/library_provider.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';

const _labels = <LibrarySortField, String>{
  LibrarySortField.name: 'Title',
  LibrarySortField.artistName: 'Artist',
  LibrarySortField.recentlyAdded: 'Recently Added',
  LibrarySortField.playCount: 'Most Played',
  LibrarySortField.duration: 'Length',
};

/// Nav-bar "Sort" button for a library section; opens the sort options with
/// a check on the current one. Picking it again flips the direction.
class SortButton extends ConsumerWidget {
  final LibraryFilter section;
  final List<LibrarySortField> fields;
  const SortButton({super.key, required this.section, required this.fields});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => showPlatformSheet(context: context, builder: (_) => _SortSheet(section: section, fields: fields)),
      child: Text('Sort', style: t.body.copyWith(color: t.accent)),
    );
  }
}

class _SortSheet extends ConsumerWidget {
  final LibraryFilter section;
  final List<LibrarySortField> fields;
  const _SortSheet({required this.section, required this.fields});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final pref = ref.watch(librarySortProvider)[section] ?? const LibrarySortPreference();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Text('Sort By', style: t.headline),
        ),
        SheetGroup(children: [
          for (final f in fields)
            SheetAction(
              label: _labels[f] ?? f.name,
              detail: pref.field == f
                  ? (pref.direction == LibrarySortDirection.asc ? 'Ascending' : 'Descending')
                  : null,
              trailing: pref.field == f ? NaviIcon(NaviGlyph.check, size: 18, color: t.accent) : null,
              onTap: () => ref.read(librarySortProvider.notifier).setSort(section, f),
            ),
        ]),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}
