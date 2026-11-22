import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/providers/library_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _Settings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _Settings() : super(const SettingsState(serverUrl: 'https://m.example', username: 'u', password: 'p'));
  void set(SettingsState s) => state = s;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Svc extends Fake implements SubsonicService {
  int playlistCalls = 0;
  @override
  Future<List<Playlist>> getPlaylists() async {
    playlistCalls++;
    return [];
  }
}

void main() {
  test('library providers do not refetch when an unrelated setting changes', () async {
    final settings = _Settings();
    final svc = _Svc();
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => settings),
      subsonicServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(playlistsProvider, (_, _) {});
    addTearDown(sub.close);

    await c.read(playlistsProvider.future);
    expect(svc.playlistCalls, 1);

    settings.set(settings.state.copyWith(crossfadeSeconds: 6));
    await Future<void>.delayed(Duration.zero);
    await c.read(playlistsProvider.future);
    expect(svc.playlistCalls, 1);
  });
}
