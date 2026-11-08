import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/playlist_access.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

/// Your own playlists are editable; other people's are read-only for everyone
/// (a room's admin too). The rule lives in the model, in the one gate every
/// write passes through, and in the controller's batch update and copy.

Playlist pl(String id, String? owner, {String name = 'Mix'}) =>
    Playlist(id: id, name: name, comment: '', songCount: 2, duration: 100, owner: owner);

Song song(String id) => Song.fromJson({'id': id, 'title': 'T$id', 'artist': 'A', 'album': 'B', 'duration': 100});

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'maya', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Svc extends Fake implements SubsonicService {
  @override
  final PlaylistAccess playlistAccess;
  final calls = <String>[];
  _Svc(String me) : playlistAccess = PlaylistAccess(me);

  @override
  Future<void> updatePlaylist(String playlistId,
      {String? songIdToAdd, int? songIndexToRemove, String? name, String? comment}) async {
    playlistAccess.requireEditable(playlistId);
    calls.add('update $playlistId add=$songIdToAdd rm=$songIndexToRemove');
  }

  @override
  Future<List<Song>> getPlaylistSongs(String id, {bool forceRefresh = false}) async => [song('s1'), song('s2')];

  @override
  Future<Playlist?> createPlaylist(String name) async {
    final p = pl('copy1', null, name: name);
    playlistAccess.learnOne(Playlist(id: 'copy1', name: name, comment: '', songCount: 0, duration: 0, owner: 'maya'));
    calls.add('create $name');
    return p;
  }

  @override
  Future<void> setPlaylistSongs(String playlistId, List<String> songIds) async {
    playlistAccess.requireEditable(playlistId);
    calls.add('set $playlistId ${songIds.join(",")}');
  }

  @override
  Future<void> deletePlaylist(String id) async {
    playlistAccess.requireEditable(id);
    calls.add('delete $id');
  }
}

({ProviderContainer c, _Svc svc}) setUpController() {
  final svc = _Svc('maya')
    ..playlistAccess.learn([pl('mine', 'maya'), pl('his', 'Arjun'), pl('plain', null)]);
  final c = ProviderContainer(overrides: [subsonicServiceProvider.overrideWithValue(svc)]);
  addTearDown(c.dispose);
  return (c: c, svc: svc);
}

void main() {
  group('ownership', () {
    test('yours and unknown-owner playlists are yours; any other name is shared', () {
      expect(pl('a', 'maya').isOwnedBy('maya'), isTrue);
      expect(pl('a', 'Maya').isOwnedBy('maya'), isTrue); // case does not matter
      expect(pl('a', null).isOwnedBy('maya'), isTrue);
      expect(pl('a', '').isOwnedBy('maya'), isTrue);
      expect(pl('a', 'Arjun').isOwnedBy('maya'), isFalse);
      expect(pl('a', 'Arjun').isSharedFor('maya'), isTrue);
    });

    test('a list splits into your playlists and Shared with you', () {
      final s = splitByOwner([pl('1', 'maya'), pl('2', 'Arjun'), pl('3', null), pl('4', 'sana')], 'maya');
      expect(s.mine.map((p) => p.id), ['1', '3']);
      expect(s.shared.map((p) => p.id), ['2', '4']);
    });
  });

  group('the write gate', () {
    test('refuses every kind of change to someone else’s playlist', () {
      final svc = _Svc('maya')..playlistAccess.learn([pl('his', 'Arjun')]);
      expect(() => svc.updatePlaylist('his', songIdToAdd: 's1'), throwsA(isA<PlaylistNotEditable>())); // add
      expect(() => svc.updatePlaylist('his', songIndexToRemove: 0), throwsA(isA<PlaylistNotEditable>())); // remove
      expect(() => svc.updatePlaylist('his', name: 'x'), throwsA(isA<PlaylistNotEditable>())); // rename
      expect(() => svc.setPlaylistSongs('his', ['s2', 's1']), throwsA(isA<PlaylistNotEditable>())); // reorder
      expect(() => svc.deletePlaylist('his'), throwsA(isA<PlaylistNotEditable>())); // delete
      expect(svc.calls, isEmpty);
    });

    test('the message names the owner and the way out', () {
      final e = PlaylistNotEditable('his', 'Arjun');
      expect(e.message, contains('Arjun'));
      expect(e.message, contains('copy'));
    });

    test('lets you change your own, and leaves playlists it hasn’t heard of to the server', () async {
      final svc = _Svc('maya')..playlistAccess.learn([pl('mine', 'maya')]);
      await svc.updatePlaylist('mine', songIdToAdd: 's1');
      await svc.deletePlaylist('mine');
      await svc.updatePlaylist('never-listed', songIdToAdd: 's1');
      expect(svc.calls.length, 3);
    });
  });

  group('the controller', () {
    test('adding to and removing from playlists skips the ones that are not yours', () async {
      final r = setUpController();
      final n = await r.c.read(playlistControllerProvider).batchUpdate(
            songId: 's1',
            adds: {'mine', 'his'},
            removes: {'his', 'plain'},
          );
      expect(r.svc.calls.where((c) => c.contains('his')), isEmpty);
      expect(r.svc.calls.any((c) => c.startsWith('update mine add=s1')), isTrue);
      expect(n, 2); // mine (add) + plain (remove); his never touched
    });

    test('Make a copy creates your own playlist holding the same songs and leaves the original alone', () async {
      final r = setUpController();
      final copy = await r.c.read(playlistControllerProvider).makeCopy(pl('his', 'Arjun', name: 'Road trip'));
      expect(copy.name, 'Road trip (copy)');
      expect(r.svc.calls, ['create Road trip (copy)', 'set copy1 s1,s2']);
      expect(r.svc.playlistAccess.canEdit('copy1'), isTrue); // it is yours
      expect(r.svc.playlistAccess.canEdit('his'), isFalse); // the original still is not
    });
  });

  group('who can be added to', () {
    test('only your playlists are offered as targets', () async {
      final c = ProviderContainer(overrides: [
        playlistsProvider.overrideWith((ref) async => [pl('1', 'maya'), pl('2', 'Arjun'), pl('3', null)]),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
      ]);
      addTearDown(c.dispose);
      c.listen(editablePlaylistsProvider, (_, _) {});
      await c.read(playlistsProvider.future);
      expect(c.read(editablePlaylistsProvider).requireValue.map((p) => p.id), ['1', '3']);
    });
  });
}
