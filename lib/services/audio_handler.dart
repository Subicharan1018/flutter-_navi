import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/song.dart';
import 'subsonic_service.dart';
import 'replay_gain_service.dart';
import '../providers/settings_provider.dart';
import '../offline_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// ISOLATE RULES — same as before, unchanged
// ---------------------------------------------------------------------------

double _songWeight(Song song) {
  double w = song.dynamicWeight.clamp(0.1, 10.0);
  if (song.starred) w *= 2.0;
  if (song.rating > 0) w += (song.rating - 1) / 4.0;
  w += (song.playCount / 100.0).clamp(0.0, 1.0);
  return w;
}

// ---------------------------------------------------------------------------
// ALGORITHM 1 — Standard Fisher-Yates
// ---------------------------------------------------------------------------
List<Song> _standardShuffleIsolate(List<Song> rest) {
  rest.shuffle();
  return rest;
}

// ---------------------------------------------------------------------------
// ALGORITHM 2 — Dithered Position Shuffle
// ---------------------------------------------------------------------------
List<Song> _ditheredPositionShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();
  final int total = songs.length;

  final Map<String, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : 'Unknown', () => []).add(song);
  }
  for (final list in groups.values) {
    list.shuffle(random);
  }

  final List<MapEntry<Song, double>> scored = [];
  for (final bucket in groups.values) {
    final double spacing = total / bucket.length.toDouble();
    final double offset = random.nextDouble() * spacing;
    for (int i = 0; i < bucket.length; i++) {
      final double dither = (random.nextDouble() - 0.5) * spacing * 0.1;
      final double position = offset + (i * spacing) + dither;
      scored.add(MapEntry(bucket[i], position));
    }
  }
  scored.sort((a, b) => a.value.compareTo(b.value));
  return scored.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 3 — Merge-Shuffle
// ---------------------------------------------------------------------------
List<Song> _interleave(List<Song> larger, List<Song> smaller, Random random) {
  if (larger.length < smaller.length)
    return _interleave(smaller, larger, random);
  if (smaller.isEmpty) return larger;
  if (larger.isEmpty) return smaller;

  final int n = larger.length;
  final int m = smaller.length;
  final List<Song> result = [];
  int largerIndex = 0;
  final double partSize = n / (m + 1);

  for (int i = 0; i < m; i++) {
    final int end = ((i + 1) * partSize).round().clamp(largerIndex, n);
    result.addAll(larger.sublist(largerIndex, end));
    result.add(smaller[i]);
    largerIndex = end;
  }
  if (largerIndex < n) result.addAll(larger.sublist(largerIndex));
  return result;
}

List<Song> _mergeShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final prefIndex = args['pref'] as int;
  final preference = ShufflePreference.values[prefIndex];
  final random = Random();

  final Map<String, List<Song>> groups = {};
  for (final song in songs) {
    final key = preference == ShufflePreference.composer
        ? song.composer
        : song.genre;
    groups.putIfAbsent(key.isNotEmpty ? key : 'Unknown', () => []).add(song);
  }
  for (final list in groups.values) {
    list.shuffle(random);
  }

  final buckets = groups.values.toList()
    ..sort((a, b) => a.length.compareTo(b.length));
  if (buckets.isEmpty) return songs;

  List<Song> result = List<Song>.from(buckets[0]);
  for (int i = 1; i < buckets.length; i++) {
    result = _interleave(result, List<Song>.from(buckets[i]), random);
  }
  return result;
}

