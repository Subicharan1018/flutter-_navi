import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/features/smart_playlists/data/playlist_entries.dart';
import 'package:navivibe/features/smart_playlists/data/playlist_folders.dart';
import 'package:navivibe/features/smart_playlists/data/smart_rules.dart';
import 'package:navivibe/features/smart_playlists/logic/smart_playlist_providers.dart';
import 'package:navivibe/models/playlist.dart';

Playlist pl(String id) => Playlist(id: id, name: 'P$id', comment: '', songCount: 1, duration: 60);
SmartPlaylist sp(String id) => SmartPlaylist(id: id, name: 'S$id', createdAt: 0);

void main() {
  group('PlaylistFolders', () {
    test('create trims, ignores blanks and duplicate ids', () {
      var s = PlaylistFolders.empty.create('f1', '  Road trip ');
      expect(s.folders.single.name, 'Road trip');
      s = s.create('f1', 'Again').create('f2', '   ');
      expect(s.folders, hasLength(1));
    });

    test('move puts a playlist in one folder at a time, and out again', () {
      var s = PlaylistFolders.empty.create('a', 'A').create('b', 'B').move('p1', 'a');
      expect(s.folderOf('p1'), 'a');
      s = s.move('p1', 'b');
      expect(s.folderOf('p1'), 'b');
      expect(s.countIn('a'), 0);
      s = s.move('p1', null);
      expect(s.folderOf('p1'), isNull);
    });

    test('move to an unknown folder changes nothing', () {
      final s = PlaylistFolders.empty.create('a', 'A');
      expect(identical(s.move('p1', 'ghost'), s), isTrue);
    });

    test('delete frees its playlists and keeps other folders', () {
      final s = PlaylistFolders.empty
          .create('a', 'A')
          .create('b', 'B')
          .move('p1', 'a')
          .move('p2', 'b')
          .delete('a');
      expect(s.folders.map((f) => f.id), ['b']);
      expect(s.folderOf('p1'), isNull);
      expect(s.folderOf('p2'), 'b');
    });

    test('rename and pin; pinned folders list first', () {
      final s = PlaylistFolders.empty.create('a', 'A').create('b', 'B').create('c', 'C').rename('b', ' Bee ').setPinned('c', true);
      expect(s.ordered.map((f) => f.id), ['c', 'a', 'b']);
      expect(s.folder('b')!.name, 'Bee');
      expect(identical(s.rename('a', ' '), s), isTrue);
    });

    test('round-trips JSON and drops memberships of missing folders', () {
      final s = PlaylistFolders.empty.create('a', 'A').setPinned('a', true).setExpanded('a', false).move('p1', 'a');
      final back = PlaylistFolders.fromJson(s.toJson());
      expect(back.folder('a')!.pinned, isTrue);
      expect(back.folder('a')!.expanded, isFalse);
      expect(back.folderOf('p1'), 'a');
      final stale = PlaylistFolders.fromJson({
        'folders': [
          {'id': 'a', 'name': 'A'},
        ],
        'membership': {'p1': 'a', 'p2': 'gone'},
      });
      expect(stale.membership.keys, ['p1']);
      expect(PlaylistFolders.fromJson(null).folders, isEmpty);
    });
  });

  group('buildPlaylistEntries', () {
    test('pinned folders first, members under expanded folders, rest loose', () {
      final folders = PlaylistFolders.empty
          .create('a', 'A')
          .create('b', 'B')
          .setPinned('b', true)
          .move('1', 'a')
          .move('smart:9', 'b')
          .move('gone', 'a');
      final entries = buildPlaylistEntries(
        folders: folders,
        smart: [sp('smart:9')],
        server: [pl('1'), pl('2')],
      );
      String name(PlaylistEntry e) => switch (e) {
            FolderEntry() => 'folder ${e.folder.id} (${e.count})',
            ItemEntry() => '${e.inFolder ? '  ' : ''}${e.id}',
          };
      expect(entries.map(name), ['folder b (1)', '  smart:9', 'folder a (1)', '  1', '2']);
    });

    test('collapsed folders hide members but still count them', () {
      final folders = PlaylistFolders.empty.create('a', 'A').move('1', 'a').setExpanded('a', false);
      final entries = buildPlaylistEntries(folders: folders, smart: const [], server: [pl('1')]);
      expect(entries, hasLength(1));
      expect((entries.single as FolderEntry).count, 1);
    });

    test('smart playlists come before server ones among loose items', () {
      final entries = buildPlaylistEntries(folders: PlaylistFolders.empty, smart: [sp('smart:1')], server: [pl('1')]);
      expect(entries.map((e) => (e as ItemEntry).id), ['smart:1', '1']);
    });
  });

  group('stores persist to Hive', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hive_smart_playlists');
      Hive.init(dir.path);
      HiveBoxes.prefs = await Hive.openBox('prefs');
    });

    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('folders survive a restart', () async {
      final a = ProviderContainer();
      final folders = a.read(playlistFoldersProvider.notifier);
      final id = folders.create('Chill');
      folders.move('p1', id);
      folders.setPinned(id, true);
      a.dispose();

      final b = ProviderContainer();
      addTearDown(b.dispose);
      final restored = b.read(playlistFoldersProvider);
      expect(restored.folders.single.name, 'Chill');
      expect(restored.folders.single.pinned, isTrue);
      expect(restored.folderOf('p1'), id);
    });

    test('smart playlists survive a restart; removing one frees its folder slot', () async {
      final a = ProviderContainer();
      final store = a.read(smartPlaylistsProvider.notifier);
      final id = store.newId();
      expect(SmartPlaylist.isSmartId(id), isTrue);
      store.upsert(SmartPlaylist(id: id, name: 'Sad ones', createdAt: 1, limit: 10));
      final folderId = a.read(playlistFoldersProvider.notifier).create('F');
      a.read(playlistFoldersProvider.notifier).move(id, folderId);
      store.upsert(store.byId(id)!.copyWith(name: 'Sadder'));
      expect(a.read(smartPlaylistsProvider), hasLength(1));
      a.dispose();

      final b = ProviderContainer();
      addTearDown(b.dispose);
      expect(b.read(smartPlaylistsProvider).single.name, 'Sadder');
      expect(b.read(smartPlaylistsProvider).single.limit, 10);
      b.read(smartPlaylistsProvider.notifier).remove(id);
      expect(b.read(smartPlaylistsProvider), isEmpty);
      expect(b.read(playlistFoldersProvider).folderOf(id), isNull);
    });
  });
}
