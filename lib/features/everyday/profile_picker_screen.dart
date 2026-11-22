import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../../providers/settings_provider.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/art/navi_icons.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/ui/large_title_page.dart';
import '../pairing/ui/tv_pair_screen.dart';
import 'dont_count.dart';
import 'profiles.dart';
import 'profiles_providers.dart';

/// "Who's listening?": one big tile per person who has signed in on this
/// device. One tap switches (R3). Built for a remote: every tile takes focus.
class ProfilePickerScreen extends ConsumerWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(settingsProvider);
    final profiles = ref.watch(profilesProvider).forServer(s.serverUrl);
    final currentKey = Profile.keyOf(s.serverUrl, s.username);
    final dontCount = ref.watch(dontCountProvider);

    Future<void> pick(Profile p) async {
      await switchToProfile(ref, p);
      if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }

    return LargeTitlePage(
      title: 'Who’s Listening?',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: Space.lg,
              runSpacing: Space.lg,
              children: [
                for (final (i, p) in profiles.indexed)
                  _ProfileTile(
                    key: ValueKey('profile_${p.key}'),
                    profile: p,
                    current: p.key == currentKey,
                    autofocus: i == 0,
                    onTap: () => pick(p),
                    onMenu: () => _menu(context, ref, p),
                  ),
                _AddTile(
                  onTap: () async {
                    // A TV has no keyboard: a phone sends the login with a code.
                    if (PlatformUtils.isTv) {
                      navigateInApp(context, const TvPairScreen(), title: 'Add someone');
                      return;
                    }
                    final login = await showDialog<(String, String)>(
                      context: context,
                      builder: (_) => const _AddDialog(),
                    );
                    if (login != null) {
                      ref.read(profilesProvider.notifier).remember(s.serverUrl, login.$1, login.$2);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
            child: Text(
              'Anyone who signs in here is remembered, so switching later takes one tap. '
              'To add someone, sign them in from their phone with a code.',
              style: t.footnote,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SwitchListTile(
            key: const ValueKey('dont_count_switch'),
            title: Text('Don’t count this listening', style: t.body),
            subtitle: Text(
              'For guests, kids and parties. Music plays, but nothing is added to your history, '
              'Replay or taste. Turns off when the app restarts.',
              style: t.footnote,
            ),
            value: dontCount,
            onChanged: ref.read(dontCountProvider.notifier).set,
          ),
        ),
      ],
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Profile p) {
    final page = Navigator.of(context).context;
    return showPlatformSheet(
      context: context,
      menu: true,
      builder: (_) => SheetGroup(children: [
        SheetAction(
          label: 'Rename…',
          icon: NaviGlyph.edit,
          onTap: () async {
            final name = await showDialog<String>(context: page, builder: (_) => _RenameDialog(initial: p.displayName));
            if (name != null) ref.read(profilesProvider.notifier).rename(p, name);
          },
        ),
        SheetAction(
          label: 'Forget on this device',
          icon: NaviGlyph.trash,
          destructive: true,
          onTap: () => ref.read(profilesProvider.notifier).forget(p),
        ),
      ]),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    super.key,
    required this.profile,
    required this.current,
    required this.autofocus,
    required this.onTap,
    required this.onMenu,
  });

  final Profile profile;
  final bool current;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      selected: current,
      label: '${profile.displayName}${current ? ', listening now' : ''}',
      child: NaviFocusRing(
        autofocus: autofocus,
        radius: 56,
        onTap: onTap,
        onLongPress: onMenu,
        child: SizedBox(
          width: 112,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.bgSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: current ? t.accent : t.outline, width: current ? 2 : 1),
                ),
                child: Text(profile.initial, style: t.title1),
              ),
              const SizedBox(height: Space.sm),
              Text(profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
              Text(current ? 'Listening now' : ' ', style: t.footnote),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Add someone',
      child: NaviFocusRing(
        radius: 56,
        onTap: onTap,
        child: SizedBox(
          width: 112,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.outline)),
                child: NaviIcon(NaviGlyph.plus, size: 32, color: t.textSecondary),
              ),
              const SizedBox(height: Space.sm),
              Text('Add', style: t.body.copyWith(color: t.textSecondary)),
              Text(' ', style: t.footnote),
            ],
          ),
        ),
      ),
    );
  }
}

/// Username and password of someone on this server, kept on this device only.
class _AddDialog extends StatefulWidget {
  const _AddDialog();

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Someone', textAlign: TextAlign.center),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: _user, autofocus: true, decoration: const InputDecoration(labelText: 'Username')),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(
        onPressed: () => Navigator.pop(context, (_user.text.trim(), _pass.text)),
        child: const Text('Add'),
      ),
    ],
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name', textAlign: TextAlign.center),
    content: TextField(controller: _c, autofocus: true, maxLength: 24, onSubmitted: (v) => Navigator.pop(context, v)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}