// ---------------------------------------------------------------------------
// ALGORITHM 4 — Weighted Shuffle (Efraimidis-Spirakis)
// ---------------------------------------------------------------------------
List<Song> _weightedShuffleIsolate(List<Song> pool) {
  final random = Random();
  final keyed = pool.map((song) {
    final w = _songWeight(song);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    final key = exp(log(r) / w);
    return MapEntry(song, key);
  }).toList();
  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 5 — Album-Aware Shuffle
// ---------------------------------------------------------------------------
List<Song> _albumAwareShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final shuffleTracks = args['shuffleTracks'] as bool? ?? false;
  final random = Random();

  final Map<String, List<Song>> albums = {};
  for (final song in songs) {
    final key = song.album.isNotEmpty ? song.album : 'Unknown';
    albums.putIfAbsent(key, () => []).add(song);
  }
  for (final list in albums.values) {
    if (shuffleTracks) {
      list.shuffle(random);
    } else {
      list.sort((a, b) => a.track.compareTo(b.track));
    }
  }
  final albumKeys = albums.keys.toList()..shuffle(random);
  return albumKeys.expand((key) => albums[key]!).toList();
}

// ---------------------------------------------------------------------------
// ALGORITHM 6 — Recency-Dampened Weighted Shuffle
// ---------------------------------------------------------------------------
List<Song> _recencyDampenedShuffleIsolate(Map<String, dynamic> args) {
  final songs = List<Song>.from(args['songs'] as List<Song>);
  final recentIds = Set<String>.from(args['recentIds'] as List);
  final random = Random();

  final keyed = songs.map((song) {
    double w = _songWeight(song);
    if (recentIds.contains(song.id)) w *= 0.1;
    w = w.clamp(0.01, 100.0);
    final r = random.nextDouble().clamp(1e-10, 1.0);
    final key = exp(log(r) / w);
    return MapEntry(song, key);
  }).toList();
  keyed.sort((a, b) => b.value.compareTo(a.value));
  return keyed.map((e) => e.key).toList();
}

// ---------------------------------------------------------------------------
// AudioHandler
// ---------------------------------------------------------------------------

class AudioHandler {
  final AudioPlayer player;
  final SubsonicService subsonicService;
  final ReplayGainService _replayGainService;
  List<Song> _currentQueue = [];
  List<Song> _unshuffledQueue = [];
  ConcatenatingAudioSource? _playlist;

  static const int _recencyWindow = 20;
  final Set<String> _recentlyPlayedIds = {};

  // FIX-PERF-1: Cache the smart local server base URL so it doesn't get
  // reconstructed on every call.
  static const String _smartLocalBase = 'http://100.99.105.51:5000';

