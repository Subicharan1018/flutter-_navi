import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/constants.dart';
import '../core/hive_boxes.dart';
import '../services/subsonic_service.dart';
import '../services/playlist_cache_service.dart';
import '../services/listening_event_collector.dart';
import '../services/cache_settings_service.dart';
import '../services/bpm_analyzer_service.dart';
import '../services/playback_tuning.dart';

import '../services/transcoding_service.dart';
import '../services/recommendation_service.dart';
import '../services/search_history_service.dart';
import '../database/app_database.dart';

// ---------------------------------------------------------------------------
// Shuffle Algorithm enum
// ---------------------------------------------------------------------------
enum ShuffleAlgorithm {
  /// Basic Fisher-Yates random shuffle.
  standard,

  /// Dithered Position Shuffle: assigns each song a floating-point position
  /// score (evenly spaced per group + random offset + small dither), then
  /// sorts globally. Guarantees same-category songs are maximally spread with
  /// no back-to-back leak — replaces the old round-robin balanced shuffle.
  spotify,

  /// YouTube-style weighted lottery: songs with higher play-counts, ratings,
  /// stars, or positive "Suggest More" feedback appear more often.
  /// Uses Efraimidis-Spirakis key trick — O(n log n), not O(n²).
  youtube,

  /// Album-Aware Shuffle: shuffles albums as atomic units so the internal
  /// track order of each album is preserved, but albums play in random order.
  albumAware,

  /// Merge-Shuffle: proven-optimal interleaving (Ruud van Asseldonk, 2023).
  /// Guarantees same-category songs are never consecutive when avoidable.
  mergeShuffle,

  /// Recency-Dampened Weighted Shuffle: like youtube but songs played
  /// recently in this session receive a 10× weight penalty, preventing
  /// repeats during long listening sessions.
  recencyDampened,

  /// Smart Shuffle via shuffle.subimusic.me — queries the hosted AI server
  /// for intelligent, context-aware song recommendations using the user's
  /// personal Navidrome listening history and real-time weather/time context.
  smartLocal,
}

// ---------------------------------------------------------------------------
// Shuffle Preference enum
// ---------------------------------------------------------------------------
enum ShufflePreference { composer, genre }

// ---------------------------------------------------------------------------
// Settings state
// ---------------------------------------------------------------------------
class SettingsState {
  final String serverUrl;
  final String username;
  final String password;
  final String webdavUsername;
  final String webdavPassword;
  final ShuffleAlgorithm shuffleAlgorithm;
  final ShufflePreference shufflePreference;

  /// Base URL for the WebDAV upload service.
  final String webdavUrl;

  final String uploadDirectory;

  /// When false the [ListeningEventCollector] is a no-op — no rows written.
  final bool dataCollectionEnabled;
  final String analyticsUploadSchedule; // 'none', 'weekly', 'monthly'
  final String? analyticsLastUpload;

  final bool allowHttp;

  /// When false the Now Playing artwork field stays still (no drift).
  /// Useful on low-end devices to save GPU and battery.
  final bool fluidBgEnabled;

  /// Volume normalisation from the file's ReplayGain tags.
  final ReplayGainMode replayGainMode;

  /// Fade length between tracks in seconds; 0 keeps playback gapless.
  final int crossfadeSeconds;

  /// Playback rate, 0.5–2.0.
  final double playbackSpeed;

  const SettingsState({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.webdavUsername = '',
    this.webdavPassword = '',
    this.shuffleAlgorithm = ShuffleAlgorithm.standard,
    this.shufflePreference = ShufflePreference.composer,
    this.webdavUrl = '',
    this.uploadDirectory = '',
    this.dataCollectionEnabled = true,
    this.analyticsUploadSchedule = 'none',
    this.analyticsLastUpload,
    this.allowHttp = false,
    this.fluidBgEnabled = true,
    this.replayGainMode = ReplayGainMode.off,
    this.crossfadeSeconds = 0,
    this.playbackSpeed = 1.0,
  });

  // ── Computed URL getters — single source of truth ───────────────────────────

  /// Full URL for the logging/telemetry service.
  String get loggingApiUrl => 'https://shuffle.subimusic.me';

