import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../services/subsonic_service.dart';
import '../services/playlist_cache_service.dart';
import '../services/listening_event_collector.dart';
import '../services/cache_settings_service.dart';
import '../services/bpm_analyzer_service.dart';
import '../services/replay_gain_service.dart';
import '../services/transcoding_service.dart';
import '../services/recommendation_service.dart';

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

  /// When false the [ListeningEventCollector] is a no-op — no rows written.
  final bool dataCollectionEnabled;

  const SettingsState({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.shuffleAlgorithm = ShuffleAlgorithm.standard,
    this.shufflePreference = ShufflePreference.composer,
    this.uploadApiUrl = '',
    this.uploadDirectory = '/DATA/Media/Music',
    this.dataCollectionEnabled = true,
  });

  SettingsState copyWith({
    String? serverUrl,
    String? username,
    String? password,
    ShuffleAlgorithm? shuffleAlgorithm,
    ShufflePreference? shufflePreference,
    String? uploadApiUrl,
    String? uploadDirectory,
    bool? dataCollectionEnabled,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      shuffleAlgorithm: shuffleAlgorithm ?? this.shuffleAlgorithm,
      shufflePreference: shufflePreference ?? this.shufflePreference,
      uploadApiUrl: uploadApiUrl ?? this.uploadApiUrl,
      uploadDirectory: uploadDirectory ?? this.uploadDirectory,
      dataCollectionEnabled:
          dataCollectionEnabled ?? this.dataCollectionEnabled,
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
          dataCollectionEnabled: true,
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
      uploadDirectory:
          prefs.getString('uploadDirectory') ?? '/DATA/Media/Music',
      dataCollectionEnabled:
          prefs.getBool('dataCollectionEnabled') ?? true,
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

  Future<void> setDataCollectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dataCollectionEnabled', enabled);
    state = state.copyWith(dataCollectionEnabled: enabled);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

/// Singleton [PlaylistCacheService] — created once, shared across the app.
/// Disposing the provider (e.g. on logout) closes the underlying DB connection.
final playlistCacheServiceProvider = Provider<PlaylistCacheService>((ref) {
  final service = PlaylistCacheService();
  ref.onDispose(service.dispose);
  return service;
});

/// Narrow provider that surfaces only the three fields that control which
/// [SubsonicService] instance we need.  By watching this instead of the full
/// [settingsProvider], [subsonicServiceProvider] is NOT recreated when
/// unrelated settings change (e.g. shuffleAlgorithm, uploadDirectory).
/// Without this guard every settings mutation would destroy the service,
/// nuke all in-memory caches, and close the http.Client mid-flight.
final _credentialsProvider =
    Provider<({String serverUrl, String username, String password})>((ref) {
  final s = ref.watch(settingsProvider);
  return (serverUrl: s.serverUrl, username: s.username, password: s.password);
});

final subsonicServiceProvider = Provider<SubsonicService>((ref) {
  final creds = ref.watch(_credentialsProvider);
  final cache = ref.watch(playlistCacheServiceProvider);
  // Use ref.read for the remaining fields — changing them does NOT require a
  // new service instance and must not trigger a recreation.
  final settings = ref.read(settingsProvider);
  final service = SubsonicService(
    serverUrl: creds.serverUrl,
    username: creds.username,
    password: creds.password,
    cache: cache,
    customUploadUrl: settings.uploadApiUrl,
    customUploadDir: settings.uploadDirectory,
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Singleton [ListeningEventCollector] — one instance for the app's lifetime.
/// Disposed automatically when the provider scope is destroyed.
final listenerCollectorProvider = Provider<ListeningEventCollector>((ref) {
  final collector = ListeningEventCollector();
  // dispose() is async; wrap in a void closure so ref.onDispose type matches.
  ref.onDispose(() => collector.dispose());
  return collector;
});

// ---------------------------------------------------------------------------
// New feature providers
// ---------------------------------------------------------------------------

/// Singleton [CacheSettingsService] — manages image/music/BPM cache toggles.
final cacheSettingsProvider = Provider<CacheSettingsService>((ref) {
  final service = CacheSettingsService();
  return service;
});

/// Singleton [BpmAnalyzerService] — BPM estimation and caching.
final bpmAnalyzerProvider = Provider<BpmAnalyzerService>((ref) {
  final service = BpmAnalyzerService();
  return service;
});

/// Singleton [ReplayGainService] — volume normalisation.
final replayGainProvider = Provider<ReplayGainService>((ref) {
  final service = ReplayGainService();
  return service;
});

/// [TranscodingService] — network-aware bitrate/format management.
/// Uses ChangeNotifierProvider so UI reactively updates when connection
/// type or settings change.
final transcodingProvider = ChangeNotifierProvider<TranscodingService>((ref) {
  final service = TranscodingService();
  ref.onDispose(service.dispose);
  return service;
});

/// [RecommendationService] — play pattern tracking and personalised feeds.
/// ChangeNotifierProvider so screens can react to new recommendation data.
final recommendationProvider =
    ChangeNotifierProvider<RecommendationService>((ref) {
  final service = RecommendationService();
  // Initialize asynchronously — listeners fire after data is loaded.
  service.initialize();
  return service;
});