  AudioHandler(
    this.subsonicService, {
    AudioPlayer? player,
    ReplayGainService? replayGainService,
  }) : player = player ?? AudioPlayer(),
       _replayGainService = replayGainService ?? ReplayGainService() {
    this.player.currentIndexStream.listen((index) {
      if (index != null && index < _currentQueue.length) {
        _trackRecentlyPlayed(_currentQueue[index].id);
      }
    });

    this.player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace stackTrace) {
        debugPrint('❌ [AudioHandler] Stream error: $e');
        if (e is PlayerException) {
          debugPrint('   Code: ${e.code}  Message: ${e.message}');
        }
      },
    );

    this.player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          debugPrint('ℹ️ [AudioHandler] Processing state: completed');
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('❌ [AudioHandler] Player state error: $e');
      },
    );
  }

  @visibleForTesting
  set currentQueue(List<Song> songs) => _currentQueue = songs;

  List<Song> get currentQueue => _currentQueue;
  List<Song> get unshuffledQueue => _unshuffledQueue;

  void _trackRecentlyPlayed(String songId) {
    _recentlyPlayedIds.add(songId);
    if (_recentlyPlayedIds.length > _recencyWindow) {
      _recentlyPlayedIds.remove(_recentlyPlayedIds.first);
    }
  }

  AudioSource _toSource(Song song) {
    final localPath = OfflineService().getLocalPath(song.id);
    final streamUri = localPath != null
        ? Uri.parse('file://$localPath')
        : Uri.parse(subsonicService.getStreamUrl(song.id));

    return AudioSource.uri(
      streamUri,
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': localPath != null},
      ),
    );
  }

  // BUG-7 FIX: Overload that takes a pre-computed offline path map to avoid
  // per-song synchronous Hive lookups during batch source building.
  AudioSource _toSourceWithPaths(Song song, Map<String, String?> offlinePaths) {
    final localPath = offlinePaths[song.id];
    final streamUri = localPath != null
        ? Uri.parse('file://$localPath')
        : Uri.parse(subsonicService.getStreamUrl(song.id));

    return AudioSource.uri(
      streamUri,
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': localPath != null},
      ),
    );
  }

  /// BUG-7 FIX: Pre-compute all offline paths in a single pass through the
  /// Hive box, eliminating O(n) individual lookups during source building.
  Map<String, String?> _precomputeOfflinePaths(List<Song> songs) {
    final offline = OfflineService();
    return {for (final song in songs) song.id: offline.getLocalPath(song.id)};
  }

  Future<void> setQueue(
    List<Song> songs,
    int startIndex, {
    List<Song>? unshuffledSongs,
  }) async {
    _currentQueue = List.from(songs);
    _unshuffledQueue = List.from(unshuffledSongs ?? songs);
    await _rebuildSource(startIndex);
    _applyReplayGain();
  }

  void _applyReplayGain() {
    final multiplier = _replayGainService.calculateVolumeMultiplier();
    player.setVolume(multiplier);
  }

  void refreshReplayGain() => _applyReplayGain();

  Future<void> _rebuildSource(
    int startIndex, {
    Duration? initialPosition,
  }) async {
    if (_currentQueue.isEmpty) return;
    final savedLoopMode = player.loopMode;
    // BUG-7 FIX: Pre-compute offline paths to avoid per-song File.existsSync() calls.
    final offlinePaths = _precomputeOfflinePaths(_currentQueue);
    final sources = _currentQueue
        .map((song) => _toSourceWithPaths(song, offlinePaths))
        .toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(
      _playlist!,
      initialIndex: startIndex,
      initialPosition: initialPosition,
    );
    if (savedLoopMode != LoopMode.off) {
      await player.setLoopMode(savedLoopMode);
    }
  }

  // ---------------------------------------------------------------------------
  // FIX-PERF-2: _updateQueueAfterAnchor — O(n) reorder via full replace
  //
  // OLD: O(n²) selection-sort with n sequential await _playlist!.move() calls.
  //      Each move() is async, so for 50 songs that's ~25 awaited round-trips
  //      on the platform channel — visible stutter.
  //
  // NEW: Build a fresh ConcatenatingAudioSource children list in the desired
  //      order and call setAudioSource with initialIndex pointing at the anchor
  //      song. This is O(n) and a single platform channel call.
  //
  //      The trade-off vs the old move()-based approach: we briefly re-buffer
  //      the anchor song (~100ms). This is imperceptible compared to the
  //      500ms–2s stutter from 50 sequential moves.
  //
  //      Exception: if the queue size is ≤ 5, moves are cheap enough that we
  //      keep the move()-based path to avoid the re-buffer entirely.
  // ---------------------------------------------------------------------------
  Future<void> _updateQueueAfterAnchor(int anchorIndex) async {
    if (_playlist == null) {
      final savedPosition = player.position;
      await _rebuildSource(anchorIndex, initialPosition: savedPosition);
      if (player.playing) player.play();
      return;
    }

    final int n = _currentQueue.length;

    // For very small queues, the old move()-based sort is cheaper (no rebuffer).
    if (n <= 5) {
      await _moveBasedReorder(anchorIndex);
      return;
    }

    // FIX-PERF-2: Single setAudioSource call — O(n), one platform channel round-trip.
    // BUG-7 FIX: Pre-compute offline paths to avoid N synchronous File.existsSync()
    // calls on the main thread during the _toSourceWithPaths loop.
    final savedPosition = player.position;
    final wasPlaying = player.playing;

    final offlinePaths = _precomputeOfflinePaths(_currentQueue);
    final sources = _currentQueue
        .map((song) => _toSourceWithPaths(song, offlinePaths))
        .toList();
    _playlist = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(
      _playlist!,
      initialIndex: anchorIndex,
      initialPosition: savedPosition,
    );

    if (wasPlaying) player.play();
  }

  /// Legacy O(n²) move-based reorder — used only for queues ≤ 5 songs.
  Future<void> _moveBasedReorder(int anchorIndex) async {
    final int n = _currentQueue.length;
    final List<String> liveIds = List.generate(n, (i) {
      final src = _playlist!.children[i];
      if (src is UriAudioSource && src.tag is MediaItem) {
        return (src.tag as MediaItem).id;
      }
      return '';
    });

    for (int targetIdx = 0; targetIdx < n; targetIdx++) {
      final wantedId = _currentQueue[targetIdx].id;
      if (liveIds[targetIdx] == wantedId) continue;
      final fromIdx = liveIds.indexOf(wantedId, targetIdx + 1);
      if (fromIdx == -1) continue;
      await _playlist!.move(fromIdx, targetIdx);
      final moved = liveIds.removeAt(fromIdx);
      liveIds.insert(targetIdx, moved);
    }

    final currentLiveIndex = player.currentIndex ?? 0;
    if (currentLiveIndex != anchorIndex) {
      await player.seek(player.position, index: anchorIndex);
    }
    if (player.playing) player.play();
  }

  // ---------------------------------------------------------------------------
  // Incremental queue mutations
  // ---------------------------------------------------------------------------

  Future<void> addToQueue(Song song) async {
    _currentQueue.add(song);
    _unshuffledQueue.add(song);
    if (_playlist != null) {
      await _playlist!.add(_toSource(song));
    } else {
      await _rebuildSource(_currentQueue.length - 1);
    }
  }

  Future<void> addAllToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    _currentQueue.addAll(songs);
    _unshuffledQueue.addAll(songs);
    if (_playlist != null) {
      await _playlist!.addAll(songs.map(_toSource).toList());
    } else {
      await _rebuildSource(_currentQueue.length - songs.length);
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _currentQueue.length) return;
    final song = _currentQueue.removeAt(index);
    final unIdx = _unshuffledQueue.indexWhere((s) => s.id == song.id);
    if (unIdx != -1) _unshuffledQueue.removeAt(unIdx);

    if (_playlist != null) {
      await _playlist!.removeAt(index);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  Future<void> reorderQueue(
    int oldIndex,
    int newIndex, {
    bool isShuffleMode = false,
  }) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length) return;
    if (newIndex < 0 || newIndex >= _currentQueue.length) return;
    final song = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, song);

    if (!isShuffleMode) {
      final unSong = _unshuffledQueue.removeAt(oldIndex);
      _unshuffledQueue.insert(newIndex, unSong);
    }

    if (_playlist != null) {
      await _playlist!.move(oldIndex, newIndex);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      await _rebuildSource(currentIndex.clamp(0, _currentQueue.length - 1));
    }
  }

  // ---------------------------------------------------------------------------
  // Shared anchor helper
  // ---------------------------------------------------------------------------
  Future<void> _shuffleFuture<T>(
    int currentIndex,
    ComputeCallback<T, List<Song>> worker,
    T args,
  ) async {
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final shuffled = await compute(worker, args);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 1. Standard Fisher-Yates
  // ---------------------------------------------------------------------------
  Future<void> standardShuffle() async {
    if (_currentQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final shuffled = await compute(_standardShuffleIsolate, future);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 2. Dithered Position Shuffle
  // ---------------------------------------------------------------------------
  Future<void> ditheredPositionShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Dithered Position ($preference)');
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final result = await compute(
      _ditheredPositionShuffleIsolate,
      <String, dynamic>{'songs': future, 'pref': preference.index},
    );
    debugPrint('✅ [SHUFFLE] Dithered result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  Future<void> spotifyDitherShuffle(ShufflePreference preference) =>
      ditheredPositionShuffle(preference);

  // ---------------------------------------------------------------------------
  // 3. Merge-Shuffle
  // ---------------------------------------------------------------------------
  Future<void> mergeShuffle(ShufflePreference preference) async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Merge-Shuffle ($preference)');
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final result = await compute(_mergeShuffleIsolate, <String, dynamic>{
      'songs': future,
      'pref': preference.index,
    });
    debugPrint('✅ [SHUFFLE] Merge result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 4. Weighted Shuffle
  // ---------------------------------------------------------------------------
  Future<void> youtubeWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Weighted Shuffle (O(n log n))');
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final shuffled = await compute(_weightedShuffleIsolate, future);
    _currentQueue = [...pastAndPresent, ...shuffled];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 5. Album-Aware Shuffle
  // ---------------------------------------------------------------------------
  Future<void> albumAwareShuffle({
    bool shuffleTracksWithinAlbum = false,
  }) async {
    if (_currentQueue.isEmpty) return;
    debugPrint(
      '🚀 [SHUFFLE] Album-Aware (shuffleTracks=$shuffleTracksWithinAlbum)',
    );
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final result = await compute(_albumAwareShuffleIsolate, <String, dynamic>{
      'songs': future,
      'shuffleTracks': shuffleTracksWithinAlbum,
    });
    debugPrint('✅ [SHUFFLE] Album-Aware result: ${result.length} songs');
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 6. Recency-Dampened Weighted Shuffle
  // ---------------------------------------------------------------------------
  Future<void> recencyDampenedWeightedShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint(
      '🚀 [SHUFFLE] Recency-Dampened Weighted Shuffle '
      '(window=$_recencyWindow, recent=${_recentlyPlayedIds.length})',
    );
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;
    final result = await compute(
      _recencyDampenedShuffleIsolate,
      <String, dynamic>{
        'songs': future,
        'recentIds': _recentlyPlayedIds.toList(),
      },
    );
    _currentQueue = [...pastAndPresent, ...result];
    await _updateQueueAfterAnchor(safeIndex);
  }

  // ---------------------------------------------------------------------------
  // 7. Smart Local Shuffle — FIXED
  //
  // OLD BUGS:
  //   BUG-A: smartLocalShuffle() was only called to RE-ORDER songs already
  //          fetched from Subsonic. The Python model has its own playlist index
  //          of ~1000 songs; the Subsonic similar-songs pool is completely
  //          different. Song title lookup always failed → fell through to
  //          random shuffle of Subsonic results → model was never actually used.
  //
  //   BUG-B: _fetchAndAppendSmartLocal() called getSimilarSongs() (Subsonic)
  //          THEN smartLocalShuffle() (Python). Two sequential network calls,
  //          neither of which talked to the same song list.
  //
  // NEW DESIGN:
  //   smartLocalShuffle() now calls the Python /next endpoint with the
  //   CURRENT song and asks for `count` song keys. It then looks up those
  //   keys in the FULL _currentQueue (not just the future slice), finds the
  //   matching Song objects by normalised title, puts them after the anchor,
  //   and appends any unmatched songs at the end.
  //
  //   _fetchAndAppendSmartLocal() (called by PlayerNotifier) no longer calls
  //   smartLocalShuffle(). Instead it fetches additional songs via Subsonic
  //   and appends them to the queue so future smartLocalShuffle() calls have
  //   a larger pool to reorder. The reordering is triggered separately by
  //   PlayerNotifier after the append.
  // ---------------------------------------------------------------------------

  /// Calls the Python model and reorders future queue items to match
  /// the model's recommended order. Only reorders [_currentQueue]; does NOT
  /// fetch any new songs. Call addAllToQueue() first if you want more songs.
  Future<void> smartLocalShuffle() async {
    if (_currentQueue.isEmpty) return;
    debugPrint('🚀 [SHUFFLE] Smart Local Model Shuffle');

    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final pastAndPresent = _currentQueue.sublist(0, safeIndex + 1);
    final future = _currentQueue.sublist(safeIndex + 1);
    if (future.isEmpty) return;

    final currentSong = _currentQueue[safeIndex];
    final count = future.length;

    // Build a lookup map: normalised title → Song
    // Use title because that's what the Python server matches on.
    final futureMap = <String, Song>{};
    for (final song in future) {
      final key = song.title.toLowerCase().trim();
      futureMap.putIfAbsent(key, () => song);
    }

    try {
      final uri = Uri.parse('$_smartLocalBase/next').replace(
        queryParameters: {
          'current': currentSong.title,
          'artist': currentSong.artist,
          'count': count.toString(),
          // FIX: tell the server to reset its session exclusion before
          // reordering the whole queue (fresh queue load context)
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5)); // FIX-TIMEOUT: was unbounded

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final List<String> serverSongKeys = data
            .map((e) => e['song_key'].toString())
            .toList();

        final List<Song> ordered = [];
        final Set<String> matched = {};

        for (final key in serverSongKeys) {
          final song = futureMap[key];
          if (song != null && !matched.contains(song.id)) {
            ordered.add(song);
            matched.add(song.id);
          }
        }

        // Append any songs the server didn't mention (unmatched pool)
        for (final song in future) {
          if (!matched.contains(song.id)) {
            ordered.add(song);
          }
        }

        _currentQueue = [...pastAndPresent, ...ordered];
        await _updateQueueAfterAnchor(safeIndex);
        debugPrint(
          '✅ [SHUFFLE] Smart Local: ${ordered.length} songs ordered, '
          '${matched.length} matched by model',
        );
      } else {
        debugPrint(
          '⚠️ [SHUFFLE] Smart Local: server returned ${response.statusCode}, '
          'falling back to standard shuffle',
        );
        await standardShuffle();
      }
    } catch (e) {
      debugPrint(
        '❌ [SHUFFLE] Smart Local failed: $e, falling back to standard shuffle',
      );
      await standardShuffle();
    }
  }

  // ---------------------------------------------------------------------------
  // 8. Unshuffle
  // ---------------------------------------------------------------------------
  Future<void> unshuffle() async {
    if (_currentQueue.isEmpty || _unshuffledQueue.isEmpty) return;
    final currentIndex = player.currentIndex ?? 0;
    final safeIndex = currentIndex.clamp(0, _currentQueue.length - 1);
    final currentSong = _currentQueue[safeIndex];
    _currentQueue = List.from(_unshuffledQueue);
    final newIndex = _unshuffledQueue.indexWhere((s) => s.id == currentSong.id);
    await _updateQueueAfterAnchor(newIndex != -1 ? newIndex : safeIndex);
  }

  // ---------------------------------------------------------------------------
  // computeShuffle — for initial playlist shuffle play
  // ---------------------------------------------------------------------------
  Future<List<Song>> computeShuffle(
    List<Song> pool,
    ShuffleAlgorithm algorithm,
    ShufflePreference preference, {
    bool albumShuffleTracks = false,
    Song? currentSong,
    String? contextName,
  }) async {
    switch (algorithm) {
      case ShuffleAlgorithm.standard:
        return compute(_standardShuffleIsolate, pool);

      case ShuffleAlgorithm.spotify:
        return compute(_ditheredPositionShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.youtube:
        return compute(_weightedShuffleIsolate, pool);

      case ShuffleAlgorithm.albumAware:
        return compute(_albumAwareShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'shuffleTracks': albumShuffleTracks,
        });

      case ShuffleAlgorithm.mergeShuffle:
        return compute(_mergeShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'pref': preference.index,
        });

      case ShuffleAlgorithm.recencyDampened:
        return compute(_recencyDampenedShuffleIsolate, <String, dynamic>{
          'songs': pool,
          'recentIds': _recentlyPlayedIds.toList(),
        });

      // FIX-SMART-LOCAL: computeShuffle for smartLocal now orders the pool
      // using the Python model directly — no Subsonic similar-songs involved.
      // The pool IS the songs to order; the model picks the best sequence.
      case ShuffleAlgorithm.smartLocal:
        if (pool.isEmpty) return pool;
        try {
          final queryParams = <String, String>{'count': pool.length.toString()};
          if (currentSong != null) {
            queryParams['current'] = currentSong.title;
            queryParams['artist'] = currentSong.artist;
          }
          if (contextName != null) {
            queryParams['playlist'] = contextName;
          }

          final uri = Uri.parse(
            '$_smartLocalBase/next',
          ).replace(queryParameters: queryParams);
          final response = await http
              .get(uri)
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final List<dynamic> data = jsonDecode(response.body);
            final serverKeys = data
                .map((e) => e['song_key'].toString())
                .toList();

            final poolMap = <String, Song>{};
            for (final song in pool) {
              poolMap.putIfAbsent(song.title.toLowerCase().trim(), () => song);
            }

            final List<Song> ordered = [];
            final Set<String> matched = {};
            for (final key in serverKeys) {
              final song = poolMap[key];
              if (song != null && !matched.contains(song.id)) {
                ordered.add(song);
                matched.add(song.id);
              }
            }
            for (final song in pool) {
              if (!matched.contains(song.id)) ordered.add(song);
            }

            debugPrint(
              '✅ [computeShuffle] Smart Local: ${matched.length}/${pool.length} matched',
            );
            return ordered;
          }
        } catch (e) {
          debugPrint('❌ [computeShuffle] Smart Local failed: $e');
        }
        // Fallback: standard shuffle
        return compute(_standardShuffleIsolate, pool);
    }
  }

  void updateSongWeight(Song song, bool suggestMore) {
    for (int i = 0; i < _currentQueue.length; i++) {
      if (_currentQueue[i].id == song.id) {
        final current = _currentQueue[i].dynamicWeight;
        final newWeight = suggestMore
            ? (current * 1.5).clamp(0.1, 10.0)
            : (current * 0.5).clamp(0.1, 10.0);
        _currentQueue[i] = _currentQueue[i].copyWith(dynamicWeight: newWeight);
        break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Offline path helpers — BUG 3 + BUG 7 fix
  //
  // _toSource() calls OfflineService().getLocalPath() which does
  // File.existsSync() synchronously. During a bulk source rebuild for a large
  // queue this is N blocking I/O calls interleaved with AudioSource/MediaItem
  // construction.  Pre-computing a Map<songId, localPath?> in one tight loop
  // is significantly cheaper than N interleaved existsSync calls.
  //
  // OfflineService() is a singleton (factory constructor → _instance), so
  // constructing it here always returns the same object.
  //
  // NOTE: This is still synchronous. For very large queues (500+ songs) a
  // future improvement is to use Future.wait() with File.exists() (async).
  // ---------------------------------------------------------------------------

  /// Pre-computes offline file paths for every song in [songs].
  /// Batches all File.existsSync() calls into a single tight loop instead of
  /// interleaving them with AudioSource + MediaItem construction.
  Map<String, String?> _precomputeOfflinePaths(List<Song> songs) {
    final offline = OfflineService();
    final map = <String, String?>{};
    for (final song in songs) {
      map[song.id] = offline.getLocalPath(song.id);
    }
    return map;
  }

  /// Like [_toSource] but uses a pre-computed [paths] map instead of calling
  /// OfflineService.getLocalPath() (which does File.existsSync()) per song.
  /// Use during bulk source-list builds; use [_toSource] for single songs.
  AudioSource _toSourceWithPaths(Song song, Map<String, String?> paths) {
    final localPath = paths[song.id];
    final streamUri = localPath != null
        ? Uri.parse('file://$localPath')
        : Uri.parse(subsonicService.getStreamUrl(song.id));

    return AudioSource.uri(
      streamUri,
      tag: MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        genre: song.genre,
        artUri: Uri.parse(subsonicService.getCoverArtUrl(song.coverArt)),
        duration: Duration(seconds: song.duration),
        extras: {'composer': song.composer, 'isLocal': localPath != null},
      ),
    );
  }

  Future<void> dispose() async {
    await player.stop();
    await player.dispose();
  }
}
