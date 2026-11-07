import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/cover_art.dart';
import 'package:navivibe/widgets/ui/playlist_cover.dart';

Song _s(String id, String cover) => Song(
      id: id,
      title: id,
      artist: 'a',
      album: 'b',
      coverArt: cover,
      duration: 100,
      track: 1,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
    );

class _Svc extends Fake implements SubsonicService {
  final List<Song> songs;
  final bool fail;
  int calls = 0;
  _Svc(this.songs, {this.fail = false});
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover://$id';
  @override
  Future<List<Song>> getPlaylistSongs(String id, {bool forceRefresh = false}) async {
    calls++;
    if (fail) throw Exception('offline');
    return songs;
  }
}

Playlist _pl({String? cover}) => Playlist(id: 'p', name: 'P', comment: '', songCount: 9, duration: 100, coverArt: cover);

void main() {
  group('playlistMosaicProvider', () {
    Future<List<String>> ids(_Svc svc) async {
      final c = ProviderContainer(overrides: [subsonicServiceProvider.overrideWithValue(svc)]);
      addTearDown(c.dispose);
      return c.read(playlistMosaicProvider('p').future);
    }

    test('takes the first four different covers, in order', () async {
      final got = await ids(_Svc([_s('1', 'a'), _s('2', 'a'), _s('3', 'b'), _s('4', 'c'), _s('5', 'd'), _s('6', 'e')]));
      expect(got, ['a', 'b', 'c', 'd']);
    });

    test('a song with no cover id uses its own id', () async {
      expect(await ids(_Svc([_s('x', ''), _s('y', 'k')])), ['x', 'k']);
    });

    test('fewer than four gives what there is; empty gives none', () async {
      expect(await ids(_Svc([_s('1', 'a')])), ['a']);
      expect(await ids(_Svc([])), isEmpty);
    });

    test('a failed fetch gives none instead of an error', () async {
      expect(await ids(_Svc([], fail: true)), isEmpty);
    });
  });

  group('PlaylistCover', () {
    Future<void> pump(WidgetTester tester, Playlist p, _Svc svc) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [subsonicServiceProvider.overrideWithValue(svc)],
        child: MaterialApp(
          builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
          home: Scaffold(body: Center(child: PlaylistCover(playlist: p, size: 120))),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a playlist with its own cover shows just that', (tester) async {
      final svc = _Svc([_s('1', 'a'), _s('2', 'b'), _s('3', 'c'), _s('4', 'd')]);
      await pump(tester, _pl(cover: 'own'), svc);
      expect(find.byType(CoverArt), findsOneWidget);
      expect(svc.calls, 0, reason: 'no songs are fetched when the server has a cover');
    });

    testWidgets('without one it shows a 2x2 mosaic of the first four songs\' covers', (tester) async {
      await pump(tester, _pl(), _Svc([_s('1', 'a'), _s('2', 'b'), _s('3', 'c'), _s('4', 'd'), _s('5', 'e')]));
      expect(find.byType(CoverArt), findsNWidgets(4));
      expect(tester.getSize(find.byType(PlaylistCover)).width, 120);
    });

    testWidgets('with fewer than four it shows one cover; with none, the playlist glyph', (tester) async {
      await pump(tester, _pl(), _Svc([_s('1', 'a'), _s('2', 'b')]));
      expect(find.byType(CoverArt), findsOneWidget);
      await pump(tester, _pl(), _Svc([]));
      expect(find.byType(CoverArt), findsOneWidget, reason: 'the placeholder square');
    });

    testWidgets('inside a desktop shelf it takes the shelf\'s tile size', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [subsonicServiceProvider.overrideWithValue(_Svc([_s('1', 'a'), _s('2', 'b'), _s('3', 'c'), _s('4', 'd')]))],
        child: MaterialApp(
          builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
          home: Scaffold(body: Center(child: ShelfSize(size: 176, child: PlaylistCover(playlist: _pl(), size: 120)))),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byType(PlaylistCover)).width, 176);
    });
  });
}
