import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/hive_boxes.dart';
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
  final String analyticsUploadSchedule; // 'none', 'weekly', 'monthly'
  final String? analyticsLastUpload;

  const SettingsState({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.shuffleAlgorithm = ShuffleAlgorithm.standard,
    this.shufflePreference = ShufflePreference.composer,
    this.uploadApiUrl = '',
    this.uploadDirectory = '/DATA/Media/Music',
    this.dataCollectionEnabled = true,
    this.analyticsUploadSchedule = 'none',
    this.analyticsLastUpload,
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
    String? analyticsUploadSchedule,
    String? analyticsLastUpload,
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
      analyticsUploadSchedule: analyticsUploadSchedule ?? this.analyticsUploadSchedule,
      analyticsLastUpload: analyticsLastUpload ?? this.analyticsLastUpload,
    );
  }
}

// ---------------------------------------------------------------------------
// Settings notifier — now uses Hive for instant sync reads
// ---------------------------------------------------------------------------
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier()
      : super(const SettingsState(
          serverUrl: '',
          username: '',
          password: '',
        )) {
    // Hive boxes are already open — read is synchronous, no async gap.
    _loadFromHive();
  }

  void _loadFromHive() {
    final auth = HiveBoxes.auth;
    final p = HiveBoxes.prefs;

    final algoName = p.get(HiveBoxes.kShuffleAlgorithm, defaultValue: 'standard') as String;
    final prefName = p.get(HiveBoxes.kShufflePreference, defaultValue: 'composer') as String;

    state = SettingsState(
      serverUrl: auth.get(HiveBoxes.kServerUrl, defaultValue: Constants.defaultServerUrl) as String,
      username: auth.get(HiveBoxes.kUsername, defaultValue: Constants.defaultUsername) as String,
      password: auth.get(HiveBoxes.kPassword, defaultValue: '') as String,
      shuffleAlgorithm: ShuffleAlgorithm.values.firstWhere(
        (e) => e.name == algoName,
        orElse: () => ShuffleAlgorithm.standard,
      ),
      shufflePreference: ShufflePreference.values.firstWhere(
        (e) => e.name == prefName,
        orElse: () => ShufflePreference.composer,
      ),
      uploadApiUrl: p.get(HiveBoxes.kUploadApiUrl, defaultValue: '') as String,
      uploadDirectory: p.get(HiveBoxes.kUploadDirectory, defaultValue: '/DATA/Media/Music') as String,
      dataCollectionEnabled: p.get(HiveBoxes.kDataCollectionEnabled, defaultValue: true) as bool,
      analyticsUploadSchedule: p.get(HiveBoxes.kAnalyticsUploadSchedule, defaultValue: 'none') as String,
      analyticsLastUpload: p.get(HiveBoxes.kAnalyticsLastUpload) as String?,
    );
  }

  Future<void> saveSettings(String url, String user, String pass, {String? uploadUrl, String? uploadDir}) async {
    final auth = HiveBoxes.auth;
    final p = HiveBoxes.prefs;

    await auth.put(HiveBoxes.kServerUrl, url);
    await auth.put(HiveBoxes.kUsername, user);
    await auth.put(HiveBoxes.kPassword, pass);
    if (uploadUrl != null) await p.put(HiveBoxes.kUploadApiUrl, uploadUrl);
    if (uploadDir != null) await p.put(HiveBoxes.kUploadDirectory, uploadDir);

    state = state.copyWith(
      serverUrl: url,
      username: user,
      password: pass,
      uploadApiUrl: uploadUrl,
      uploadDirectory: uploadDir,
    );
  }

  Future<void> setShuffleAlgorithm(ShuffleAlgorithm algo) async {
    await HiveBoxes.prefs.put(HiveBoxes.kShuffleAlgorithm, algo.name);
    state = state.copyWith(shuffleAlgorithm: algo);
  }

  Future<void> setShufflePreference(ShufflePreference pref) async {
    await HiveBoxes.prefs.put(HiveBoxes.kShufflePreference, pref.name);
    state = state.copyWith(shufflePreference: pref);
  }

  Future<void> setDataCollectionEnabled(bool enabled) async {
    await HiveBoxes.prefs.put(HiveBoxes.kDataCollectionEnabled, enabled);
    state = state.copyWith(dataCollectionEnabled: enabled);
  }

  Future<void> setAnalyticsUploadSchedule(String schedule) async {
    await HiveBoxes.prefs.put(HiveBoxes.kAnalyticsUploadSchedule, schedule);
    state = state.copyWith(analyticsUploadSchedule: schedule);
  }

  Future<void> setAnalyticsLastUpload(String timestamp) async {
    await HiveBoxes.prefs.put(HiveBoxes.kAnalyticsLastUpload, timestamp);
    state = state.copyWith(analyticsLastUpload: timestamp);
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
