import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/film_credits/data/film_info.dart';
import 'package:navivibe/features/film_credits/logic/film_credits_providers.dart';
import 'package:navivibe/models/catalog.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/artwork.dart' show coverPaletteProvider, debugCoverImageOverride;
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

class FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => 'c${(id ?? '0').hashCode.abs() % 9}';
}

class FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final List<List<String>> queues = [];
  FakePlayer()
      : super(const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
        ));

  @override
  Future<void> setQueue(List<Song> songs, int index, {String? playlistName, List<Song>? unshuffledSongs, bool autoplay = true}) async {
    queues.add([for (final s in songs) s.id]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class FixedCatalog extends CatalogNotifier {
  final Map<String, CatalogSong> songs;
  FixedCatalog(this.songs);
  @override
  Future<CatalogDocument> build() async => CatalogDocument(songs: songs);
}

class FixedFilmInfos extends FilmInfosNotifier {
  final Map<String, FilmInfo> infos;
  FixedFilmInfos(this.infos);
  @override
  Future<Map<String, FilmInfo>> build() async => infos;
}

Song s(String id, String title, String artist, {String composer = '', int track = 1, int year = 2016, String cover = 'c1'}) =>
    Song(id: id, title: title, artist: artist, album: 'A$id', composer: composer, coverArt: cover, duration: 230, track: track, year: year);

/// A small, realistic library: Remo (2016), Kodi (2016) and a song with no film.
final librarySongs = [
  s('1', 'Sirikkadhey', 'Anirudh Ravichander ; Shweta Mohan', composer: 'Anirudh Ravichander', track: 1, cover: 'c1'),
  s('2', 'Remo Theme', 'Anirudh Ravichander', composer: 'Anirudh Ravichander', track: 2, cover: 'c1'),
  s('3', 'Ei Suzhali', 'Santhosh Narayanan ; Vivek', composer: 'Santhosh Narayanan', cover: 'c4'),
  s('4', 'Why This Kolaveri Di', 'Dhanush', composer: 'Anirudh Ravichander', year: 2011, cover: 'c6'),
  s('5', 'Alone', 'Alan Walker', year: 2015, cover: 'c2'),
];

Map<String, CatalogSong> catalogFor() => {
      '1': const CatalogSong(id: '1', film: 'Remo', musicDirectors: ['Anirudh Ravichander'], lyricists: ['Thamarai'], singers: ['Anirudh Ravichander', 'Shweta Mohan']),
      '2': const CatalogSong(id: '2', film: 'Remo'),
      '3': const CatalogSong(id: '3', film: 'Kodi', lyricist: 'Vivek'),
      '4': const CatalogSong(id: '4', film: '3'),
      '5': const CatalogSong(id: '5'),
    };

final remoInfo = FilmInfo(
  title: 'Remo',
  year: 2016,
  directors: const ['Bakkiyaraj Kannan'],
  musicDirectors: const ['Anirudh Ravichander'],
  lyricists: const ['Thamarai'],
  tracklist: const [
    TrackStub(title: 'Sirikkadhey', artist: 'Anirudh Ravichander'),
    TrackStub(title: 'Remo Theme'),
    TrackStub(title: 'Unnaal Unnaal', artist: 'Yazin Nizar'),
    TrackStub(title: 'Kadhal Cricket', artist: 'Anirudh Ravichander'),
  ],
);

Widget app(Widget home, {FakePlayer? player, List<Override> extra = const []}) {
  final tokens = AppThemeTokens.fallback;
  return ProviderScope(
    overrides: [
      subsonicServiceProvider.overrideWithValue(FakeSubsonic()),
      playerProvider.overrideWith((ref) => player ?? FakePlayer()),
      allSongsProvider.overrideWith((ref) async => librarySongs),
      catalogProvider.overrideWith(() => FixedCatalog(catalogFor())),
      filmInfosProvider.overrideWith(() => FixedFilmInfos({'remo': remoInfo})),
      coverPaletteProvider.overrideWith((ref, id) async => AlbumPalette.fallback),
      ...extra,
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
    ),
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
}

/// Covers draw a flat tile instead of going to the network / cache manager (no platform plugins in tests).
void useFakeCovers() {
  final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  setUp(() => debugCoverImageOverride = (url, key) => MemoryImage(png));
  tearDown(() => debugCoverImageOverride = null);
}
