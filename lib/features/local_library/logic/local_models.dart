import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../../../models/song.dart';

/// Ids of device songs start with this, so they can never collide with
/// Subsonic ids and every server-only call site can tell them apart.
const localSongIdPrefix = 'local:';

bool isLocalSongId(String id) => id.startsWith(localSongIdPrefix);

/// Stable id for a file: the same path or document URI always maps to the
/// same id, so a rescan keeps play history and queue entries.
String localSongIdFor(String path) =>
    '$localSongIdPrefix${md5.convert(utf8.encode(path)).toString().substring(0, 16)}';

/// Stable id of an added folder, from its path or tree URI.
String folderIdFor(String uri) => localSongIdFor(uri).substring(localSongIdPrefix.length);

/// A folder location the way a person reads it: Android tree URIs
/// (`content://…/tree/primary%3AMusic`) become "Internal storage/Music".
String displayFolderPath(String uri) {
  if (!uri.startsWith('content://')) return uri;
  final i = uri.indexOf('/tree/');
  if (i < 0) return uri;
  var doc = Uri.decodeComponent(uri.substring(i + 6));
  final colon = doc.indexOf(':');
  if (colon < 0) return doc;
  final volume = doc.substring(0, colon);
  final rest = doc.substring(colon + 1);
  final root = volume == 'primary' ? 'Internal storage' : 'SD card ($volume)';
  return rest.isEmpty ? root : '$root/$rest';
}

/// One audio file found while listing a folder.
class ScanEntry {
  /// Path or `content://` URI; what playback opens.
  final String path;
  final String name;

  /// Containing folder (path or URI), used to pair sidecar files.
  final String dir;
  final int size;
  final int modifiedMs;

  const ScanEntry({
    required this.path,
    required this.name,
    required this.dir,
    required this.size,
    required this.modifiedMs,
  });
}

/// Every file of interest in an added folder, already sorted by kind.
class FolderListing {
  final List<ScanEntry> audio;

  /// Sidecar lyrics keyed by `dir|basename` (lower case).
  final Map<String, ScanEntry> lyrics;

  /// A cover picture per folder (`cover`, `folder`, `front`, `album`).
  final Map<String, ScanEntry> folderArt;

  const FolderListing({
    this.audio = const [],
    this.lyrics = const {},
    this.folderArt = const {},
  });
}

/// A file's tags, as the scanner reads them.
class ScannedTrack {
  final String path;
  final String songId;
  final String folderId;
  final String fingerprint;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int track;
  final int disc;
  final int year;
  final int durationSec;
  final int bitRate;
  final String suffix;
  final double? trackGain;
  final double? albumGain;
  final double? trackPeak;
  final double? albumPeak;
  final String? coverPath;
  final String? lyrics;

  const ScannedTrack({
    required this.path,
    required this.songId,
    required this.folderId,
    required this.fingerprint,
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.genre = '',
    this.track = 0,
    this.disc = 0,
    this.year = 0,
    this.durationSec = 0,
    this.bitRate = 0,
    this.suffix = '',
    this.trackGain,
    this.albumGain,
    this.trackPeak,
    this.albumPeak,
    this.coverPath,
    this.lyrics,
  });
}

/// Progress and results the scan reports while it runs.
sealed class ScanEvent {
  const ScanEvent();
}

class ScanListed extends ScanEvent {
  final String folderId;
  final int total;
  final int changed;
  const ScanListed(this.folderId, this.total, this.changed);
}

class ScanBatch extends ScanEvent {
  final List<ScannedTrack> tracks;
  final int done;
  final int total;
  const ScanBatch(this.tracks, this.done, this.total);
}

/// A folder finished: every path still present in it. Rows of this folder
/// that are not in [seen] were removed from the device.
class ScanFolderDone extends ScanEvent {
  final String folderId;
  final Set<String> seen;
  final int unreadable;
  const ScanFolderDone(this.folderId, this.seen, this.unreadable);
}

/// A folder could not be listed (permission revoked, drive gone). Its
/// rows are kept: missing access is not the same as deleted files.
class ScanFolderFailed extends ScanEvent {
  final String folderId;
  final String message;
  const ScanFolderFailed(this.folderId, this.message);
}

/// A folder the user added.
class LocalFolder {
  final String id;

  /// Path or `content://` tree URI.
  final String uri;
  final String name;
  const LocalFolder({required this.id, required this.uri, required this.name});

  bool get isSaf => uri.startsWith('content://');

  Map<String, String> toJson() => {'id': id, 'uri': uri, 'name': name};

  static LocalFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], uri = raw['uri'], name = raw['name'];
    if (id is! String || uri is! String) return null;
    return LocalFolder(id: id, uri: uri, name: name is String ? name : uri);
  }
}

/// A local song as a [Song]: `coverArt` is the id itself, which
/// `SubsonicService.getCoverArtUrl` turns into the cover file.
Song localSongToSong({
  required String id,
  required String title,
  required String artist,
  required String album,
  required String genre,
  required int track,
  required int year,
  required int durationSec,
  required int bitRate,
  required String suffix,
  required double? trackGain,
  required double? albumGain,
  required double? trackPeak,
  required double? albumPeak,
  required DateTime added,
}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      coverArt: id,
      duration: durationSec,
      track: track,
      year: year,
      bitRate: bitRate,
      contentType: suffix.isEmpty ? '' : 'audio/$suffix',
      suffix: suffix,
      trackGain: trackGain,
      albumGain: albumGain,
      trackPeak: trackPeak,
      albumPeak: albumPeak,
      created: added,
    );
