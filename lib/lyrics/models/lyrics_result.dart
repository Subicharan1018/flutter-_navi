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

  /// Where the text came from, for the source chip: a [LyricsSource.wire]
  /// name, `server` (the Navidrome file's own tags), `lrclib` or `device`.
  /// Null when unknown (nothing found).
  final String? source;

  /// True when [type] is [LyricsType.none] because a source could not be
  /// reached (timeout, 429, 5xx, no network) — NOT because every source said
  /// it has nothing. Such a result is never remembered as "no lyrics".
  final bool unreachable;

  const LyricsResult({
    required this.type,
    this.lyrics,
    this.rawText,
    this.source,
    this.unreachable = false,
  });

  /// Every source answered and none has these lyrics.
  factory LyricsResult.none() => const LyricsResult(type: LyricsType.none);

  /// Nothing found, but at least one source did not answer: ask again later.
  factory LyricsResult.unreachable() =>
      const LyricsResult(type: LyricsType.none, unreachable: true);

  /// True when at least one line carries per-word timing.
  bool get wordSynced => lyrics?.lines.any((l) => l.hasWordTimestamps) ?? false;

  LyricsResult withSource(String? source) => LyricsResult(
    type: type,
    lyrics: lyrics,
    rawText: rawText,
    source: source,
    unreachable: unreachable,
  );

  // ── Cache serialisation ──────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'rawText': rawText ?? '',
    if (source != null) 'source': source,
  };

  factory LyricsResult.fromJson(
    Map<String, dynamic> json,
    SyncedLyrics? Function(String type, String text) parser,
  ) {
    final typeName = json['type']?.toString() ?? 'none';
    final raw = json['rawText']?.toString() ?? '';
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
      source: json['source']?.toString(),
    );
  }
}
