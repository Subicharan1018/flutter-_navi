import 'package:flutter/foundation.dart';
import '../core/hive_boxes.dart';
import '../models/song.dart';
import 'cache_settings_service.dart';

class BpmAnalyzerService {
  static final BpmAnalyzerService _instance = BpmAnalyzerService._internal();
  factory BpmAnalyzerService() => _instance;
  BpmAnalyzerService._internal();

  bool _isInitialized = false;
  final _cacheSettings = CacheSettingsService();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _cacheSettings.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing BPM analyzer: $e');
    }
  }

  Future<int> getBPM(Song song, String audioUrl) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_cacheSettings.getBpmCacheEnabled()) {
      final cachedBPM = _getCachedBPM(song.id);
      if (cachedBPM != null) {
        return cachedBPM;
      }
    }

    final estimatedBPM = _estimateBPMFromGenre(song);

    if (_cacheSettings.getBpmCacheEnabled()) {
      await _cacheBPM(song.id, estimatedBPM);
    }

    return estimatedBPM;
  }

  int? _getCachedBPM(String songId) {
    return HiveBoxes.audio.get('bpm_$songId') as int?;
  }

  Future<void> _cacheBPM(String songId, int bpm) async {
    await HiveBoxes.audio.put('bpm_$songId', bpm);
  }

  int _estimateBPMFromGenre(Song song) {
    final genre = song.genre.toLowerCase();

    if (genre.contains('electronic') ||
        genre.contains('edm') ||
        genre.contains('techno') ||
        genre.contains('house')) {
      return 128;
    } else if (genre.contains('hip hop') ||
        genre.contains('rap') ||
        genre.contains('trap')) {
      return 85;
    } else if (genre.contains('rock') || genre.contains('metal')) {
      return 120;
    } else if (genre.contains('jazz') || genre.contains('blues')) {
      return 90;
    } else if (genre.contains('classical') || genre.contains('orchestra')) {
      return 100;
    } else if (genre.contains('reggae') || genre.contains('dub')) {
      return 75;
    } else if (genre.contains('country') || genre.contains('folk')) {
      return 95;
    } else if (genre.contains('disco') || genre.contains('funk')) {
      return 115;
    } else if (genre.contains('pop')) {
      return 110;
    } else if (genre.contains('ballad') || genre.contains('slow')) {
      return 70;
    }

    final duration = song.duration;
    if (duration < 120) {
      return 140;
    } else if (duration > 300) {
      return 80;
    }

    return 100;
  }

  Future<void> clearCache() async {
    final box = HiveBoxes.audio;
    final bpmKeys = box.keys
        .where((k) => k.toString().startsWith('bpm_'))
        .toList();
    for (final key in bpmKeys) {
      await box.delete(key);
    }
  }

  Future<void> cacheAllBPM(
    List<Song> songs, {
    Function(int current, int total)? onProgress,
    Function(Song song, int bpm)? onSongCached,
    VoidCallback? onCompleted,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final total = songs.length;
    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];

      if (_getCachedBPM(song.id) != null) {
        onProgress?.call(i + 1, total);
        continue;
      }

      final bpm = _estimateBPMFromGenre(song);
      await _cacheBPM(song.id, bpm);

      onProgress?.call(i + 1, total);
      onSongCached?.call(song, bpm);
    }

    onCompleted?.call();
  }

  int getCachedCount() {
    return HiveBoxes.audio.keys
        .where((k) => k.toString().startsWith('bpm_'))
        .length;
  }

  bool isCached(String songId) {
    return _getCachedBPM(songId) != null;
  }
}
