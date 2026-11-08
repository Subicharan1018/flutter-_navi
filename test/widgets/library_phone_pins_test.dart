import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/local_library/logic/local_library_providers.dart';
import 'package:navivibe/models/album.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/pins_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/screens/library_screen.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/widgets/ui/media.dart';

/// The phone Library: the destinations stay put at the top (pins, which come
/// and go, sit below them), and Pinned and Recently Added share one tile size.

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'admin', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _Pins extends PinsNotifier {
  final List<Pin> initial;
  _Pins(this.initial);
  @override
  List<Pin> build() => initial;
}

Album album(String id, String name) =>
    Album(id: id, name: name, artist: 'Artist $id', coverArt: id, songCount: 8, duration: 1800, year: 2024);

Future<void> pump(WidgetTester tester, List<Pin> pins) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox()); // a fresh screen each time
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
      pinsProvider.overrideWith(() => _Pins(pins)),
      recentlyAddedAlbumsProvider.overrideWith((ref) async => [album('r1', 'Fresh One'), album('r2', 'Fresh Two')]),
      localFoldersProvider.overrideWith(() => LocalFoldersNotifier()),
    ],
    child: MaterialApp(
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: const LibraryScreen(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

double y(WidgetTester t, String s) => t.getTopLeft(find.text(s).first).dy;

void main() {
  testWidgets('the destinations come first and do not move when pins are added', (tester) async {
    await pump(tester, const []);
    final before = [for (final d in ['Playlists', 'Artists', 'Albums', 'Songs', 'Favorites']) y(tester, d)];

    await pump(tester, [
      const Pin(kind: PinKind.album, id: 'a1', title: 'Pinned Album', subtitle: 'Someone'),
      const Pin(kind: PinKind.playlist, id: 'p1', title: 'Pinned List', subtitle: 'Playlist'),
    ]);
    final after = [for (final d in ['Playlists', 'Artists', 'Albums', 'Songs', 'Favorites']) y(tester, d)];
    expect(after, before, reason: 'adding pins must not shift the sections');
    expect(y(tester, 'Favorites'), lessThan(y(tester, 'Pinned')));
    expect(y(tester, 'Pinned'), lessThan(y(tester, 'Pinned Album')));
    expect(y(tester, 'Pinned Album'), lessThan(y(tester, 'Recently Added')));
  });

  testWidgets('with no pins the hint is where pins will go, below the sections', (tester) async {
    await pump(tester, const []);
    expect(find.text('Pinned'), findsNothing);
    expect(y(tester, 'Favorites'), lessThan(y(tester, 'Touch and hold an album, playlist or artist to pin it here.')));
  });

  testWidgets('Pinned and Recently Added use one tile size', (tester) async {
    await pump(tester, [const Pin(kind: PinKind.album, id: 'a1', title: 'Pinned Album', subtitle: 'Someone')]);
    final cards = tester.widgetList<MediaCard>(find.byType(MediaCard)).toList();
    expect(cards.length, greaterThanOrEqualTo(3)); // one pin + two recent
    expect({for (final c in cards) c.size}, hasLength(1), reason: 'every tile in both grids is the same size');
    expect(tester.getSize(find.byType(MediaCard).first), tester.getSize(find.byType(MediaCard).last));
  });
}
