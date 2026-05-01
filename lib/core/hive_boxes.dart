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

  /// Initialize Hive and open all boxes. Must be called before runApp().
  static Future<void> init() async {
    await Hive.initFlutter();

    // Secure encryption for sensitive data (credentials)
    final encryptionKey = await _getEncryptionKey();

    auth    = await Hive.openBox(_authBox, encryptionCipher: HiveAesCipher(encryptionKey));
    session = await Hive.openBox(_sessionBox);
    prefs   = await Hive.openBox(_prefsBox);
    audio   = await Hive.openBox(_audioBox);

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
  static const kUploadApiUrl = 'uploadApiUrl';
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
      _migrateString(sp, 'serverUrl', auth, kServerUrl);
      _migrateString(sp, 'username', auth, kUsername);
      _migrateString(sp, 'password', auth, kPassword);

      // Prefs
      _migrateString(sp, 'shuffleAlgorithm', prefs, kShuffleAlgorithm);
      _migrateString(sp, 'shufflePreference', prefs, kShufflePreference);
      _migrateString(sp, 'uploadApiUrl', prefs, kUploadApiUrl);
      _migrateString(sp, 'uploadDirectory', prefs, kUploadDirectory);
      _migrateBool(sp, 'dataCollectionEnabled', prefs, kDataCollectionEnabled);
      _migrateString(sp, 'analytics_upload_schedule', prefs, kAnalyticsUploadSchedule);
      _migrateString(sp, 'analytics_last_upload', prefs, kAnalyticsLastUpload);
      _migrateBool(sp, 'cache_images_enabled', prefs, kImageCacheEnabled);
      _migrateBool(sp, 'cache_music_enabled', prefs, kMusicCacheEnabled);
      _migrateBool(sp, 'cache_bpm_enabled', prefs, kBpmCacheEnabled);
      _migrateBool(sp, 'recommendations_enabled', prefs, kRecommendationsEnabled);

      // Audio — transcoding
      _migrateBool(sp, 'transcoding_enabled', audio, kTranscodingEnabled);
      _migrateBool(sp, 'transcoding_smart_enabled', audio, kSmartSwitchEnabled);
      _migrateInt(sp, 'transcoding_wifi_bitrate', audio, kWifiBitrate);
      _migrateInt(sp, 'transcoding_mobile_bitrate', audio, kMobileBitrate);
      _migrateString(sp, 'transcoding_format', audio, kTranscodeFormat);
      _migrateInt(sp, 'transcoding_connection_type', audio, kConnectionType);

      // Audio — replay gain
      _migrateInt(sp, 'replay_gain_mode', audio, kReplayGainMode);
      _migrateDouble(sp, 'replay_gain_preamp', audio, kPreampGain);
      _migrateBool(sp, 'replay_gain_prevent_clipping', audio, kPreventClipping);
      _migrateDouble(sp, 'replay_gain_fallback', audio, kFallbackGain);

      // Search history
      final searchHistory = sp.getStringList('search_history');
      if (searchHistory != null) {
        await prefs.put(kSearchHistory, searchHistory);
      }

      // BPM cache — migrate all bpm_ keys
      for (final key in sp.getKeys()) {
        if (key.startsWith('bpm_')) {
          final val = sp.getInt(key);
          if (val != null) await audio.put(key, val);
        }
      }

      await prefs.put(_kMigrationDone, true);
      debugPrint('[Hive] ✅ Migration complete');
    } catch (e) {
      debugPrint('[Hive] ❌ Migration error: $e');
    }
  }

  static void _migrateString(SharedPreferences sp, String spKey, Box box, String hiveKey) {
    final val = sp.getString(spKey);
    if (val != null) box.put(hiveKey, val);
  }

  static void _migrateBool(SharedPreferences sp, String spKey, Box box, String hiveKey) {
    final val = sp.getBool(spKey);
    if (val != null) box.put(hiveKey, val);
  }

  static void _migrateInt(SharedPreferences sp, String spKey, Box box, String hiveKey) {
    final val = sp.getInt(spKey);
    if (val != null) box.put(hiveKey, val);
  }

  static void _migrateDouble(SharedPreferences sp, String spKey, Box box, String hiveKey) {
    final val = sp.getDouble(spKey);
    if (val != null) box.put(hiveKey, val);
  }
}
