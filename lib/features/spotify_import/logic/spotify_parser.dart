/// Reads a Spotify "Extended Streaming History" (or the older basic export) on the device and keeps ONLY what the
/// import needs. Everything else is dropped here, before anything is sent anywhere:
///
///  * kept per music play: the time (UTC), title, artist, album, ms played, how it ended (`reason_end`) and
///    Spotify's `skipped` flag;
///  * dropped: IP address, country, platform, offline details, connection details, track URIs, podcast episodes,
///    audiobooks, video history files, and plays made in Private Session (incognito).
///
/// Nothing here logs or prints file contents. The work runs in an isolate ([parseSpotifyFiles]) because a full
/// export can be 50 MB or more of JSON.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

enum SpotifyFormat {
  extended('extended'),
  basic('basic');

  final String wire;
  const SpotifyFormat(this.wire);
}

/// One music play with only the needed fields.
class SpotifyPlay {
  /// When the play ended, UTC epoch seconds (Spotify's `ts`: the server works out the start).
  final int t;
  final int ms;
  final String title;
  final String artist;
  final String album;

  /// `reason_end` (trackdone, fwdbtn, backbtn, endplay, logout, ...); empty in the basic export.
  final String end;

  /// Spotify's `skipped` flag; null when absent.
  final bool? skipped;

  const SpotifyPlay({
    required this.t,
    required this.ms,
    required this.title,
    required this.artist,
    this.album = '',
    this.end = '',
    this.skipped,
  });

  /// The wire form: the same keys the server's `/spotify-import/jobs/<id>/page` reads, nothing else.
  Map<String, Object> toJson() => {
    't': t,
    'ms': ms,
    'title': title,
    'artist': artist,
    if (album.isNotEmpty) 'album': album,
    if (end.isNotEmpty) 'end': end,
    'sk': ?skipped,
  };
}

/// What was found and what was thrown away. Counts only.
class SpotifyParseSummary {
  final SpotifyFormat format;

  /// History files read / files in the ZIP that were left alone (video, README, ...) / history files that could
  /// not be read.
  final int filesRead;
  final int filesIgnored;
  final int filesUnreadable;
  final int rows;
  final int kept;
  final int droppedEpisodes;
  final int droppedAudiobooks;
  final int droppedPrivate;

  /// No title or artist, or an unreadable time / length.
  final int droppedUnusable;

  /// Oldest and newest play kept (UTC epoch seconds); null when nothing was kept.
  final int? firstTs;
  final int? lastTs;

  const SpotifyParseSummary({
    required this.format,
    this.filesRead = 0,
    this.filesIgnored = 0,
    this.filesUnreadable = 0,
    this.rows = 0,
    this.kept = 0,
    this.droppedEpisodes = 0,
    this.droppedAudiobooks = 0,
    this.droppedPrivate = 0,
    this.droppedUnusable = 0,
    this.firstTs,
    this.lastTs,
  });

  int get dropped => droppedEpisodes + droppedAudiobooks + droppedPrivate + droppedUnusable;
}

class SpotifyParseResult {
  /// Oldest first.
  final List<SpotifyPlay> plays;
  final SpotifyParseSummary summary;
  const SpotifyParseResult(this.plays, this.summary);
}

/// The ZIP or file is not a Spotify history (nothing to import).
class SpotifyParseException implements Exception {
  final String message;
  const SpotifyParseException(this.message);
  @override
  String toString() => message;
}

final RegExp _extendedName = RegExp(r'^streaming_history_audio_.*\.json$');
final RegExp _basicName = RegExp(r'^streaminghistory(_music)?_?\d*\.json$');

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last.toLowerCase();

bool isExtendedHistoryFile(String path) => _extendedName.hasMatch(_baseName(path));
bool isBasicHistoryFile(String path) => _basicName.hasMatch(_baseName(path));

bool _has(Object? v) => v is String ? v.trim().isNotEmpty : v != null;

/// Collects files one at a time so a big export is never all in memory as raw JSON.
class SpotifyAccumulator {
  final List<SpotifyPlay> _extended = [];
  final List<SpotifyPlay> _basic = [];
  int _extendedFiles = 0, _basicFiles = 0, _ignored = 0, _unreadable = 0;
  int _rows = 0, _episodes = 0, _audiobooks = 0, _private = 0, _unusable = 0;
  int _basicRows = 0, _basicUnusable = 0;

  /// Counts a file that is not history (video, README, ...) without opening it.
  void ignore() => _ignored++;

