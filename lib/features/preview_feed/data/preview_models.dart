import 'package:flutter/foundation.dart';

/// Where a preview came from, as the server says it.
enum PreviewSource {
  chart('Trending'),
  release('New release'),
  friend('A friend hearted this'),
  other('');

  const PreviewSource(this.label);
  final String label;

  static PreviewSource parse(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => other);
}

/// One 30 s clip of a song that is not in the library.
@immutable
class PreviewItem {
  /// The server's key for the song (stable per title + first artist).
  final String key;
  final String title;
  final String artist;
  final String album;
  final String? artUrl;
  final String previewUrl;
  final PreviewSource source;

  /// "Trending · tamil #1", "New release": why it is in the feed.
  final String reason;

  const PreviewItem({
    required this.key,
    required this.title,
    required this.artist,
    required this.previewUrl,
    this.album = '',
    this.artUrl,
    this.source = PreviewSource.other,
    this.reason = '',
  });

  factory PreviewItem.fromJson(Map<String, dynamic> j) {
    final art = j['art_url'];
    return PreviewItem(
      key: (j['key'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      artUrl: art is String && art.isNotEmpty ? art : null,
      previewUrl: (j['preview_url'] ?? '').toString(),
      source: PreviewSource.parse(j['source']),
      reason: (j['reason'] ?? '').toString(),
    );
  }

  /// What the fetcher is asked for: the same words a person would type into Search online.
  String get query => '$title $artist'.trim();

  bool get playable =>
      key.isNotEmpty && title.isNotEmpty && previewUrl.startsWith('http');

  @override
  bool operator ==(Object other) =>
      other is PreviewItem &&
      other.key == key &&
      other.previewUrl == previewUrl;

  @override
  int get hashCode => Object.hash(key, previewUrl);
}

/// A page of the feed and what is left of today's hearts.
@immutable
class PreviewFeedPage {
  final List<PreviewItem> items;
  final int remaining;
  final int cap;
  const PreviewFeedPage({
    required this.items,
    required this.remaining,
    required this.cap,
  });

  factory PreviewFeedPage.fromJson(Map<String, dynamic> j) => PreviewFeedPage(
    items: [
      for (final e in (j['items'] as List? ?? const []))
        if (e is Map) PreviewItem.fromJson(Map<String, dynamic>.from(e)),
    ].where((i) => i.playable).toList(),
    remaining: (j['remaining'] as num?)?.toInt() ?? 0,
    cap: (j['cap'] as num?)?.toInt() ?? 0,
  );
}

/// The answer to a yes/no signal: today's allowance after it.
@immutable
class PreviewSignalResult {
  final int remaining;
  final bool capReached;
  const PreviewSignalResult({required this.remaining, this.capReached = false});
}
