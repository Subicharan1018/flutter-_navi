import 'dart:convert';

import '../../models/song.dart';

/// R6: the last queues, so yesterday's can come back.
///
/// A queue is remembered when something replaces it (a new album, playlist,
/// Flow, Smart Shuffle...), so the list holds the queues you moved on from.
/// Pure logic and (de)serialisation; the Hive backing is in
/// recent_queues_providers.dart.

/// One remembered queue.
class RecentQueue {
  RecentQueue({
    required this.account,
    required this.savedAt,
    required this.songs,
    this.source,
    this.index = 0,
  });

  /// `server|username`; another account never sees it.
  final String account;
  final DateTime savedAt;
  final List<Song> songs;

  /// Where it came from ("Late night", "Rahman hits"), if the player knew.
  final String? source;

  /// The song that was playing, as a position in [songs].
  final int index;

  /// Same songs in the same order.
  bool sameSongs(List<Song> other) {
    if (other.length != songs.length) return false;
    for (var i = 0; i < songs.length; i++) {
      if (songs[i].id != other[i].id) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'a': account,
    't': savedAt.millisecondsSinceEpoch,
    'i': index,
    if (source != null) 's': source,
    'songs': [for (final s in songs) s.toMap()],
  };

  static RecentQueue? tryParse(Object? raw) {
    try {
      final j = Map<String, dynamic>.from(raw as Map);
      final songs = [
        for (final m in (j['songs'] as List)) Song.fromJson(Map<String, dynamic>.from(m as Map)),
      ];
      if (songs.isEmpty) return null;
      return RecentQueue(
        account: j['a'] as String,
        savedAt: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        songs: songs,
        source: j['s'] as String?,
        index: ((j['i'] as num?)?.toInt() ?? 0).clamp(0, songs.length - 1),
      );
    } catch (_) {
      return null;
    }
  }
}

class RecentQueues {
  RecentQueues._();

  /// Queues kept per account.
  static const keep = 10;

  /// A queue shorter than this is not worth remembering: a single song tapped
  /// in search is not "a queue".
  static const minSongs = 2;

  /// Songs kept per queue; the ones around the playing song, like the saved
  /// queue of the last session.
  static const maxSongs = 200;

  /// [list] with [outgoing] remembered. Newest first, at most [keep] per
  /// account. The same songs as an existing entry replace it (moved to the
  /// top), so replaying one queue doesn't fill the list with copies.
  static List<RecentQueue> remember(List<RecentQueue> list, RecentQueue outgoing) {
    if (outgoing.songs.length < minSongs) return list;
    var songs = outgoing.songs;
    var index = outgoing.index;
    if (songs.length > maxSongs) {
      final from = (index - maxSongs ~/ 2).clamp(0, songs.length - maxSongs);
      songs = songs.sublist(from, from + maxSongs);
      index -= from;
    }
    final entry = RecentQueue(
      account: outgoing.account,
      savedAt: outgoing.savedAt,
      songs: songs,
      source: outgoing.source,
      index: index.clamp(0, songs.length - 1),
    );
    final others = [
      for (final q in list)
        if (!(q.account == entry.account && q.sameSongs(entry.songs))) q,
    ];
    final result = [entry, ...others];
    // Trim per account, newest first.
    final counts = <String, int>{};
    return [
      for (final q in result)
        if ((counts[q.account] = (counts[q.account] ?? 0) + 1) <= keep) q,
    ];
  }

  /// The queues of [account], newest first.
  static List<RecentQueue> forAccount(List<RecentQueue> list, String account) => [
    for (final q in list)
      if (q.account == account) q,
  ];

  static String encode(List<RecentQueue> list) => jsonEncode([for (final q in list) q.toJson()]);

  /// Anything that does not parse reads as an empty list; one bad entry is
  /// dropped, not the rest.
  static List<RecentQueue> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final e in list) ?RecentQueue.tryParse(e)];
    } catch (_) {
      return const [];
    }
  }

  /// "Yesterday, 9:40 pm · 24 songs" label parts: the caller formats the day.
  static String title(RecentQueue q) {
    if (q.source != null && q.source!.trim().isNotEmpty) return q.source!;
    final first = q.songs.first;
    return q.songs.length > 1 ? '${first.title} and ${q.songs.length - 1} more' : first.title;
  }
}
