import 'dart:convert';

import '../models/song.dart';
import 'resume_position.dart';

/// The queue as it was when the app last stopped, so the next launch can show
/// it (paused) instead of an empty player.
///
/// Stored as ONE json string under one key: a write replaces the whole value
/// or nothing, so a crash mid-write leaves the previous snapshot, never half
/// of one. Anything that does not parse, or has a different version, reads as
/// "no snapshot" and the app starts clean.
///
/// The playback position is not in here: it changes every second and lives in
/// its own small keys next to the song it belongs to (see [resumeSeekMs]).
class SavedQueue {
  SavedQueue({
    required this.account,
    required this.songs,
    required this.unshuffledIds,
    required this.index,
    required this.shuffle,
    required this.repeat,
    this.source,
  });

  static const int version = 1;

  /// Songs kept around the current one: this many before, this many after.
  static const int windowEachSide = 100;

  /// Who saved it: `server|username`. Another account never restores it.
  final String account;

  /// The queue in play order, limited to the window around the current song.
  final List<Song> songs;

  /// The order before shuffling (ids), limited to songs that are in [songs].
  final List<String> unshuffledIds;

  /// The current song's position in [songs].
  final int index;
  final bool shuffle;

  /// `LoopMode.index`.
  final int repeat;

  /// Playlist / album name the queue came from, if any.
  final String? source;

  static String accountKey(String serverUrl, String username) =>
      '${serverUrl.trim().toLowerCase()}|${username.trim().toLowerCase()}';

  /// Builds a snapshot from the live queue, keeping at most the current song
  /// and [windowEachSide] on each side. Null when there is nothing to keep.
  static SavedQueue? capture({
    required String account,
    required List<Song> queue,
    required int currentIndex,
    required List<Song> unshuffled,
    required bool shuffle,
    required int repeat,
    String? source,
  }) {
    if (queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length) return null;
    final from = (currentIndex - windowEachSide).clamp(0, queue.length);
    final to = (currentIndex + windowEachSide + 1).clamp(0, queue.length);
    final kept = queue.sublist(from, to);
    final keptIds = {for (final s in kept) s.id};
    return SavedQueue(
      account: account,
      songs: kept,
      unshuffledIds: [
        for (final s in unshuffled)
          if (keptIds.contains(s.id)) s.id,
      ],
      index: currentIndex - from,
      shuffle: shuffle,
      repeat: repeat,
      source: source,
    );
  }

  String encode() => jsonEncode({
        'v': version,
        'account': account,
        'index': index,
        'shuffle': shuffle,
        'repeat': repeat,
        if (source != null) 'source': source,
        'unshuffled': unshuffledIds,
        'songs': [
          for (final s in songs)
            () {
              final m = s.toMap();
              // fromJson reads any `starred` value as "starred".
              if (!s.starred) m.remove('starred');
              return m;
            }(),
        ],
      });

  /// The snapshot in [raw], or null if it is missing, damaged or from an
  /// incompatible version. Never throws.
  static SavedQueue? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['v'] != version) return null;
      final account = j['account'];
      final rawSongs = j['songs'];
      if (account is! String || rawSongs is! List || rawSongs.isEmpty) return null;
      final songs = <Song>[];
      for (final e in rawSongs) {
        if (e is! Map) return null; // one bad entry: drop the whole snapshot
        final song = Song.fromJson(Map<String, dynamic>.from(e));
        if (song.id.isEmpty) return null;
        songs.add(song);
      }
      final index = j['index'];
      final shuffle = j['shuffle'];
      final repeat = j['repeat'];
      if (index is! int || shuffle is! bool || repeat is! int) return null;
      final unshuffled = j['unshuffled'];
      return SavedQueue(
        account: account,
        songs: songs,
        unshuffledIds: unshuffled is List ? [for (final u in unshuffled) u.toString()] : const [],
        index: index,
        shuffle: shuffle,
        repeat: repeat,
        source: j['source'] is String ? j['source'] as String : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// What can be restored now, or null when nothing should be.
  ///
  /// - another account's snapshot is never used;
  /// - [isGone] marks songs removed from the library (null: cannot tell, keep
  ///   all); the others stay, and if the current song went the next one that
  ///   is left takes its place, from the start;
  /// - a stale index is pulled back into the queue.
  RestoredQueue? resolve({
    required String account,
    bool Function(String songId)? isGone,
    String? savedTrackId,
    int savedPositionMs = 0,
  }) {
    if (account != this.account) return null;
    final at = index.clamp(0, songs.length - 1);
    final currentId = songs[at].id;
    final kept = isGone == null ? songs : [for (final s in songs) if (!isGone(s.id)) s];
    if (kept.isEmpty) return null;

    var restoredIndex = kept.indexWhere((s) => s.id == currentId);
    final currentSurvived = restoredIndex >= 0;
    if (!currentSurvived) {
      // The first song after the removed one that is still here.
      // None after it: the last one that is left.
      restoredIndex = kept.length - 1;
      for (var i = at + 1; i < songs.length; i++) {
        final k = kept.indexWhere((s) => s.id == songs[i].id);
        if (k >= 0) {
          restoredIndex = k;
          break;
        }
      }
    }
    final restoredSong = kept[restoredIndex];

    final byId = {for (final s in kept) s.id: s};
    final unshuffled = [
      for (final id in unshuffledIds)
        if (byId[id] != null) byId[id]!,
    ];

    return RestoredQueue(
      songs: kept,
      unshuffled: unshuffled.length == kept.length ? unshuffled : kept,
      index: restoredIndex,
      positionMs: currentSurvived
          ? resumeSeekMs(
              savedTrackId: savedTrackId,
              savedMs: savedPositionMs,
              startingTrackId: restoredSong.id,
              durationMs: restoredSong.duration * 1000,
            )
          : 0,
      shuffle: shuffle,
      repeat: repeat,
      source: source,
    );
  }
}

/// A [SavedQueue] checked against today's library, ready to load.
class RestoredQueue {
  const RestoredQueue({
    required this.songs,
    required this.unshuffled,
    required this.index,
    required this.positionMs,
    required this.shuffle,
    required this.repeat,
    this.source,
  });

  final List<Song> songs;
  final List<Song> unshuffled;
  final int index;
  final int positionMs;
  final bool shuffle;
  final int repeat;
  final String? source;
}
