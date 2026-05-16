import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

// =============================================================================
// HiveBoxes — Central Hive initialization
//
// Call [HiveBoxes.init()] once from main() before runApp().
// All boxes are opened synchronously during startup so that reads are instant
// throughout the app lifecycle — no async gaps on cold start.
//
// On first launch, any existing SharedPreferences data is migrated into the
// appropriate Hive boxes and then deleted from SharedPreferences.
// =============================================================================

class HiveBoxes {
  static const _authBox = 'auth';
  static const _sessionBox = 'session';
  static const _prefsBox = 'prefs';
  static const _audioBox = 'audio';

  static late Box auth;
  static late Box session;
  static late Box prefs;
  static late Box audio;
  static late Box shuffleCache;

  /// Initialize Hive and open all boxes. Must be called before runApp().
  static Future<void> init() async {
    await Hive.initFlutter();

    // Secure encryption for sensitive data (credentials)
    final encryptionKey = await _getEncryptionKey();

    auth         = await Hive.openBox(_authBox, encryptionCipher: HiveAesCipher(encryptionKey));
    session      = await Hive.openBox(_sessionBox);
    prefs        = await Hive.openBox(_prefsBox);
    audio        = await Hive.openBox(_audioBox);
    shuffleCache = await Hive.openBox('shuffle_cache');

    // One-time migration from SharedPreferences → Hive
    await _migrateFromSharedPreferences();
  }

  static Future<List<int>> _getEncryptionKey() async {
    const storage = FlutterSecureStorage();
    final encodedKey = await storage.read(key: 'hive_encryption_key');
    if (encodedKey == null) {
      final key = Hive.generateSecureKey();
      await storage.write(key: 'hive_encryption_key', value: base64UrlEncode(key));
      return key;
    }
    return base64Url.decode(encodedKey);
  }

  // ---------------------------------------------------------------------------
  // Auth keys
  // ---------------------------------------------------------------------------
  static const kServerUrl = 'serverUrl';
  static const kUsername = 'username';
  static const kPassword = 'password';
  static const kWebdavUsername = 'webdavUsername';
  static const kWebdavPassword = 'webdavPassword';

  // ---------------------------------------------------------------------------
  // Session keys
  // ---------------------------------------------------------------------------
  static const kCurrentTrackId = 'currentTrackId';
  static const kLastPositionMs = 'lastPositionMs';
  static const kLastTimestamp = 'lastTimestamp';

  // ---------------------------------------------------------------------------
  // Prefs keys
  // ---------------------------------------------------------------------------
  static const kShuffleAlgorithm = 'shuffleAlgorithm';
  static const kShufflePreference = 'shufflePreference';
  static const kAutoplayPreference = 'autoplay_enabled';
  static const kUploadApiUrl = 'uploadApiUrl';           // legacy — kept for migration
  static const kListeningApiUrl = 'listeningApiUrl';     // legacy — kept for migration
  static const kApiBaseUrl = 'api_base_url';
  static const kLoggingPort = 'logging_port';
  static const kUploadPort = 'upload_port';
  static const kLocalShufflePort = 'local_shuffle_port';
  static const kUploadDirectory = 'uploadDirectory';
  static const kDataCollectionEnabled = 'dataCollectionEnabled';
  static const kAnalyticsUploadSchedule = 'analytics_upload_schedule';
  static const kAnalyticsLastUpload = 'analytics_last_upload';
  static const kThemeMode = 'theme_mode';
  static const kMeshGradientEnabled = 'mesh_gradient_enabled';
  static const kImageCacheEnabled = 'cache_images_enabled';
  static const kMusicCacheEnabled = 'cache_music_enabled';
  static const kBpmCacheEnabled = 'cache_bpm_enabled';
  static const kSearchHistory = 'search_history';
  static const kRecommendationsEnabled = 'recommendations_enabled';
  static const kAllowHttp = 'allow_http';

  // ---------------------------------------------------------------------------
  // Audio keys
  // ---------------------------------------------------------------------------
  static const kTranscodingEnabled = 'transcoding_enabled';
  static const kSmartSwitchEnabled = 'transcoding_smart_enabled';
  static const kWifiBitrate = 'transcoding_wifi_bitrate';
  static const kMobileBitrate = 'transcoding_mobile_bitrate';
  static const kTranscodeFormat = 'transcoding_format';
  static const kConnectionType = 'transcoding_connection_type';
  static const kReplayGainMode = 'replay_gain_mode';
  static const kPreampGain = 'replay_gain_preamp';
  static const kPreventClipping = 'replay_gain_prevent_clipping';
  static const kFallbackGain = 'replay_gain_fallback';

