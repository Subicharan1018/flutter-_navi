// =============================================================================
// ContributionGraphResponse — model for GET /listening-log/contribution-graph
// API returns: { "data": [ { "date_str": "2024-11-30", "count": 24 } ] }
// =============================================================================

import '../../../../utils/format.dart' show isoDate;

class ContributionDay {
  final String date;
  final int count;

  const ContributionDay({required this.date, required this.count});

  factory ContributionDay.fromJson(Map<String, dynamic> json) {
    return ContributionDay(
      // API field is "date_str", not "date"
      date: json['date_str']?.toString() ?? json['date']?.toString() ?? '',
      count: _parseInt(json['count']),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// Consecutive days with a play, counted from the whole daily history. Today
/// not being played yet doesn't end it; a missed day does.
///
/// The stats endpoint's `streak_days` can't be used for this: it only looks at
/// the selected period's rows (a week never shows more than the days since
/// Monday) and reads 0 until the first play of the day.
int listeningStreak(List<ContributionDay> days, DateTime now) {
  final played = {
    for (final d in days)
      if (d.count > 0) d.date,
  };
  // Calendar arithmetic, not 24-hour steps, so a clock change can't skip a day.
  bool on(int daysAgo) =>
      played.contains(isoDate(DateTime(now.year, now.month, now.day - daysAgo)));
  var ago = on(0) ? 0 : 1;
  var streak = 0;
  while (on(ago++)) {
    streak++;
  }
  return streak;
}

class ContributionGraphResponse {
  final List<ContributionDay> days;

  const ContributionGraphResponse({required this.days});

  factory ContributionGraphResponse.fromJson(Map<String, dynamic> json) {
    // API returns "data", not "days"
    final list = (json['data'] ?? json['days']) as List<dynamic>? ?? [];
    return ContributionGraphResponse(
      days: list
          .map((e) => ContributionDay.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
