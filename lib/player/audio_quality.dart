import '../models/song.dart';

/// What the player actually opened for the current song: the file on this
/// device, or a stream with the transcoding values the URL was built with.
/// Recorded when the source is built, so a Settings change made mid-song
/// never changes what the label says.
class StreamQuality {
  /// A file on this device (download, play cache or device library).
  final bool local;

  /// Requested codec (`mp3`, `opus`…); null or `raw` = the original.
  final String? format;

  /// Requested ceiling in kbps; 0 = none.
  final int maxBitRate;

  const StreamQuality({this.local = false, this.format, this.maxBitRate = 0});

  const StreamQuality.local() : this(local: true);

  String? get _codec {
    final f = format?.trim().toLowerCase();
    return f == null || f.isEmpty || f == 'raw' ? null : f;
  }

  @override
  bool operator ==(Object other) =>
      other is StreamQuality && other.local == local && other._codec == _codec && other.maxBitRate == maxBitRate;

  @override
  int get hashCode => Object.hash(local, _codec, maxBitRate);
}

/// What the audio handler opened for each song, written when a source is
/// built and read by the UI. A plain registry (not the handler) so screens
/// can show quality without a handler existing, as in widget tests.
class StreamQualityRegistry {
  StreamQualityRegistry._();
  static final StreamQualityRegistry instance = StreamQualityRegistry._();

  final Map<String, StreamQuality> _byId = {};

  void record(String songId, StreamQuality quality) => _byId[songId] = quality;

  StreamQuality? of(String songId) => _byId[songId];

  void clear() => _byId.clear();
}

const _lossless = {'flac', 'alac', 'wav', 'aiff', 'aif', 'ape', 'wv', 'dsf', 'dff'};

bool isLosslessSuffix(String suffix) => _lossless.contains(suffix.toLowerCase());

/// The one line that says what is playing, honestly:
///
/// * lossless: `Lossless · FLAC · 24-bit/96 kHz` (depth and rate only when known)
/// * lossy: `MP3 · 320 kbps`
/// * transcoded by the server: `MP3 · 192 kbps (converted)`
///
/// Null when nothing is known.
class AudioQualityLabel {
  const AudioQualityLabel._();

  static String? of(Song song, {StreamQuality? stream}) {
    final suffix = song.suffix.toLowerCase();
    if (stream != null && !stream.local && _isConverted(song, stream)) return _converted(song, stream);
    if (isLosslessSuffix(suffix)) {
      return ['Lossless', suffix.toUpperCase(), ?_depthAndRate(song)].join(' · ');
    }
    if (suffix.isEmpty && song.bitRate <= 0) return null;
    return [
      if (suffix.isNotEmpty) suffix.toUpperCase(),
      if (song.bitRate > 0) '${song.bitRate} kbps',
    ].join(' · ');
  }

  /// Whether the server changes what it sends: another codec, or a ceiling
  /// the original is above (a lossless file always is).
  static bool _isConverted(Song song, StreamQuality s) {
    final suffix = song.suffix.toLowerCase();
    final codec = s._codec;
    if (codec != null && codec != suffix) return true;
    if (s.maxBitRate <= 0) return false;
    return isLosslessSuffix(suffix) || song.bitRate <= 0 || song.bitRate > s.maxBitRate;
  }

  static String _converted(Song song, StreamQuality s) {
    final codec = s._codec;
    // The server stops at the ceiling, or at the original if that is lower.
    final kbps = s.maxBitRate > 0
        ? (!isLosslessSuffix(song.suffix) && song.bitRate > 0 && song.bitRate < s.maxBitRate ? song.bitRate : s.maxBitRate)
        : 0;
    final parts = [
      if (codec != null) codec.toUpperCase(),
      if (kbps > 0) '$kbps kbps',
    ];
    return parts.isEmpty ? 'Converted' : '${parts.join(' · ')} (converted)';
  }

  static String? _depthAndRate(Song song) {
    final depth = song.bitDepth > 0 ? '${song.bitDepth}-bit' : null;
    final rate = song.samplingRate > 0 ? formatSamplingRate(song.samplingRate) : null;
    if (depth != null && rate != null) return '$depth/$rate';
    return depth ?? rate;
  }
}

/// 44100 → `44.1 kHz`, 96000 → `96 kHz`.
String formatSamplingRate(int hz) {
  final k = hz / 1000;
  final text = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
  return '$text kHz';
}
