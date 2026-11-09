import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/data/repositories/shuffle_repository.dart';
import 'package:navivibe/features/ai_shuffle/logic/shuffle_providers.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/playlist_suggestions.dart';
import 'package:navivibe/services/subsonic_service.dart';

Song _s(int i) => Song(
      id: 's$i',
      title: 'Pick $i',
      artist: 'A',
      album: 'B',
      coverArt: '',
      duration: 100,
      track: i,
      year: 2024,
      suffix: 'mp3',
      bitRate: 128,
    );

class _FakeRepo extends Fake implements ShuffleRepository {
  final calls = <int>[];
  @override
  Future<List<({String id, String why})>> getPlaylistSuggestions(List<String> songIds, {int limit = 10}) async {
    calls.add(limit);
    // The server answers the same ranking each time; a bigger limit reaches further down it.
    return [for (var i = 0; i < limit.clamp(0, 25); i++) (id: 's$i', why: '')];
  }
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

void main() {
  testWidgets('Refresh shows ten new suggestions and never repeats the last batch', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1600);
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shuffleRepositoryProvider.overrideWithValue(repo),
          subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
          allSongsProvider.overrideWith((ref) async => [for (var i = 0; i < 30; i++) _s(i)]),
        ],
        child: ThemeTokens(
          tokens: AppThemeTokens.fallback,
          child: MaterialApp(
            theme: AppTheme.build(AppThemeTokens.fallback),
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlaylistSuggestions(playlistId: 'p', playlistName: 'P', songs: [_s(99)], onAdded: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pick 0'), findsOneWidget);
    expect(find.text('Pick 9'), findsOneWidget);
    expect(find.text('Pick 10'), findsNothing);

    await tester.tap(find.byTooltip('Refresh suggestions'));
    await tester.pumpAndSettle();
    expect(find.text('Pick 0'), findsNothing, reason: 'the last batch is not shown again');
    expect(find.text('Pick 10'), findsOneWidget);
    expect(find.text('Pick 19'), findsOneWidget);

    await tester.tap(find.byTooltip('Refresh suggestions'));
    await tester.pumpAndSettle();
    expect(find.text('Pick 10'), findsNothing);
    expect(find.text('Pick 20'), findsOneWidget);
  });
}