  /// Full URL for the WebDAV/upload service.
  String get uploadApiUrl => webdavUrl;

  /// Full URL for the local shuffle model server.
  String get localShuffleUrl => 'https://shuffle.subimusic.me';

  SettingsState copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? webdavUsername,
    String? webdavPassword,
    ShuffleAlgorithm? shuffleAlgorithm,
    ShufflePreference? shufflePreference,
    String? webdavUrl,
    String? uploadDirectory,
    bool? dataCollectionEnabled,
    String? analyticsUploadSchedule,
    String? analyticsLastUpload,
    bool? allowHttp,
    bool? fluidBgEnabled,
    ReplayGainMode? replayGainMode,
    int? crossfadeSeconds,
    double? playbackSpeed,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      shuffleAlgorithm: shuffleAlgorithm ?? this.shuffleAlgorithm,
      shufflePreference: shufflePreference ?? this.shufflePreference,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      uploadDirectory: uploadDirectory ?? this.uploadDirectory,
      dataCollectionEnabled:
          dataCollectionEnabled ?? this.dataCollectionEnabled,
      analyticsUploadSchedule:
          analyticsUploadSchedule ?? this.analyticsUploadSchedule,
      analyticsLastUpload: analyticsLastUpload ?? this.analyticsLastUpload,
      allowHttp: allowHttp ?? this.allowHttp,
      fluidBgEnabled: fluidBgEnabled ?? this.fluidBgEnabled,
      replayGainMode: replayGainMode ?? this.replayGainMode,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }
}

