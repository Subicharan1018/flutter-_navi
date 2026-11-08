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
      'you_can_edit': ?canEdit,
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
  Future<JamState> jamRequestSkip(String code) async => reply..let(() => calls.add('request-skip'));
  @override
  Future<JamState> jamResolveSkip(String code, {required bool approve, String? user}) async =>
      reply..let(() => calls.add(approve ? 'approve-skip' : 'dismiss-skip'));
  @override
  Future<JamState> jamUndo(String code, int itemId) async => reply..let(() => calls.add('undo $itemId'));
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
      expect(await c.setOpen(true), isFalse); // showing the room in People is the admin's call
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

  group('skip requests and undo', () {
    test('a Jam member can ask to skip, once, and cannot approve it', () async {
      final r = setUpRoom(room());
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.requestSkip(), isTrue);
      expect(r.api.calls, ['request-skip']);
      expect(await c.resolveSkip(approve: true), isFalse); // only the admin
      expect(r.api.calls, ['request-skip']);
    });

    test('a member who already asked is not sent again', () async {
      final r = setUpRoom(JamState.fromJson({
        'code': 'K7QX2M', 'version': 1, 'mode': 'jam', 'host': 'maya', 'you_are_host': false, 'you_requested_skip': true,
        'members': <Object>[], 'queue': [{'id': 1, 'song_id': 's1', 'title': 'T'}], 'index': 0, 'playing': true,
        'position_ms': 0, 'server_ms': 0,
      }));
      expect(await r.c.read(jamControllerProvider.notifier).requestSkip(), isTrue);
      expect(r.api.calls, isEmpty);
    });

    test('the admin skips for themselves, and a Collab member needs no request', () async {
      final admin = setUpRoom(room(admin: true));
      expect(await admin.c.read(jamControllerProvider.notifier).requestSkip(), isFalse);
      final collab = setUpRoom(room(mode: 'collab'));
      expect(await collab.c.read(jamControllerProvider.notifier).requestSkip(), isFalse);
      expect(admin.api.calls, isEmpty);
      expect(collab.api.calls, isEmpty);
    });

    test('the admin approves or dismisses', () async {
      final r = setUpRoom(room(admin: true));
      final c = r.c.read(jamControllerProvider.notifier);
      expect(await c.resolveSkip(approve: true), isTrue);
      expect(await c.resolveSkip(approve: false), isTrue);
      expect(r.api.calls, ['approve-skip', 'dismiss-skip']);
    });

    test('undo is for whoever may edit: the admin in a Jam, anyone in a Collab room, never a member', () async {
      final admin = setUpRoom(room(admin: true));
      expect(await admin.c.read(jamControllerProvider.notifier).undoRemove(3), isTrue);
      final collab = setUpRoom(room(mode: 'collab'));
      expect(await collab.c.read(jamControllerProvider.notifier).undoRemove(3), isTrue);
      final member = setUpRoom(room());
      expect(await member.c.read(jamControllerProvider.notifier).undoRemove(3), isFalse);
      expect(member.api.calls, isEmpty);
    });

    test('the room state carries requests and who left', () {
      final j = JamState.fromJson({
        'code': 'K7QX2M', 'version': 1, 'mode': 'jam', 'host': 'maya', 'you_are_host': true,
        'members': <Object>[], 'queue': <Object>[], 'index': 0, 'playing': false, 'position_ms': 0, 'server_ms': 0,
        'skip_requests': [{'username': 'Arjun', 'item_id': 4}],
        'recently_left': [
          {'username': 'Sana', 'reason': 'removed', 'ago_s': 40},
          {'username': 'Dev', 'reason': 'left', 'ago_s': 400},
        ],
      });
      expect(j.skipRequests.single.username, 'Arjun');
      expect(j.recentlyLeft.map((m) => m.removed), [true, false]);
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