  // ---------------------------------------------------------------------------
  // One-time migration from SharedPreferences → Hive
  // ---------------------------------------------------------------------------
  static const _kMigrationDone = '_hive_migration_v1_done';

  static Future<void> _migrateFromSharedPreferences() async {
    if (prefs.get(_kMigrationDone) == true) return;

    debugPrint('[Hive] 🔄 Migrating SharedPreferences → Hive...');
    try {
      final sp = await SharedPreferences.getInstance();

      // Auth
      await _migrateString(sp, 'serverUrl', auth, kServerUrl);
      await _migrateString(sp, 'username', auth, kUsername);
      await _migrateString(sp, 'password', auth, kPassword);

      // Prefs
      await _migrateString(sp, 'shuffleAlgorithm', prefs, kShuffleAlgorithm);
      await _migrateString(sp, 'shufflePreference', prefs, kShufflePreference);
      await _migrateString(sp, 'uploadApiUrl', prefs, kUploadApiUrl);
      
      // Migration: listening API defaults to upload API if it wasn't set yet.
      if (!prefs.containsKey(kListeningApiUrl) && prefs.containsKey(kUploadApiUrl)) {
        await prefs.put(kListeningApiUrl, prefs.get(kUploadApiUrl));
      }

      await _migrateString(sp, 'uploadDirectory', prefs, kUploadDirectory);
      await _migrateBool(sp, 'dataCollectionEnabled', prefs, kDataCollectionEnabled);
      await _migrateString(sp, 'analytics_upload_schedule', prefs, kAnalyticsUploadSchedule);
      await _migrateString(sp, 'analytics_last_upload', prefs, kAnalyticsLastUpload);
      await _migrateBool(sp, 'cache_images_enabled', prefs, kImageCacheEnabled);
      await _migrateBool(sp, 'cache_music_enabled', prefs, kMusicCacheEnabled);
      await _migrateBool(sp, 'cache_bpm_enabled', prefs, kBpmCacheEnabled);
      await _migrateBool(sp, 'recommendations_enabled', prefs, kRecommendationsEnabled);

      // Audio — transcoding
      await _migrateBool(sp, 'transcoding_enabled', audio, kTranscodingEnabled);
      await _migrateBool(sp, 'transcoding_smart_enabled', audio, kSmartSwitchEnabled);
      await _migrateInt(sp, 'transcoding_wifi_bitrate', audio, kWifiBitrate);
      await _migrateInt(sp, 'transcoding_mobile_bitrate', audio, kMobileBitrate);
      await _migrateString(sp, 'transcoding_format', audio, kTranscodeFormat);
      await _migrateInt(sp, 'transcoding_connection_type', audio, kConnectionType);

      // Audio — replay gain
      await _migrateInt(sp, 'replay_gain_mode', audio, kReplayGainMode);
      await _migrateDouble(sp, 'replay_gain_preamp', audio, kPreampGain);
      await _migrateBool(sp, 'replay_gain_prevent_clipping', audio, kPreventClipping);
      await _migrateDouble(sp, 'replay_gain_fallback', audio, kFallbackGain);

      // Search history
      final searchHistory = sp.getStringList('search_history');
      if (searchHistory != null) {
        await prefs.put(kSearchHistory, searchHistory);
        await sp.remove('search_history');
      }

      // BPM cache — migrate all bpm_ keys
      for (final key in sp.getKeys()) {
        if (key.startsWith('bpm_')) {
          final val = sp.getInt(key);
          if (val != null) {
            await audio.put(key, val);
            await sp.remove(key);
          }
        }
      }

      await prefs.put(_kMigrationDone, true);
      debugPrint('[Hive] ✅ Migration complete');
    } catch (e) {
      debugPrint('[Hive] ❌ Migration error: $e');
    }
  }

  static Future<void> _migrateString(SharedPreferences sp, String spKey, Box box, String hiveKey) async {
    final val = sp.getString(spKey);
    if (val != null) {
      await box.put(hiveKey, val);
      await sp.remove(spKey);
    }
  }

  static Future<void> _migrateBool(SharedPreferences sp, String spKey, Box box, String hiveKey) async {
    final val = sp.getBool(spKey);
    if (val != null) {
      await box.put(hiveKey, val);
      await sp.remove(spKey);
    }
  }

  static Future<void> _migrateInt(SharedPreferences sp, String spKey, Box box, String hiveKey) async {
    final val = sp.getInt(spKey);
    if (val != null) {
      await box.put(hiveKey, val);
      await sp.remove(spKey);
    }
  }

  static Future<void> _migrateDouble(SharedPreferences sp, String spKey, Box box, String hiveKey) async {
    final val = sp.getDouble(spKey);
    if (val != null) {
      await box.put(hiveKey, val);
      await sp.remove(spKey);
    }
  }
}