// ---------------------------------------------------------------------------
// Settings notifier — uses Hive for instant sync reads
// ---------------------------------------------------------------------------
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier()
    : super(const SettingsState(serverUrl: '', username: '', password: '')) {
    _loadFromHive();
  }

  void _loadFromHive() {
    final auth = HiveBoxes.auth;
    final p = HiveBoxes.prefs;

    final algoName =
        p
            .get(HiveBoxes.kShuffleAlgorithm, defaultValue: 'standard')
            ?.toString() ??
        'standard';
    final prefName =
        p
            .get(HiveBoxes.kShufflePreference, defaultValue: 'composer')
            ?.toString() ??
        'composer';

    String getString(dynamic box, String key, String defaultValue) {
      final val = box.get(key)?.toString() ?? '';
      return val.isEmpty ? defaultValue : val;
    }

    String webdavUrl = p.get(HiveBoxes.kWebdavUrl)?.toString() ?? '';

    state = SettingsState(
      serverUrl: getString(
        auth,
        HiveBoxes.kServerUrl,
        Constants.defaultServerUrl,
      ),
      username: getString(auth, HiveBoxes.kUsername, Constants.defaultUsername),
      password: auth.get(HiveBoxes.kPassword)?.toString() ?? '',
      webdavUsername: auth.get(HiveBoxes.kWebdavUsername)?.toString() ?? '',
      webdavPassword: auth.get(HiveBoxes.kWebdavPassword)?.toString() ?? '',
      shuffleAlgorithm: ShuffleAlgorithm.values.firstWhere(
        (e) => e.name == algoName,
        orElse: () => ShuffleAlgorithm.standard,
      ),
      shufflePreference: ShufflePreference.values.firstWhere(
        (e) => e.name == prefName,
        orElse: () => ShufflePreference.composer,
      ),
      webdavUrl: webdavUrl,
      uploadDirectory: p.get(HiveBoxes.kUploadDirectory)?.toString() ?? '',
      dataCollectionEnabled:
          p.get(HiveBoxes.kDataCollectionEnabled, defaultValue: true) is bool
          ? p.get(HiveBoxes.kDataCollectionEnabled, defaultValue: true) as bool
          : true,
      analyticsUploadSchedule:
          p
              .get(HiveBoxes.kAnalyticsUploadSchedule, defaultValue: 'none')
              ?.toString() ??
          'none',
      analyticsLastUpload: p.get(HiveBoxes.kAnalyticsLastUpload)?.toString(),
      allowHttp: p.get(HiveBoxes.kAllowHttp, defaultValue: false) == true,
      fluidBgEnabled:
          p.get(HiveBoxes.kFluidBgEnabled, defaultValue: true) is bool
          ? p.get(HiveBoxes.kFluidBgEnabled, defaultValue: true) as bool
          : true,
      replayGainMode: ReplayGainMode.values.firstWhere(
        (e) => e.name == p.get(HiveBoxes.kReplayGainMode)?.toString(),
        orElse: () => ReplayGainMode.off,
      ),
      crossfadeSeconds: clampCrossfadeSeconds(
        p.get(HiveBoxes.kCrossfadeSeconds) is num
            ? (p.get(HiveBoxes.kCrossfadeSeconds) as num).round()
            : 0,
      ),
      playbackSpeed: clampPlaybackSpeed(
        p.get(HiveBoxes.kPlaybackSpeed) is num
            ? (p.get(HiveBoxes.kPlaybackSpeed) as num).toDouble()
            : 1.0,
      ),
    );
  }

  Future<void> saveSettings(
    String url,
    String user,
    String pass, {
    String? webdavUrl,
    String? uploadDir,
    String? webdavUser,
    String? webdavPass,
  }) async {
    final auth = HiveBoxes.auth;
    final p = HiveBoxes.prefs;

    await auth.put(HiveBoxes.kServerUrl, url);
    await auth.put(HiveBoxes.kUsername, user);
    await auth.put(HiveBoxes.kPassword, pass);
    if (webdavUser != null) {
      await auth.put(HiveBoxes.kWebdavUsername, webdavUser);
    }
    if (webdavPass != null) {
      await auth.put(HiveBoxes.kWebdavPassword, webdavPass);
    }
    if (webdavUrl != null) await p.put(HiveBoxes.kWebdavUrl, webdavUrl);
    if (uploadDir != null) await p.put(HiveBoxes.kUploadDirectory, uploadDir);

    state = state.copyWith(
      serverUrl: url,
      username: user,
      password: pass,
      webdavUsername: webdavUser,
      webdavPassword: webdavPass,
      webdavUrl: webdavUrl,
      uploadDirectory: uploadDir,
    );
  }

  Future<void> setWebdavUrl(String url) async {
    await HiveBoxes.prefs.put(HiveBoxes.kWebdavUrl, url);
    state = state.copyWith(webdavUrl: url);
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

  Future<void> setAllowHttp(bool allow) async {
    await HiveBoxes.prefs.put(HiveBoxes.kAllowHttp, allow);
    state = state.copyWith(allowHttp: allow);
  }

  /// Persists and applies the fluid background toggle.
  Future<void> setFluidBgEnabled(bool enabled) async {
    await HiveBoxes.prefs.put(HiveBoxes.kFluidBgEnabled, enabled);
    state = state.copyWith(fluidBgEnabled: enabled);
  }

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    await HiveBoxes.prefs.put(HiveBoxes.kReplayGainMode, mode.name);
    state = state.copyWith(replayGainMode: mode);
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    final clamped = clampCrossfadeSeconds(seconds);
    await HiveBoxes.prefs.put(HiveBoxes.kCrossfadeSeconds, clamped);
    state = state.copyWith(crossfadeSeconds: clamped);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = clampPlaybackSpeed(speed);
    await HiveBoxes.prefs.put(HiveBoxes.kPlaybackSpeed, clamped);
    state = state.copyWith(playbackSpeed: clamped);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);


/// Singleton [AppDatabase] — central Drift instance for the app.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Singleton [PlaylistCacheService] — created once, shared across the app.
final playlistCacheServiceProvider = Provider<PlaylistCacheService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PlaylistCacheService(db);
});

/// Narrow provider that surfaces only the three fields that control which
/// [SubsonicService] instance we need.
final _credentialsProvider =
    Provider<({String serverUrl, String username, String password})>((ref) {
      final s = ref.watch(settingsProvider);
      return (
        serverUrl: s.serverUrl,
        username: s.username,
        password: s.password,
      );
    });

