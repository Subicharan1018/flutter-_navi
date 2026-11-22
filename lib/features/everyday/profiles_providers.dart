import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'profiles.dart';

abstract class ProfilesBackend {
  String? read();
  Future<void> write(String value);
}

/// The encrypted auth box: profiles hold passwords.
class HiveProfilesBackend implements ProfilesBackend {
  static const key = 'profiles_v1';

  @override
  String? read() {
    final v = HiveBoxes.auth.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String value) => HiveBoxes.auth.put(key, value);
}

final profilesBackendProvider = Provider<ProfilesBackend>((ref) => HiveProfilesBackend());

class ProfilesNotifier extends Notifier<Profiles> {
  @override
  Profiles build() {
    try {
      return Profiles.decode(ref.read(profilesBackendProvider).read());
    } catch (_) {
      return const Profiles();
    }
  }

  void _save(Profiles next) {
    if (identical(next, state)) return;
    state = next;
    try {
      ref.read(profilesBackendProvider).write(next.encode());
    } catch (_) {}
  }

  void remember(String serverUrl, String username, String password) =>
      _save(state.remember(serverUrl, username, password));

  void rename(Profile p, String name) => _save(state.rename(p.serverUrl, p.username, name));

  void forget(Profile p) => _save(state.forget(p.serverUrl, p.username));
}

final profilesProvider = NotifierProvider<ProfilesNotifier, Profiles>(ProfilesNotifier.new);

/// Every login this device uses is remembered as a profile, however it got
/// there (typed on a phone, sent to the TV by pairing). Read once at start-up.
/// The browser build keeps no passwords and so no profiles.
final profilesBootstrapProvider = Provider<void>((ref) {
  if (kIsWeb) return;
  void note(SettingsState s) =>
      ref.read(profilesProvider.notifier).remember(s.serverUrl, s.username, s.password);
  note(ref.read(settingsProvider));
  ref.listen(settingsProvider, (_, next) => note(next));
});

/// Switches this device to [profile]: stops what is playing (it belongs to
/// the person who started it), then signs in as them. The account-bound
/// providers rebuild from the new login.
Future<void> switchToProfile(WidgetRef ref, Profile profile) async {
  final current = ref.read(settingsProvider);
  if (Profile.keyOf(current.serverUrl, current.username) == profile.key) return;
  await ref.read(playerProvider.notifier).stop();
  await ref.read(settingsProvider.notifier).saveSettings(profile.serverUrl, profile.username, profile.password);
  ref.read(playerProvider.notifier).refreshShuffleUrl();
}
