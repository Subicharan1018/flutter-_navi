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

  AudioHandler(this.subsonicService, {AudioPlayer? player})
      : player = player ?? AudioPlayer();

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;

  Future<void> setQueue(List<Song> songs, int startIndex) async {
    _currentQueue = List.from(songs);
    await _updatePlayerSource(startIndex);
  }

  Future<void> _updatePlayerSource(int startIndex) async {
    if (player.audioSource == null && _currentQueue.isEmpty) return; // Basic safety for tests

    final audioSources = _currentQueue.map((song) {
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
    }).toList();

    final playlist = ConcatenatingAudioSource(children: audioSources);
    await player.setAudioSource(playlist, initialIndex: startIndex);
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates shuffle (keeps current song at index 0)
  // ---------------------------------------------------------------------------
  void standardShuffle() {
    if (_currentQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final currentSong = _currentQueue[currentIndex];
    final rest = _currentQueue.where((s) => s.id != currentSong.id).toList();
    rest.shuffle();
    _currentQueue = [currentSong, ...rest];
    _updatePlayerSource(0);
  }

  // ---------------------------------------------------------------------------
  // 2. Balanced Shuffle
  //    Groups songs by the user's preferred category (composer or genre) and
  //    interleaves them so the same category never plays back-to-back.
  // ---------------------------------------------------------------------------
  void spotifyDitherShuffle(ShufflePreference preference) {
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
    _updatePlayerSource(0);
  }

  // ---------------------------------------------------------------------------
  // 3. Weighted Shuffle
  //    Each pick is a weighted random draw. Weight is computed from:
  //      - dynamicWeight  (user feedback via Suggest More / Less)
  //      - starred        (×2 multiplier)
  //      - rating         (+0–1 additive bonus, normalised from 1–5)
  //      - playCount      (+0–1 additive bonus, clamped at 100 plays)
  // ---------------------------------------------------------------------------
  void youtubeWeightedShuffle() {
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
    _updatePlayerSource(0);
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
}