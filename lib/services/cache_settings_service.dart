import '../core/hive_boxes.dart';

class CacheSettingsService {
  static final CacheSettingsService _instance =
      CacheSettingsService._internal();
  factory CacheSettingsService() => _instance;
  CacheSettingsService._internal();

  /// No-op — Hive boxes are already open from main(). Kept for API compat.
  Future<void> initialize() async {}

  Future<void> setImageCacheEnabled(bool enabled) async {
    await HiveBoxes.prefs.put(HiveBoxes.kImageCacheEnabled, enabled);
  }

  bool getImageCacheEnabled() {
    final val = HiveBoxes.prefs.get(HiveBoxes.kImageCacheEnabled, defaultValue: true);
    return val is bool ? val : true;
  }

  Future<void> setMusicCacheEnabled(bool enabled) async {
    await HiveBoxes.prefs.put(HiveBoxes.kMusicCacheEnabled, enabled);
  }

  bool getMusicCacheEnabled() {
    final val = HiveBoxes.prefs.get(HiveBoxes.kMusicCacheEnabled, defaultValue: true);
    return val is bool ? val : true;
  }

  Future<void> setBpmCacheEnabled(bool enabled) async {
    await HiveBoxes.prefs.put(HiveBoxes.kBpmCacheEnabled, enabled);
  }

  bool getBpmCacheEnabled() {
    final val = HiveBoxes.prefs.get(HiveBoxes.kBpmCacheEnabled, defaultValue: true);
    return val is bool ? val : true;
  }

  Future<void> disableAllCaches() async {
    await Future.wait([
      setImageCacheEnabled(false),
      setMusicCacheEnabled(false),
      setBpmCacheEnabled(false),
    ]);
  }

  Future<void> enableAllCaches() async {
    await Future.wait([
      setImageCacheEnabled(true),
      setMusicCacheEnabled(true),
      setBpmCacheEnabled(true),
    ]);
  }

  bool areAllCachesDisabled() {
    return !getImageCacheEnabled() &&
        !getMusicCacheEnabled() &&
        !getBpmCacheEnabled();
  }

  bool areAllCachesEnabled() {
    return getImageCacheEnabled() &&
        getMusicCacheEnabled() &&
        getBpmCacheEnabled();
  }
}
