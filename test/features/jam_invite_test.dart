import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/social/data/social_api.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_controller.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/logic/social_rules.dart';
import 'package:navivibe/features/social/ui/invitations.dart';

/// Inviting a friend into a Jam: the client of jam-invites-v1, what an
/// invitation says, and the one-tap Join / Decline row.

class _Adapter implements HttpClientAdapter {
  final Map<String, ResponseBody Function()> routes;
  final List<(String, Object?)> sent = [];
  _Adapter(this.routes);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    sent.add((o.path, o.data));
    final r = routes[o.path];
    return r == null ? _json(404, {'error': 'Not found'}) : r();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {'content-type': ['application/json']});

SocialApi _api(_Adapter a) => SocialApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = a);

const _invite = JamInvite(code: 'K7QX2M', from: 'maya', members: 2, at: 100, expiresAt: 1900);

class _FakeJam extends JamController {
  final joined = <String>[];
  bool succeed = true;

  @override
  Future<bool> join(String code) async {
    joined.add(code);
    return succeed;
  }
}

class _FakeApi extends Fake implements SocialApi {
  final declined = <String>[];
  @override
  Future<void> jamInviteDecline(String code) async => declined.add(code);
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

void main() {
  group('client', () {
    test('invites are read, with the room, who sent it and when it runs out', () async {
      final a = _Adapter({
        '/social/jam/invites': () => _json(200, {
              'invites': [
                {'code': 'K7QX2M', 'from': 'maya', 'mode': 'collab', 'members': 3, 'at': 100.5, 'expires_at': 1900.5},
              ],
            }),
      });
      final got = await _api(a).jamInvites();
      expect(got.single.code, 'K7QX2M');
      expect(got.single.from, 'maya');
      expect(got.single.mode, JamMode.collab);
      expect(got.single.members, 3);
      expect(got.single.expiresAt - got.single.at, 1800);
    });

    test('a server without invites (404) means none, not an error', () async {
      expect(await _api(_Adapter({})).jamInvites(), isEmpty);
    });

    test('other failures still surface', () async {
      final a = _Adapter({'/social/jam/invites': () => _json(401, {'error': 'auth'})});
      expect(_api(a).jamInvites(), throwsA(isA<SocialException>().having((e) => e.status, 'status', 401)));
    });

    test('invite sends the friend, decline names the room', () async {
      final a = _Adapter({
        '/social/jam/K7QX2M/invite': () => _json(200, {'invited': 'Bob'}),
        '/social/jam/K7QX2M/invite/decline': () => _json(200, {'declined': true}),
      });
      final api = _api(a);
      await api.jamInvite('K7QX2M', 'Bob');
      await api.jamInviteDecline('K7QX2M');
      expect(a.sent.first.$1, '/social/jam/K7QX2M/invite');
      expect(a.sent.first.$2, {'to': 'Bob'});
      expect(a.sent.last.$1, '/social/jam/K7QX2M/invite/decline');
    });

    test('the server’s refusal reaches the person in its own words', () async {
      final a = _Adapter({
        '/social/jam/K7QX2M/invite': () => _json(404, {'error': 'That person isn’t on social features.'}),
      });
      expect(
        _api(a).jamInvite('K7QX2M', 'Zed'),
        throwsA(isA<SocialException>().having((e) => e.message, 'message', contains('isn’t on social'))),
      );
    });
  });

  group('rules', () {
    test('the line names who and what kind of room', () {
      expect(jamInviteLine(_invite), 'maya invited you to a Jam');
      expect(jamInviteLine(const JamInvite(code: 'X', from: 'Bob', mode: JamMode.collab)), 'Bob invited you to a Collab room');
    });

    test('the detail says how many are already in', () {
      expect(jamInviteDetail(_invite), '2 people are in it');
      expect(jamInviteDetail(const JamInvite(code: 'X', from: 'a')), 'Just them so far');
    });

    test('one invitation per room, newest first', () {
      const old = JamInvite(code: 'A', from: 'maya', at: 10);
      const again = JamInvite(code: 'A', from: 'maya', at: 50);
      const other = JamInvite(code: 'B', from: 'Bob', at: 30);
      final shown = latestJamInvites([old, other, again]);
      expect(shown.map((i) => i.code), ['A', 'B']);
      expect(shown.first.at, 50);
    });

    test('Jam invitations count with the others, so the badge and the notification see them', () {
      const blend = Blend(id: 'b', withUser: 'Bob', status: 'pending', incoming: true);
      expect(countInvitations(const [], const []), 0);
      expect(countInvitations(const [], [blend], [_invite, _invite]), 3);
    });
  });

  group('invitations row', () {
    testWidgets('Join is one tap and uses the invite’s code', (tester) async {
      final jam = _FakeJam();
      await tester.pumpWidget(_host(const InvitationsSection(), [
        jamInvitesProvider.overrideWith((ref) async => [_invite]),
        collabListProvider.overrideWith((ref) async => const <CollabPlaylist>[]),
        blendListProvider.overrideWith((ref) async => const <Blend>[]),
        jamControllerProvider.overrideWith(() => jam),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('maya invited you to a Jam'), findsOneWidget);
      expect(find.text('2 people are in it'), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(jam.joined, ['K7QX2M']);
    });

    testWidgets('Decline tells the server and refreshes the list', (tester) async {
      final api = _FakeApi();
      var reads = 0;
      await tester.pumpWidget(_host(const InvitationsSection(), [
        socialApiProvider.overrideWithValue(api),
        jamInvitesProvider.overrideWith((ref) async => reads++ == 0 ? [_invite] : const <JamInvite>[]),
        collabListProvider.overrideWith((ref) async => const <CollabPlaylist>[]),
        blendListProvider.overrideWith((ref) async => const <Blend>[]),
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(api.declined, ['K7QX2M']);
      expect(find.text('maya invited you to a Jam'), findsNothing);
      expect(find.text('Invitations'), findsNothing);
    });

    testWidgets('a join the server refuses says so and leaves the row to answer again', (tester) async {
      final jam = _FakeJam()..succeed = false;
      await tester.pumpWidget(_host(const InvitationsSection(), [
        jamInvitesProvider.overrideWith((ref) async => [_invite]),
        collabListProvider.overrideWith((ref) async => const <CollabPlaylist>[]),
        blendListProvider.overrideWith((ref) async => const <Blend>[]),
        jamControllerProvider.overrideWith(() => jam),
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('maya invited you to a Jam'), findsOneWidget);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(jam.joined, ['K7QX2M', 'K7QX2M']);
    });
  });
}