final subsonicServiceProvider = Provider<SubsonicService>((ref) {
  final creds = ref.watch(_credentialsProvider);
  final cache = ref.watch(playlistCacheServiceProvider);
  final settings = ref.read(settingsProvider);
  final uploadUrl = settings.uploadApiUrl; // computed getter: base + uploadPort
  final service = SubsonicService(
    serverUrl: creds.serverUrl,
    username: creds.username,
    password: creds.password,
    cache: cache,
    customUploadUrl: uploadUrl.isEmpty ? null : uploadUrl,
    customUploadDir: settings.uploadDirectory.isEmpty
        ? null
        : settings.uploadDirectory,
    webdavUsername: settings.webdavUsername.isEmpty
        ? null
        : settings.webdavUsername,
    webdavPassword: settings.webdavPassword.isEmpty
        ? null
        : settings.webdavPassword,
  );

  ref.onDispose(service.dispose);
  return service;
});

/// Singleton [ListeningEventCollector] — one instance for the app's lifetime.
final listenerCollectorProvider = Provider<ListeningEventCollector>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final collector = ListeningEventCollector(db);
  ref.onDispose(() => collector.dispose());
  return collector;
});

// ---------------------------------------------------------------------------
// New feature providers
// ---------------------------------------------------------------------------

class CacheSettings {
  final bool imageCacheEnabled;
  final bool musicCacheEnabled;
  final bool bpmCacheEnabled;

  const CacheSettings({
    required this.imageCacheEnabled,
    required this.musicCacheEnabled,
    required this.bpmCacheEnabled,
  });
}

class CacheSettingsNotifier extends Notifier<CacheSettings> {
  @override
  CacheSettings build() {
    final service = CacheSettingsService();
    return CacheSettings(
      imageCacheEnabled: service.getImageCacheEnabled(),
      musicCacheEnabled: service.getMusicCacheEnabled(),
      bpmCacheEnabled: service.getBpmCacheEnabled(),
    );
  }

  Future<void> setImageCacheEnabled(bool enabled) async {
    await CacheSettingsService().setImageCacheEnabled(enabled);
    state = CacheSettings(
      imageCacheEnabled: enabled,
      musicCacheEnabled: state.musicCacheEnabled,
      bpmCacheEnabled: state.bpmCacheEnabled,
    );
  }

  Future<void> setMusicCacheEnabled(bool enabled) async {
    await CacheSettingsService().setMusicCacheEnabled(enabled);
    state = CacheSettings(
      imageCacheEnabled: state.imageCacheEnabled,
      musicCacheEnabled: enabled,
      bpmCacheEnabled: state.bpmCacheEnabled,
    );
  }

  Future<void> setBpmCacheEnabled(bool enabled) async {
    await CacheSettingsService().setBpmCacheEnabled(enabled);
    state = CacheSettings(
      imageCacheEnabled: state.imageCacheEnabled,
      musicCacheEnabled: state.musicCacheEnabled,
      bpmCacheEnabled: enabled,
    );
  }
}

final cacheSettingsNotifierProvider = NotifierProvider<CacheSettingsNotifier, CacheSettings>(
  CacheSettingsNotifier.new,
);

/// Singleton [CacheSettingsService] — manages image/music/BPM cache toggles.
final cacheSettingsProvider = Provider<CacheSettingsService>((ref) {
  return CacheSettingsService();
});

/// Singleton [BpmAnalyzerService] — BPM estimation and caching.
final bpmAnalyzerProvider = Provider<BpmAnalyzerService>((ref) {
  return BpmAnalyzerService();
});



/// [TranscodingService] — network-aware bitrate/format management.
final transcodingProvider = ChangeNotifierProvider<TranscodingService>((ref) {
  final service = TranscodingService();
  ref.onDispose(service.dispose);
  return service;
});

/// [RecommendationService] — play pattern tracking and personalised feeds.
/// MEM-OPT: initialize() is NOT called here. The service lazy-loads its data
/// from SharedPreferences on the first call to trackSongPlay() or setEnabled().
/// This avoids decoding 500 profiles into memory at app startup when the user
/// never visits the Made For You screen.
final recommendationProvider = ChangeNotifierProvider<RecommendationService>((
  ref,
) {
  return RecommendationService();
});

/// Singleton [SearchHistoryService].
final searchHistoryServiceProvider = Provider<SearchHistoryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SearchHistoryService(db);
});
