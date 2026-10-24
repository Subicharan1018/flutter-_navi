/// POST /intent — what the server understood from "describe a mix", and the
/// library titles that fit it (sent on to /next in candidates mode).
class IntentResponse {
  /// "Tamil · Melody · calm" — empty when nothing was understood.
  final String summary;
  final List<String> candidates;
  final int count;

  /// Filters loosened because too few songs matched ("mood", "era", …).
  final List<String> relaxed;

  /// The AI read the request (otherwise keyword rules did).
  final bool ai;
  final bool understood;

  const IntentResponse({
    required this.summary,
    required this.candidates,
    required this.count,
    this.relaxed = const [],
    this.ai = false,
    this.understood = true,
  });

  static const _relaxedLabels = {'years': 'era', 'genres': 'genre'};

  factory IntentResponse.fromJson(Map<String, dynamic> j) => IntentResponse(
        summary: j['summary'] as String? ?? '',
        candidates: [for (final c in (j['candidates'] as List? ?? const [])) c.toString()],
        count: (j['count'] as num?)?.toInt() ?? 0,
        relaxed: [
          for (final r in (j['relaxed'] as List? ?? const [])) _relaxedLabels[r] ?? r.toString(),
        ],
        ai: j['ai'] == true,
        understood: j['understood'] != false,
      );
}
