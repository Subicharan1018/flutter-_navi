import 'dart:convert';

import '../../models/song.dart';

/// R7: playlist history. A snapshot of a playlist's songs is kept every time
/// the app sees it change, so a removed song, or a whole earlier version, can
/// be brought back. Pure logic and (de)serialisation.

/// Just enough of a song to show it and to put it back.
class VSong {
  const VSong(this.id, this.title, this.artist);
  final String id;
  final String title;
  final String artist;

  factory VSong.of(Song s) => VSong(s.id, s.title, s.artist);
}

/// The playlist as it was at [at].
class PlaylistVersion {
  const PlaylistVersion(this.at, this.songs);
  final DateTime at;
  final List<VSong> songs;

  List<String> get ids => [for (final s in songs) s.id];
}

/// What changed from one version to the next.
class VersionChange {
  const VersionChange({required this.added, required this.removed, required this.reordered});
  final List<VSong> added;
  final List<VSong> removed;

  /// Same songs, different order.
  final bool reordered;

  bool get isEmpty => added.isEmpty && removed.isEmpty && !reordered;

  /// "+3 −1", "reordered", "+2".
  String get summary {
    final parts = [
      if (added.isNotEmpty) '+${added.length}',
      if (removed.isNotEmpty) '−${removed.length}',
      if (reordered && added.isEmpty && removed.isEmpty) 'reordered',
    ];
    return parts.isEmpty ? 'no change' : parts.join(' ');
  }
}

/// A song taken out of the playlist, and when the app first saw it gone.
class RemovedSong {
  const RemovedSong(this.song, this.removedAt);
  final VSong song;
  final DateTime removedAt;
}

class PlaylistVersions {
  PlaylistVersions._();

  /// Versions kept per playlist.
  static const keep = 20;

  /// Songs kept per version. Longer playlists are not snapshotted at all
  /// (see [record]): a cut copy would lose the tail when restored.
  static const maxSongs = 1000;

  static bool _sameOrder(List<VSong> a, List<VSong> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// [versions] (newest first) with [songs] recorded at [at]. The same songs in
  /// the same order as the newest version is not a new version. Capped at
  /// [keep].
  static List<PlaylistVersion> record(List<PlaylistVersion> versions, List<Song> songs, DateTime at) {
    if (songs.length > maxSongs) return versions;
    final snap = [for (final s in songs) VSong.of(s)];
    if (versions.isNotEmpty && _sameOrder(versions.first.songs, snap)) return versions;
    // Nothing to protect in a first look at an empty playlist.
    if (versions.isEmpty && snap.isEmpty) return versions;
    return [PlaylistVersion(at, snap), ...versions].take(keep).toList();
  }

  /// What [to] changed relative to [from].
  static VersionChange diff(PlaylistVersion from, PlaylistVersion to) {
    final fromIds = from.ids.toSet();
    final toIds = to.ids.toSet();
    final added = [for (final s in to.songs) if (!fromIds.contains(s.id)) s];
    final removed = [for (final s in from.songs) if (!toIds.contains(s.id)) s];
    final common = [for (final s in from.songs) if (toIds.contains(s.id)) s.id];
    final commonTo = [for (final s in to.songs) if (fromIds.contains(s.id)) s.id];
    var reordered = false;
    for (var i = 0; i < common.length && i < commonTo.length; i++) {
      if (common[i] != commonTo[i]) {
        reordered = true;
        break;
      }
    }
    return VersionChange(added: added, removed: removed, reordered: reordered);
  }

  /// Songs that were in an earlier version and are not in [current] now, newest
  /// removal first, each once. "Removed at" is the time of the first version
  /// without the song after one that had it.
  static List<RemovedSong> recentlyRemoved(List<PlaylistVersion> versions, List<String> current, {int max = 50}) {
    final now = current.toSet();
    final seen = <String>{};
    final out = <RemovedSong>[];
    // versions are newest first: walk pairs (newer, older).
    for (var i = 0; i + 1 < versions.length; i++) {
      final newer = versions[i];
      final newerIds = newer.ids.toSet();
      for (final s in versions[i + 1].songs) {
        if (!newerIds.contains(s.id) && !now.contains(s.id) && seen.add(s.id)) {
          out.add(RemovedSong(s, newer.at));
        }
      }
    }
    // The newest version may itself differ from what is live (edited since).
    if (versions.isNotEmpty) {
      for (final s in versions.first.songs) {
        if (!now.contains(s.id) && seen.add(s.id)) out.add(RemovedSong(s, versions.first.at));
      }
    }
    out.sort((a, b) => b.removedAt.compareTo(a.removedAt));
    return out.take(max).toList();
  }

  /// The ids to write to the playlist to bring [version] back.
  static List<String> restoreIds(PlaylistVersion version) => version.ids;

  /// [current] with [songIds] added at the end (those already there are
  /// skipped): "put this removed song back".
  static List<String> withAdded(List<String> current, Iterable<String> songIds) {
    final have = current.toSet();
    return [...current, for (final id in songIds) if (have.add(id)) id];
  }

  // ── storage ────────────────────────────────────────────────────────────────

  /// Per playlist: a dictionary of songs (id → title, artist) written once,
  /// and each version as its time and a list of ids. Versions of one playlist
  /// share most songs, so this is a fraction of the size of repeating them.
  static String encode(Map<String, List<PlaylistVersion>> all) => jsonEncode({
    for (final e in all.entries)
      e.key: {
        'd': {
          for (final v in e.value)
            for (final s in v.songs) s.id: [s.title, s.artist],
        },
        'v': [
          for (final v in e.value) {'t': v.at.millisecondsSinceEpoch, 's': v.ids},
        ],
      },
  });

  static Map<String, List<PlaylistVersion>> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw) as Map;
      final out = <String, List<PlaylistVersion>>{};
      for (final e in j.entries) {
        try {
          final dict = e.value['d'] as Map;
          VSong song(String id) {
            final d = dict[id] as List;
            return VSong(id, d[0] as String, d[1] as String);
          }

          out[e.key as String] = [
            for (final v in e.value['v'] as List)
              PlaylistVersion(
                DateTime.fromMillisecondsSinceEpoch(((v as Map)['t'] as num).toInt()),
                [for (final id in v['s'] as List) song(id as String)],
              ),
          ];
        } catch (_) {} // one damaged playlist loses its history, not all of them
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
