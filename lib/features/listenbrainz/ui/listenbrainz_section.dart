import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/web_session.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup, showToast;
import '../../../widgets/ui/grouped_list.dart';
import '../../playlist_cover/playlist_image_providers.dart' show navidromeJwtProvider;
import '../listenbrainz_link.dart';

/// The server-side link for this account, built from the saved sign-in.
final listenBrainzLinkProvider = Provider.autoDispose<ListenBrainzLink>((ref) => ListenBrainzLink(
      base: WebSession.navidromeBase(ref.watch(settingsProvider).serverUrl),
      jwt: ref.watch(navidromeJwtProvider),
    ));

final listenBrainzStatusProvider =
    FutureProvider.autoDispose<ListenBrainzStatus>((ref) => ref.watch(listenBrainzLinkProvider).status());

/// Settings › Scrobbling. Plays already reach Navidrome; with a ListenBrainz
/// token on the account Navidrome forwards each one to the person's own profile.
class ListenBrainzSection extends ConsumerWidget {
  const ListenBrainzSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(listenBrainzStatusProvider);
    final value = status.when(
      data: (s) => s.linked ? (s.user == null ? 'Linked' : 'Linked as ${s.user}') : 'Not linked',
      loading: () => 'Checking…',
      error: (_, _) => 'Unavailable',
    );
    return GroupedSection(
      header: 'Scrobbling',
      footer: 'Your plays are sent to your own ListenBrainz profile, through your server.',
      children: [
        GroupedRow(
          title: 'ListenBrainz',
          icon: NaviGlyph.person,
          value: value,
          onTap: () => showPlatformSheet<void>(
            context: context,
            title: 'ListenBrainz',
            builder: (_) => _LinkSheet(linked: status.asData?.value.linked == true, host: context),
          ),
        ),
      ],
    );
  }
}

class _LinkSheet extends ConsumerStatefulWidget {
  final bool linked;
  final BuildContext host;
  const _LinkSheet({required this.linked, required this.host});

  @override
  ConsumerState<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends ConsumerState<_LinkSheet> {
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(ListenBrainzLink) work, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work(ref.read(listenBrainzLinkProvider));
      ref.invalidate(listenBrainzStatusProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.host.mounted) showToast(widget.host, done);
    } on ListenBrainzException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Copy your user token from listenbrainz.org › Settings, and paste it here.', style: t.footnote),
          const SizedBox(height: Space.md),
          CupertinoTextField(
            controller: _token,
            placeholder: 'User token',
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            style: t.body,
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.sm),
            Text(_error!, style: t.footnote.copyWith(color: t.danger)),
          ],
          const SizedBox(height: Space.md),
          SheetGroup(children: [
            SheetAction(
              label: widget.linked ? 'Replace Token' : 'Link ListenBrainz',
              onTap: _busy ? null : () => _run((l) => l.link(_token.text), 'ListenBrainz linked'),
              keepOpen: true,
            ),
            if (widget.linked)
              SheetAction(
                label: 'Unlink',
                destructive: true,
                onTap: _busy ? null : () => _run((l) => l.unlink(), 'ListenBrainz unlinked'),
                keepOpen: true,
              ),
          ]),
        ],
      ),
    );
  }
}
