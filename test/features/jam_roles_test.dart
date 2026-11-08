import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_api.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/jam_controller.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';

/// Who may do what in a room. The server is the real gate; the controller must
/// not even send a request the server will refuse, and the models must read the
/// roles the server reports.

JamState room({
  String mode = 'jam',
  bool admin = false,
  bool? canEdit,
  int songs = 3,
}) =>
    JamState.fromJson({
      'code': 'K7QX2M',
      'version': 4,
      'mode': mode,
      'host': 'maya',
      'admin': 'maya',
      'you_are_host': admin,
      'you_are_admin': admin,
      if (canEdit != null) 'you_can_edit': canEdit,
      'members': [
        {'username': 'maya', 'is_host': true, 'role': 'admin'},
        {'username': 'Arjun', 'is_host': false, 'role': 'member'},
      ],
      'queue': [
        for (var i = 1; i <= songs; i++)
          {'id': i, 'song_id': 's$i', 'title': 'T$i', 'added_by': i.isOdd ? 'maya' : 'Arjun', 'duration_s': 100},
      ],
      'index': 0,
      'playing': false,
      'position_ms': 0,
      'server_ms': 1000,
    });

class _Api extends Fake implements SocialApi {
  final calls = <String>[];
  final JamState reply;
  _Api(this.reply);

  @override
  Future<JamState> jamRemoveItem(String code, int itemId) async => reply..let(() => calls.add('remove $itemId'));
  @override
  Future<JamState> jamClear(String code) async => reply..let(() => calls.add('clear'));
  @override
  Future<JamState> jamControl(String code, String action, {int? positionMs, int? index, int? itemId}) async =>
      reply..let(() => calls.add(action));
  @override
  Future<JamState> jamTransferAdmin(String code, String to) async => reply..let(() => calls.add('admin $to'));
  @override
  Future<JamState> jamKick(String code, String user) async => reply..let(() => calls.add('kick $user'));
  @override
  Future<JamState> jamAddSongs(String code, List songs) async => reply..let(() => calls.add('add'));
}

extension on Object {
  void let(void Function() f) => f();
}

class _FakeJam extends JamController {
  final JamState initial;
  _FakeJam(this.initial);
  @override
  JamUiState build() => JamUiState(jam: initial);
}

({ProviderContainer c, _Api api}) setUpRoom(JamState jam) {
  final api = _Api(jam);
  final c = ProviderContainer(overrides: [
    socialApiProvider.overrideWithValue(api),
    jamControllerProvider.overrideWith(() => _FakeJam(jam)),
  ]);
  addTearDown(c.dispose);
  return (c: c, api: api);
}

void main() {
  group('reading the roles', () {
    test('the creator is the admin, the rest are members', () {
      final j = room(admin: false);
      expect(j.admin, 'maya');
      expect(j.members.map((m) => m.role), ['Admin', 'Member']);
      expect(j.members.first.isAdmin, isTrue);
      expect(j.youAreAdmin, isFalse);
    });

    test('a jam member cannot edit, the admin and every collab member can', () {
      expect(room().youCanEdit, isFalse);
      expect(room(admin: true).youCanEdit, isTrue);
      expect(room(mode: 'collab').youCanEdit, isTrue);
      expect(room(mode: 'collab').isCollab, isTrue);
    });

    test('an older server that sends only host fields still works', () {
      final j = JamState.fromJson({
        'code': 'ABC234',
        'version': 1,
        'host': 'maya',
        'you_are_host': true,
        'members': [
          {'username': 'maya', 'is_host': true},
        ],
        'queue': <Object>[],
        'index': 0,
        'playing': false,
        'position_ms': 0,
        'server_ms': 0,
      });
      expect(j.mode, JamMode.jam);
      expect(j.youAreAdmin, isTrue);
      expect(j.youCanEdit, isTrue);
    });

    test('the server’s own answer wins over the guess', () {
      expect(room(canEdit: false, admin: true).youCanEdit, isFalse);
    });
  });

  group('a Jam member', () {
    test('can add songs and nothing else', () async {
      final r = setUpRoom(room());
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.addSongs(const []), isTrue);
      for (final denied in [
        c.togglePlay(),
        c.next(),
        c.previous(),
        c.jumpTo(1),
        c.seek(5000),
        c.moveItem(1, 2),
        c.removeItem(1),
        c.removeItem(2), // not even a song they added
        c.clearQueue(),
      ]) {
        expect(await denied, isFalse);
      }
      expect(r.api.calls, ['add']); // nothing else reached the server
      expect(r.c.read(jamControllerProvider).notice, contains('admin controls the queue'));
    });

    test('cannot hand over the role or remove anyone', () async {
      final r = setUpRoom(room());
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.makeAdmin('Arjun'), isFalse);
      expect(await c.removeMember('maya'), isFalse);
      expect(r.api.calls, isEmpty);
      expect(r.c.read(jamControllerProvider).notice, 'Only the admin can do that.');
    });
  });

  group('the admin', () {
    test('can reorder, remove, skip, clear, hand over and remove members', () async {
      final r = setUpRoom(room(admin: true));
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.moveItem(1, 2), isTrue);
      expect(await c.removeItem(2), isTrue);
      expect(await c.next(), isTrue);
      expect(await c.jumpTo(1), isTrue);
      expect(await c.clearQueue(), isTrue);
      expect(await c.makeAdmin('Arjun'), isTrue);
      expect(await c.removeMember('Arjun'), isTrue);
      expect(r.api.calls, ['move', 'remove 2', 'next', 'jump', 'clear', 'admin Arjun', 'kick Arjun']);
    });
  });

  group('a Collab member', () {
    test('edits like an equal but still cannot touch the admin’s powers', () async {
      final r = setUpRoom(room(mode: 'collab'));
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.moveItem(1, 2), isTrue);
      expect(await c.removeItem(1), isTrue); // maya’s song, removed by Arjun
      expect(await c.next(), isTrue);
      expect(await c.clearQueue(), isTrue);
      expect(await c.makeAdmin('Arjun'), isFalse);
      expect(await c.removeMember('maya'), isFalse);
      expect(r.api.calls, ['move', 'remove 1', 'next', 'clear']);
    });
  });
}
