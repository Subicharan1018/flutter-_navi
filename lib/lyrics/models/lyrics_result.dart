import 'lyric_line.dart';

enum LyricsType { synced, plain, none }

/// Holds the result of a lyrics fetch — type discriminates the three cases.
class LyricsResult {
  final LyricsType type;

  /// Parsed lyrics. Non-null when [type] is [LyricsType.synced] or
  /// [LyricsType.plain]. Null when [type] is [LyricsType.none].
  final SyncedLyrics? lyrics;

  /// The original raw string (LRC or plain text) used to populate [lyrics].
  /// Stored in cache so re-parsing on cold-start is cheap and lossless.
  final String? rawText;

  const LyricsResult({required this.type, this.lyrics, this.rawText});

  factory LyricsResult.none() => const LyricsResult(type: LyricsType.none);

  // ── Cache serialisation ──────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'rawText': rawText ?? '',
  };

  factory LyricsResult.fromJson(
    Map<String, dynamic> json,
    SyncedLyrics? Function(String type, String text) parser,
  ) {
    final typeName = json['type'] as String? ?? 'none';
    final raw = json['rawText'] as String? ?? '';
    final t = LyricsType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => LyricsType.none,
    );
    return LyricsResult(
      type: t,
      lyrics: (t != LyricsType.none && raw.isNotEmpty)
          ? parser(t.name, raw)
          : null,
      rawText: raw,
    );
  }
}
