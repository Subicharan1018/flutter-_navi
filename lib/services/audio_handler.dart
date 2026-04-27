import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import '../providers/settings_provider.dart';

class AudioHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  List<Song> _currentQueue = [];

  // Kept alive between queue mutations so we can use incremental APIs
  // (add / removeAt / move) instead of rebuilding the entire source.
  ConcatenatingAudioSource? _playlist;

  AudioHandler(this.subsonicService, {AudioPlayer? player})
      : player = player ?? AudioPlayer();

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  AudioSource _toSource(Song song) {
    return AudioSource.uri(
      Uri.parse(subsonicService.getStreamUrl(song.id)),
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer},
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Full rebuild — only called when the entire queue is replaced (setQueue /
  // shuffle).  For incremental changes use addToQueue / removeFromQueue /
  // reorderQueue below.
  // ---------------------------------------------------------------------------
  Future<void> setQueue(List<Song> songs, int startIndex) async {
    _currentQueue = List.from(songs);
    await _rebuildSource(startIndex);
  }

  Future<void> _rebuildSource(int startIndex) async {
    if (_currentQueue.isEmpty) return;
    final sources = _currentQueue.map(_toSource).toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(_playlist!, initialIndex: startIndex);
  }

  // ---------------------------------------------------------------------------
  // Incremental queue mutations — BUG-1 fix
  // These mutate the existing ConcatenatingAudioSource so playback of the
  // current song is never interrupted.
  // ---------------------------------------------------------------------------

  Future<void> addToQueue(Song song) async {
    _currentQueue.add(song);
    if (_playlist != null) {
      await _playlist!.add(_toSource(song));
    } else {
      await _rebuildSource(_currentQueue.length - 1);
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    _currentQueue.removeAt(index);
    if (_playlist != null) {
      await _playlist!.removeAt(index);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length) return;
    if (newIndex < 0 || newIndex >= _currentQueue.length) return;
    final song = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, song);
    if (_playlist != null) {
      await _playlist!.move(oldIndex, newIndex);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates shuffle (keeps current song at index 0)
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final currentSong = _currentQueue[currentIndex];
    final rest = _currentQueue.where((s) => s.id != currentSong.id).toList();
    rest.shuffle();
    _currentQueue = [currentSong, ...rest];
    await _rebuildSource(0); // BUG-13: now properly awaited
  }

  // ---------------------------------------------------------------------------
  // 2. Balanced Shuffle
  //    Groups songs by the user's preferred category (composer or genre) and
  //    interleaves them so the same category never plays back-to-back.
  // ---------------------------------------------------------------------------
  Future<void> spotifyDitherShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Balanced Shuffle ($preference)');

    final currentIndex = player.currentIndex ?? 0;
    final currentSong = _currentQueue[currentIndex];
    final rest = _currentQueue.where((s) => s.id != currentSong.id).toList();

    // Group by preference
    final Map<String, List<Song>> groups = {};
    for (final song in rest) {
      final key = preference == ShufflePreference.composer ? song.composer : song.genre;
      final finalKey = key.isNotEmpty ? key : 'Unknown';
      groups.putIfAbsent(finalKey, () => []).add(song);
    }

    debugPrint('📦 [SHUFFLE] Group Buckets:');
    groups.forEach((category, bucket) {
      debugPrint('  - $category: ${bucket.length} songs');
    });

    // Shuffle each category's bucket internally
    for (final list in groups.values) {
      list.shuffle();
    }

    final List<Song> result = [currentSong];
    List<String> categories = groups.keys.toList()..shuffle();

    // Ensure we don't pick the same category as currentSong if possible in round 1
    final currentKey = preference == ShufflePreference.composer ? currentSong.composer : currentSong.genre;
    final finalCurrentKey = currentKey.isNotEmpty ? currentKey : 'Unknown';

    // Track how far into each category's bucket we are
    final Map<String, int> categoryIndices = {for (final c in categories) c: 0};
    int totalRemaining = rest.length;

    int round = 1;
    while (totalRemaining > 0) {
      for (final category in categories) {
        // Round 1 logic: avoid back-to-back same category if there are other categories
        if (round == 1 && category == finalCurrentKey && categories.length > 1 && result.length == 1) {
          continue;
        }

        final idx = categoryIndices[category]!;
        final bucket = groups[category]!;
        if (idx < bucket.length) {
          final song = bucket[idx];
          result.add(song);
          categoryIndices[category] = idx + 1;
          totalRemaining--;
        }
      }
      categories.shuffle();
      round++;
    }

    _currentQueue = result;
    await _rebuildSource(0); // BUG-13: now properly awaited
  }

  // ---------------------------------------------------------------------------
  // 3. Weighted Shuffle
  //    Each pick is a weighted random draw. Weight is computed from:
  //      - dynamicWeight  (user feedback via Suggest More / Less)
  //      - starred        (×2 multiplier)
  //      - rating         (+0–1 additive bonus, normalised from 1–5)
  //      - playCount      (+0–1 additive bonus, clamped at 100 plays)
  // ---------------------------------------------------------------------------
  Future<void> youtubeWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Weighted Shuffle');

    final currentIndex = player.currentIndex ?? 0;
    final currentSong = _currentQueue[currentIndex];
    final pool = _currentQueue.where((s) => s.id != currentSong.id).toList();

    final List<Song> shuffled = [currentSong];
    final random = Random();

    while (pool.isNotEmpty) {
      // Build weight list
      double totalWeight = 0;
      final List<double> weights = [];

      for (final song in pool) {
        double w = song.dynamicWeight.clamp(0.1, 10.0);
        if (song.starred) w *= 2.0;
        if (song.rating > 0) w += (song.rating - 1) / 4.0; // 0–1 bonus
        w += (song.playCount / 100.0).clamp(0.0, 1.0);
        weights.add(w);
        totalWeight += w;
      }

      // Weighted lottery pick
      double target = random.nextDouble() * totalWeight;
      double cumulative = 0;
      int selectedIndex = pool.length - 1; // fallback to last

      for (int i = 0; i < weights.length; i++) {
        cumulative += weights[i];
        if (cumulative >= target) {
          selectedIndex = i;
          break;
        }
      }

      final selectedSong = pool.removeAt(selectedIndex);
      shuffled.add(selectedSong);
    }

    _currentQueue = shuffled;
    await _rebuildSource(0); // BUG-13: now properly awaited
  }

  // ---------------------------------------------------------------------------
  // Update the dynamic weight of a song in the current queue.
  // suggestMore = true  → increase weight by 50% (max 10.0)
  // suggestMore = false → decrease weight by 50% (min 0.1)
  // ---------------------------------------------------------------------------
  void updateSongWeight(Song song, bool suggestMore) {
    for (int i = 0; i < _currentQueue.length; i++) {
      if (_currentQueue[i].id == song.id) {
        final current = _currentQueue[i].dynamicWeight;
        _currentQueue[i].dynamicWeight = suggestMore
            ? (current * 1.5).clamp(0.1, 10.0)
            : (current * 0.5).clamp(0.1, 10.0);
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------
  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}