  /// Reads one file. [name] decides what it is; anything that is not a music history file is ignored unread.
  void add(String name, Uint8List bytes) {
    final extended = isExtendedHistoryFile(name);
    if (!extended && !isBasicHistoryFile(name)) {
      _ignored++;
      return;
    }
    final Object? data;
    try {
      var text = utf8.decode(bytes, allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      data = jsonDecode(text);
    } on FormatException {
      _unreadable++;
      return;
    }
    if (data is! List) {
      _unreadable++;
      return;
    }
    if (extended) {
      _extendedFiles++;
      _rows += data.length;
      for (final r in data) {
        _extendedRow(r);
      }
    } else {
      _basicFiles++;
      _basicRows += data.length;
      for (final r in data) {
        _basicRow(r);
      }
    }
  }

  void _extendedRow(Object? r) {
    if (r is! Map) {
      _unusable++;
      return;
    }
    if (_has(r['episode_name']) || _has(r['episode_show_name']) || _has(r['spotify_episode_uri'])) {
      _episodes++;
      return;
    }
    if (_has(r['audiobook_title']) || _has(r['audiobook_uri']) || _has(r['audiobook_chapter_uri'])) {
      _audiobooks++;
      return;
    }
    if (r['incognito_mode'] == true) {
      _private++;
      return;
    }
    final title = r['master_metadata_track_name'], artist = r['master_metadata_album_artist_name'];
    final when = DateTime.tryParse('${r['ts']}');
    final ms = r['ms_played'];
    if (title is! String || title.trim().isEmpty || artist is! String || artist.trim().isEmpty) {
      _unusable++;
      return;
    }
    if (when == null || ms is! num || !ms.isFinite || ms < 0) {
      _unusable++;
      return;
    }
    final album = r['master_metadata_album_album_name'], end = r['reason_end'], sk = r['skipped'];
    _extended.add(
      SpotifyPlay(
        t: when.toUtc().millisecondsSinceEpoch ~/ 1000,
        ms: ms.toInt(),
        title: title.trim(),
        artist: artist.trim(),
        album: album is String ? album.trim() : '',
        end: end is String ? end.trim() : '',
        skipped: sk is bool ? sk : null,
      ),
    );
  }

  void _basicRow(Object? r) {
    if (r is! Map) {
      _basicUnusable++;
      return;
    }
    final title = r['trackName'], artist = r['artistName'], ms = r['msPlayed'];
    final raw = '${r['endTime']}'.trim();
    // "2023-11-02 11:28" is UTC, written without a zone.
    final when = DateTime.tryParse(raw.contains('Z') || raw.contains('+') ? raw : '${raw.replaceFirst(' ', 'T')}Z');
    if (title is! String || title.trim().isEmpty || artist is! String || artist.trim().isEmpty) {
      _basicUnusable++;
      return;
    }
    if (when == null || ms is! num || !ms.isFinite || ms < 0) {
      _basicUnusable++;
      return;
    }
    _basic.add(
      SpotifyPlay(
        t: when.toUtc().millisecondsSinceEpoch ~/ 1000,
        ms: ms.toInt(),
        title: title.trim(),
        artist: artist.trim(),
      ),
    );
  }

  SpotifyParseResult finish() {
    final extended = _extendedFiles > 0;
    if (!extended && _basicFiles == 0) {
      throw const SpotifyParseException(
        'No Spotify listening history found in this file. Choose the ZIP from Spotify’s “Extended streaming history” '
        '(or its Streaming_History_Audio files).',
      );
    }
    final plays = extended ? _extended : _basic;
    plays.sort((a, b) => a.t.compareTo(b.t));
    final summary = SpotifyParseSummary(
      format: extended ? SpotifyFormat.extended : SpotifyFormat.basic,
      filesRead: extended ? _extendedFiles : _basicFiles,
      filesIgnored: _ignored + (extended ? _basicFiles : 0),
      filesUnreadable: _unreadable,
      rows: extended ? _rows : _basicRows,
      kept: plays.length,
      droppedEpisodes: extended ? _episodes : 0,
      droppedAudiobooks: extended ? _audiobooks : 0,
      droppedPrivate: extended ? _private : 0,
      droppedUnusable: extended ? _unusable : _basicUnusable,
      firstTs: plays.isEmpty ? null : plays.first.t,
      lastTs: plays.isEmpty ? null : plays.last.t,
    );
    return SpotifyParseResult(plays, summary);
  }
}

/// Parses already-loaded files (tests, and the small-file path). Same rules as [parseSpotifyFiles].
SpotifyParseResult parseSpotifyBytes(Iterable<(String, Uint8List)> files) {
  final acc = SpotifyAccumulator();
  for (final (name, bytes) in files) {
    acc.add(name, bytes);
  }
  return acc.finish();
}

SpotifyParseResult _parsePaths(List<String> paths) {
  final acc = SpotifyAccumulator();
  for (final path in paths) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.zip')) {
      final input = InputFileStream(path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        for (final f in archive.files) {
          if (!f.isFile) continue;
          // Only music history files are ever inflated; video, README and the rest are skipped unread.
          if (isExtendedHistoryFile(f.name) || isBasicHistoryFile(f.name)) {
            acc.add(f.name, f.readBytes() ?? Uint8List(0));
          } else {
            acc.ignore();
          }
        }
      } on ArchiveException {
        throw const SpotifyParseException('That ZIP can’t be opened. Download it again from Spotify and retry.');
      } on FormatException {
        throw const SpotifyParseException('That ZIP can’t be opened. Download it again from Spotify and retry.');
      } finally {
        input.closeSync();
      }
    } else {
      acc.add(path, File(path).readAsBytesSync());
    }
  }
  return acc.finish();
}

/// Reads the chosen ZIP and/or JSON files in a background isolate and returns only the kept fields.
Future<SpotifyParseResult> parseSpotifyFiles(List<String> paths) => Isolate.run(() => _parsePaths(paths));

/// Splits plays into pages of at most [pageSize] for upload (the server takes up to 1,000 at a time).
List<List<SpotifyPlay>> spotifyPages(List<SpotifyPlay> plays, {int pageSize = spotifyPageSize}) => [
  for (var i = 0; i < plays.length; i += pageSize)
    plays.sublist(i, i + pageSize > plays.length ? plays.length : i + pageSize),
];

const int spotifyPageSize = 1000;
