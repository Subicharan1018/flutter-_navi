import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../../../widgets/ui/states.dart';
import '../../listen/data/listen_api.dart';
import '../logic/flow_prefs_provider.dart';

/// Tells the listener a change didn't save; the setting snaps back by itself.
void _failed(BuildContext context, Object e) =>
    showToast(context, e is ListenException ? e.message : 'Couldn’t save that. Try again.');

/// Settings > Flow languages: which languages Flow and the weekly mix draw from,
/// and whether NaviVibe may try new ones. Both save at once and are kept on the
/// server, so the same choice applies on every device.
class FlowSettingsSection extends ConsumerWidget {
  const FlowSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(flowPrefsProvider).asData?.value;
    final loaded = prefs != null;
    return GroupedSection(
      header: 'Flow languages',
      footer: !loaded || prefs.explore
          ? 'Flow and your weekly mix stay in these languages, with an occasional song from a new one.'
          : 'Flow and your weekly mix stay in these languages.',
      children: [
        GroupedRow(
          title: 'Languages',
          subtitle: 'What Flow and your weekly mix play',
          value: loaded ? prefs.summary : null,
          onTap: () => navigateInApp(context, const FlowLanguagesScreen()),
        ),
        GroupedSwitchRow(
          title: 'Try new languages',
          subtitle: 'One new-language song now and then',
          value: !loaded || prefs.explore,
          onChanged: loaded
              ? (v) async {
                  try {
                    await ref.read(flowPrefsProvider.notifier).setExplore(v);
                  } catch (e) {
                    if (context.mounted) _failed(context, e);
                  }
                }
              : (_) {},
        ),
      ],
    );
  }
}

/// Settings > Flow & Mixes > Languages: "Any (learn from me)", or a multi-select
/// of the languages in the library with their song counts.
class FlowLanguagesScreen extends ConsumerWidget {
  const FlowLanguagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(flowPrefsProvider);
    final prefs = async.asData?.value;

    Future<void> save(List<String> codes) async {
      try {
        await ref.read(flowPrefsProvider.notifier).setLanguages(codes);
      } catch (e) {
        if (context.mounted) _failed(context, e);
      }
    }

    return LargeTitlePage(
      title: 'Languages',
      clearPlayer: false,
      onRefresh: () => ref.refresh(flowPrefsProvider.future),
      slivers: [
        if (prefs != null && prefs.available.isNotEmpty)
          SliverList.list(children: [
            const SizedBox(height: Space.sm),
            GroupedSection(
              footer: 'Any lets NaviVibe learn your languages from what you play.',
              children: [
                _ChoiceRow(title: 'Any (learn from me)', selected: prefs.isAny, onTap: () => save(const [])),
              ],
            ),
            GroupedSection(
              header: 'Or pick languages',
              footer: prefs.explore
                  ? 'Flow and your weekly mix stay in these, with an occasional song from a new language.'
                  : 'Flow and your weekly mix stay in these.',
              children: [
                for (final l in prefs.available)
                  _ChoiceRow(
                    title: l.name,
                    subtitle: '${_count(l.songs)} ${l.songs == 1 ? 'song' : 'songs'}',
                    selected: prefs.languages.contains(l.code),
                    onTap: () => save(_toggle(prefs.languages, l.code)),
                  ),
              ],
            ),
          ])
        else
          SliverToBoxAdapter(
            child: async.when(
              loading: () => const LoadingState(),
              error: (e, _) => MessageState.error(
                title: 'Your languages didn’t load',
                onRetry: () => ref.invalidate(flowPrefsProvider),
              ),
              data: (_) => const MessageState(
                art: EmptyArtKind.noResults,
                title: 'No languages yet',
                message: 'Languages show up here once the server has read your library.',
              ),
            ),
          ),
      ],
    );
  }

  /// [codes] with [code] added, or taken out when it is there.
  static List<String> _toggle(List<String> codes, String code) =>
      codes.contains(code) ? [for (final c in codes) if (c != code) c] : [...codes, code];

  /// 1690 → "1,690".
  static String _count(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// One option: a row with a check on the right when it is chosen. Focusable with
/// the D-pad, and read out as selected.
class _ChoiceRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceRow({required this.title, this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      selected: selected,
      child: GroupedRow(
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: SizedBox.square(
          dimension: 22,
          child: selected ? NaviIcon(NaviGlyph.check, size: 20, color: t.accent) : null,
        ),
      ),
    );
  }
}
