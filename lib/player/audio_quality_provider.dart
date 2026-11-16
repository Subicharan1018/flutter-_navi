import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import 'audio_quality.dart';

/// How the current song's source was opened (stream, converted, or a file on
/// this device). Null while nothing plays. Re-evaluated on a song change, which
/// is when a source is built.
final streamQualityProvider = Provider<StreamQuality?>((ref) {
  final id = ref.watch(playerProvider.select((s) => s.currentSong?.id));
  if (id == null) return null;
  return StreamQualityRegistry.instance.of(id);
});

/// The quality line for the playing song: `Lossless · FLAC · 24-bit/96 kHz`.
final currentAudioQualityProvider = Provider<String?>((ref) {
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  if (song == null) return null;
  return audioQualityFor(song, ref.watch(streamQualityProvider));
});

/// Shared by every surface that names a song's quality.
String? audioQualityFor(Song song, StreamQuality? stream) => AudioQualityLabel.of(song, stream: stream);
