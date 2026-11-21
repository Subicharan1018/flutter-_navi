import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/database/app_database.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _Subsonic extends Fake implements SubsonicService {
  int artistCalls = 0;
  @override
  Future<List<Map<String, dynamic>>> getArtists() async {
    artistCalls++;
    return [
      {'id': 'a1', 'name': 'Anirudh Ravichander'},
    ];
  }

  @override
  String getCoverArtUrl(String? id, {int? size}) => 'cover:$id';
}

void main() {
  late AppDatabase db;
  late _Subsonic svc;
  ProviderContainer make() {
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      subsonicServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = _Subsonic();
  });
  tearDown(() => db.close());

  test('a top artist shows the artist’s own portrait, found by name', () async {
    final c = make();
    expect(await c.read(artistCoverUrlProvider('Anirudh Ravichander').future), 'cover:ar-a1');
    // case and spacing do not matter; the artist list is fetched once
    expect(await c.read(artistCoverUrlProvider(' anirudh ravichander ').future), 'cover:ar-a1');
    expect(svc.artistCalls, 1);
  });

  test('an artist the library does not know has no portrait', () async {
    expect(await make().read(artistCoverUrlProvider('Nobody At All').future), isNull);
  });
}
