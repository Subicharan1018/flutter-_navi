import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';

import 'file_source.dart';
import 'local_models.dart';

/// "-6.54 dB" → -6.54. Null when the tag is missing or not a number.
double? parseGain(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'[-+]?\d+(?:[.,]\d+)?').firstMatch(raw);
  return m == null ? null : double.tryParse(m.group(0)!.replaceAll(',', '.'));
}

class _ReplayGain {
  double? trackGain, albumGain, trackPeak, albumPeak;
}

/// ReplayGain lives in different places per tag family; read what the format
/// offers. Failures just mean "no ReplayGain".
_ReplayGain _readReplayGain(File file) {
  final rg = _ReplayGain();
  try {
    final tag = readAllMetadata(file, getImage: false);
    switch (tag) {
      case VorbisMetadata():
        rg.trackGain = parseGain(tag.replayGainTrackGain.firstOrNull);
        rg.albumGain = parseGain(tag.replayGainAlbumGain.firstOrNull);
        rg.trackPeak = parseGain(tag.replayGainTrackPeak.firstOrNull);
        rg.albumPeak = parseGain(tag.replayGainAlbumPeak.firstOrNull);
      case Mp3Metadata():
        final custom = {for (final e in tag.customMetadata.entries) e.key.toUpperCase(): e.value};
        rg.trackGain = parseGain(custom['REPLAYGAIN_TRACK_GAIN']);
        rg.albumGain = parseGain(custom['REPLAYGAIN_ALBUM_GAIN']);
        rg.trackPeak = parseGain(custom['REPLAYGAIN_TRACK_PEAK']);
        rg.albumPeak = parseGain(custom['REPLAYGAIN_ALBUM_PEAK']);
      default:
        break;
    }
  } catch (_) {
    // Not every container carries ReplayGain, and some parsers throw on it.
  }
  return rg;
}

/// Parsers report bits per second for some formats and kbps for others.
int _kbps(int? bitrate) {
  if (bitrate == null || bitrate <= 0) return 0;
  return bitrate > 10000 ? (bitrate / 1000).round() : bitrate;
}

String _imageExt(String mime, Uint8List bytes) {
  final m = mime.toLowerCase();
  if (m.contains('png')) return 'png';
  if (m.contains('webp')) return 'webp';
  if (m.contains('jpeg') || m.contains('jpg')) return 'jpg';
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
  return 'jpg';
}

/// Saves cover bytes under [artDir], named by content so albums sharing a
/// cover share one file. Returns its path, or null if it could not be saved.
Future<String?> saveCover(Directory artDir, Uint8List bytes, String mime) async {
  if (bytes.isEmpty) return null;
  try {
    final file = File('${artDir.path}${Platform.pathSeparator}${md5.convert(bytes)}.${_imageExt(mime, bytes)}');
    if (!await file.exists()) {
      await artDir.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  } on FileSystemException {
    return null;
  }
}

Future<String?> _readText(LocalFileSource source, String path) async {
  final opened = await source.open(path);
  try {
    final bytes = await opened.file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('﻿', '');
    return text.trim().isEmpty ? null : text;
  } on FileSystemException {
    return null;
  } finally {
    await opened.close();
  }
}

/// Reads one file's tags. Unreadable tags never drop the song: it is listed
/// under its file name so it can still be played.
Future<ScannedTrack> readTrack({
  required LocalFileSource source,
  required ScanEntry entry,
  required String folderId,
  required String fingerprint,
  required Directory artDir,
  ScanEntry? lyricsFile,
  ScanEntry? folderArt,
}) async {
  AudioMetadata? meta;
  _ReplayGain rg = _ReplayGain();
  String? coverPath;

  final opened = await source.open(entry.path);
  try {
    try {
      meta = readMetadata(opened.file, getImage: true);
    } catch (_) {
      meta = null;
    }
    if (meta != null) rg = _readReplayGain(opened.file);
    final pics = meta?.pictures ?? const <Picture>[];
    if (pics.isNotEmpty) {
      final pic = pics.firstWhere((p) => p.pictureType == PictureType.coverFront, orElse: () => pics.first);
      coverPath = await saveCover(artDir, pic.bytes, pic.mimetype);
    }
  } finally {
    await opened.close();
  }

  if (coverPath == null && folderArt != null) {
    final art = await source.open(folderArt.path);
    try {
      coverPath = await saveCover(artDir, await art.file.readAsBytes(), extensionOf(folderArt.name));
    } on FileSystemException {
      coverPath = null;
    } finally {
      await art.close();
    }
  }

  var lyrics = lyricsFile == null ? null : await _readText(source, lyricsFile.path);
  final tagLyrics = meta?.lyrics?.trim();
  if (lyrics == null && tagLyrics != null && tagLyrics.isNotEmpty) lyrics = tagLyrics;

  String clean(String? s) => (s ?? '').trim();
  final title = clean(meta?.title);
  final artist = clean(meta?.artist);
  final album = clean(meta?.album);
  return ScannedTrack(
    path: entry.path,
    songId: localSongIdFor(entry.path),
    folderId: folderId,
    fingerprint: fingerprint,
    title: title.isNotEmpty ? title : baseNameOf(entry.name),
    artist: artist.isNotEmpty ? artist : 'Unknown Artist',
    album: album.isNotEmpty ? album : 'Unknown Album',
    albumArtist: clean(meta?.albumArtist),
    genre: (meta?.genres ?? const <String>[]).where((g) => g.trim().isNotEmpty).join(', '),
    track: meta?.trackNumber ?? 0,
    disc: meta?.discNumber ?? 0,
    year: meta?.year?.year ?? 0,
    durationSec: meta?.duration?.inSeconds ?? 0,
    bitRate: _kbps(meta?.bitrate),
    suffix: extensionOf(entry.name),
    trackGain: rg.trackGain,
    albumGain: rg.albumGain,
    trackPeak: rg.trackPeak,
    albumPeak: rg.albumPeak,
    coverPath: coverPath,
    lyrics: lyrics,
  );
}
