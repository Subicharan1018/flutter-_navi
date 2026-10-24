import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/ui/invitations.dart';
import 'package:navivibe/features/social/ui/social_settings_section.dart';

class _FakeSettings extends SocialSettingsNotifier {
  final SocialSettings initial;
  final saved = <(bool?, bool?)>[];
  _FakeSettings(this.initial);

  @override
  Future<SocialSettings> build() async => initial;

  @override
  Future<void> save({bool? enabled, bool? hideActivity}) async {
    saved.add((enabled, hideActivity));
    state = AsyncData(initial.copyWith(enabled: enabled, hideActivity: hideActivity));
  }
}

Widget _host(Widget child, List overrides) => ProviderScope(
      // ignore: argument_type_not_assignable
      overrides: overrides.cast(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ThemeTokens(tokens: AppThemeTokens.fallback, child: child)),
        ),
      ),
    );

const _invite = CollabPlaylist(id: 'p1', name: 'Road trip', owner: 'alice', isOwner: false, status: 'invited', invitedBy: 'alice');
const _mine = CollabPlaylist(id: 'p2', name: 'Mine', owner: 'me', isOwner: true, status: 'active');

void main() {
  test('countInvitations counts shared-playlist invites and incoming Blend requests only', () {
    const incoming = Blend(id: 'b1', withUser: 'Bob', status: 'pending', incoming: true);
    const outgoing = Blend(id: 'b2', withUser: 'Cy', status: 'pending');
    const active = Blend(id: 'b3', withUser: 'Di', status: 'active');
    expect(countInvitations([_invite, _mine], [incoming, outgoing, active]), 2);
    expect(countInvitations(const [], const []), 0);
  });

  testWidgets('privacy switches start off and the second one appears only once sharing is on', (tester) async {
    final fake = _FakeSettings(const SocialSettings());
    await tester.pumpWidget(_host(const SocialSettingsSection(), [socialSettingsProvider.overrideWith(() => fake)]));
    await tester.pumpAndSettle();
    expect(find.text('Friends & Sharing'), findsOneWidget);
    expect(find.text('Hide My Activity'), findsNothing);
    expect(tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value, isFalse);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(fake.saved.single.$1, isTrue);
    expect(find.text('Hide My Activity'), findsOneWidget);

    await tester.tap(find.byType(CupertinoSwitch).last);
    await tester.pumpAndSettle();
    expect(fake.saved.last, (null, true));
  });

  testWidgets('invitations section lists invites and hides itself when there are none', (tester) async {
    await tester.pumpWidget(_host(const InvitationsSection(), [
      collabListProvider.overrideWith((ref) async => [_invite, _mine]),
      blendListProvider.overrideWith((ref) async => [
            const Blend(id: 'b1', withUser: 'Bob', status: 'pending', incoming: true),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Invitations'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Mine'), findsNothing);
    expect(find.text('Blend with Bob'), findsOneWidget);
  });

  testWidgets('invitations section is empty when nothing is waiting', (tester) async {
    await tester.pumpWidget(_host(const InvitationsSection(), [
      collabListProvider.overrideWith((ref) async => [_mine]),
      blendListProvider.overrideWith((ref) async => const <Blend>[]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Invitations'), findsNothing);
  });
}
