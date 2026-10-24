import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/ui/action_sheet.dart' show showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/large_title_page.dart';
import '../logic/update_providers.dart';
import '../logic/update_service.dart';

/// "1.4 MB", "3.2 MB": sizes the way the update banner quotes them.
String formatUpdateSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The size to quote for a check: the patch if one applies, else the full file.
int? updateDownloadSize(UpdateCheck c) => c.plan?.downloadSize ?? c.manifest.windowsSetup?.size;

/// Settings > About > Updates: where releases come from, the newest build with
/// its notes, and the download/install controls.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  late final _source = TextEditingController(text: ref.read(updateSettingsProvider).source);
  late final _token = TextEditingController(text: ref.read(updateSettingsProvider).token);

  @override
  void dispose() {
    _source.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = ref.read(updateSettingsProvider.notifier);
    await n.setSource(_source.text);
    await n.setToken(_token.text);
    if (!mounted) return;
    final s = ref.read(updateSettingsProvider);
    showToast(context, s.enabled ? 'Saved. Checking for updates…' : (s.source.isEmpty ? 'Updates are off' : 'That address isn’t valid'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final settings = ref.watch(updateSettingsProvider);
    final check = ref.watch(updateCheckProvider);
    final run = ref.watch(updateRunProvider);

    final Widget status = !updatesSupported
        ? _note(t, 'Updates inside the app are available on Android and Windows.')
        : !settings.enabled
            ? _note(t, 'Add the address of your releases below to turn updates on.')
            : check.when(
                loading: () => _note(t, 'Checking…'),
                error: (e, _) => _note(t, e is UpdateException ? e.message : 'Couldn’t check for updates.'),
                data: (c) => c == null ? _note(t, 'Updates are off.') : _result(t, c, run),
              );

    return LargeTitlePage(
      title: 'Updates',
      clearPlayer: false,
      slivers: [
        SliverToBoxAdapter(child: status),
        SliverToBoxAdapter(
          child: Column(children: [
            GroupedSection(
              header: 'Update source',
              footer: 'A GitHub repository (github:owner/repo) or the address of a latest.json file. '
                  'For a private repository, paste a read-only access token.',
              children: [
                GroupedTextFieldRow(
                  title: 'Address',
                  controller: _source,
                  placeholder: 'github:owner/repo',
                  keyboardType: TextInputType.url,
                  icon: NaviGlyph.globe,
                ),
                GroupedTextFieldRow(
                  title: 'Token',
                  controller: _token,
                  placeholder: 'Optional',
                  obscure: true,
                  icon: NaviGlyph.lock,
                ),
                GroupedRow(title: 'Save and Check', icon: NaviGlyph.repeat, onTap: _save),
              ],
            ),
            GroupedSection(
              footer: 'Patches are small, but a full download can be 25 MB.',
              children: [
                GroupedSwitchRow(
                  title: 'Download on Wi-Fi only',
                  icon: NaviGlyph.wifi,
                  value: settings.wifiOnly,
                  onChanged: ref.read(updateSettingsProvider.notifier).setWifiOnly,
                ),
              ],
            ),
          ]),
        ),
      ],
    );
  }

  Widget _note(AppThemeTokens t, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
        child: Text(text, style: t.subheadline),
      );

  Widget _result(AppThemeTokens t, UpdateCheck c, UpdateRun run) {
    final m = c.manifest;
    if (!c.available) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('You’re up to date', style: t.title3),
          const SizedBox(height: Space.xs),
          Text('Newest build is ${m.version} (${m.build}).', style: t.subheadline),
          const SizedBox(height: Space.md),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            onPressed: () => ref.invalidate(updateCheckProvider),
            child: Text('Check Again', style: TextStyle(color: t.accent)),
          ),
        ]),
      );
    }
    final size = updateDownloadSize(c);
    final delta = c.plan?.isDelta ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NaviVibe ${m.version} is ready', style: t.title3),
        const SizedBox(height: Space.xs),
        Text(
          [
            'Build ${m.build}',
            if (size != null) '${formatUpdateSize(size)}${delta ? ' (changes only)' : ''}',
          ].join(' · '),
          style: t.subheadline,
        ),
        if (m.notes.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Text('What’s new', style: t.headline),
          const SizedBox(height: Space.xs),
          Text(m.notes, style: t.body),
        ],
        const SizedBox(height: Space.lg),
        if (run.busy) ...[
          _Bar(fraction: run.fraction, color: t.accent, track: t.bgSurface),
          const SizedBox(height: Space.xs),
          Text(run.stage, style: t.footnote),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            onPressed: ref.read(updateRunProvider.notifier).cancel,
            child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
          ),
        ] else ...[
          if (run.error != null) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text(run.error!, style: t.footnote.copyWith(color: t.danger))),
          if (run.installReady) Padding(padding: const EdgeInsets.only(bottom: Space.sm), child: Text(run.stage, style: t.footnote)),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: t.accent,
              onPressed: () => run.installReady
                  ? ref.read(updateRunProvider.notifier).install()
                  : ref.read(updateRunProvider.notifier).start(c),
              child: Text(
                run.installReady ? 'Install' : (run.error != null ? 'Try Again' : 'Download and Install'),
                style: TextStyle(color: t.bgBase),
              ),
            ),
          ),
          if (run.needsWifi)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => ref.read(updateRunProvider.notifier).start(c, ignoreWifiRule: true),
              child: Text('Use Mobile Data Anyway', style: TextStyle(color: t.accent)),
            ),
        ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color track;
  const _Bar({required this.fraction, required this.color, required this.track});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: ColoredBox(color: color)),
          ]),
        ),
      );
}
