import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/subsonic_service.dart';

// ---------------------------------------------------------------------------
// Shuffle Algorithm enum
// ---------------------------------------------------------------------------
enum ShuffleAlgorithm {
  /// Basic Fisher-Yates random shuffle.
  standard,

  /// Balanced Shuffle: spaces composers or genres evenly across
  /// the queue so the same category never plays consecutively.
  spotify,

  /// YouTube-style weighted lottery: songs with higher play-counts, ratings,
  /// stars, or positive "Suggest More" feedback appear more often.
  youtube,
}

// ---------------------------------------------------------------------------
// Shuffle Preference enum
// ---------------------------------------------------------------------------
enum ShufflePreference {
  composer,
  genre,
}

// ---------------------------------------------------------------------------
// Settings state
// ---------------------------------------------------------------------------
class SettingsState {
  final String serverUrl;
  final String username;
  final String password;
  final ShuffleAlgorithm shuffleAlgorithm;
  final ShufflePreference shufflePreference;
  final String uploadApiUrl;
  final String uploadDirectory;

  const SettingsState({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.shuffleAlgorithm = ShuffleAlgorithm.standard,
    this.shufflePreference = ShufflePreference.composer,
    this.uploadApiUrl = '',
    this.uploadDirectory = '/DATA/Media/Music',
  });

  SettingsState copyWith({
    String? serverUrl,
    String? username,
    String? password,
    ShuffleAlgorithm? shuffleAlgorithm,
    ShufflePreference? shufflePreference,
    String? uploadApiUrl,
    String? uploadDirectory,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      shuffleAlgorithm: shuffleAlgorithm ?? this.shuffleAlgorithm,
      shufflePreference: shufflePreference ?? this.shufflePreference,
      uploadApiUrl: uploadApiUrl ?? this.uploadApiUrl,
      uploadDirectory: uploadDirectory ?? this.uploadDirectory,
    );
  }
}

// ---------------------------------------------------------------------------
// Settings notifier
// ---------------------------------------------------------------------------
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier()
      : super(const SettingsState(
          serverUrl: Constants.defaultServerUrl,
          username: Constants.defaultUsername,
          password: '',
          shuffleAlgorithm: ShuffleAlgorithm.standard,
          shufflePreference: ShufflePreference.composer,
          uploadApiUrl: '',
          uploadDirectory: '/DATA/Media/Music',
        )) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final algoName = prefs.getString('shuffleAlgorithm') ?? 'standard';
    final prefName = prefs.getString('shufflePreference') ?? 'composer';
    state = SettingsState(
      serverUrl: prefs.getString('serverUrl') ?? Constants.defaultServerUrl,
      username: prefs.getString('username') ?? Constants.defaultUsername,
      password: prefs.getString('password') ?? '',
      shuffleAlgorithm: ShuffleAlgorithm.values.firstWhere(
        (e) => e.name == algoName,
        orElse: () => ShuffleAlgorithm.standard,
      ),
      shufflePreference: ShufflePreference.values.firstWhere(
        (e) => e.name == prefName,
        orElse: () => ShufflePreference.composer,
      ),
      uploadApiUrl: prefs.getString('uploadApiUrl') ?? '',
      uploadDirectory: prefs.getString('uploadDirectory') ?? '/DATA/Media/Music',
    );
  }

  Future<void> saveSettings(String url, String user, String pass, {String? uploadUrl, String? uploadDir}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', url);
    await prefs.setString('username', user);
    await prefs.setString('password', pass);
    if (uploadUrl != null) await prefs.setString('uploadApiUrl', uploadUrl);
    if (uploadDir != null) await prefs.setString('uploadDirectory', uploadDir);

    state = state.copyWith(
      serverUrl: url,
      username: user,
      password: pass,
      uploadApiUrl: uploadUrl,
      uploadDirectory: uploadDir,
    );
  }

  Future<void> setShuffleAlgorithm(ShuffleAlgorithm algo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shuffleAlgorithm', algo.name);
    state = state.copyWith(shuffleAlgorithm: algo);
  }

  Future<void> setShufflePreference(ShufflePreference pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shufflePreference', pref.name);
    state = state.copyWith(shufflePreference: pref);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

final subsonicServiceProvider = Provider<SubsonicService>((ref) {
  final settings = ref.watch(settingsProvider);
  final service = SubsonicService(
    serverUrl: settings.serverUrl,
    username: settings.username,
    password: settings.password,
    customUploadUrl: settings.uploadApiUrl,
    customUploadDir: settings.uploadDirectory,
  );
  
  ref.onDispose(service.dispose);
  return service;
});
