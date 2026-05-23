// =============================================================================
// ContributionGraphResponse — model for GET /listening-log/contribution-graph
// API returns: { "data": [ { "date_str": "2024-11-30", "count": 24 } ] }
// =============================================================================

class ContributionDay {
  final String date;
  final int count;

  const ContributionDay({
    required this.date,
    required this.count,
  });

  factory ContributionDay.fromJson(Map<String, dynamic> json) {
    return ContributionDay(
      // API field is "date_str", not "date"
      date: json['date_str'] as String? ?? json['date'] as String? ?? '',
      count: _parseInt(json['count']),
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class ContributionGraphResponse {
  final List<ContributionDay> days;

  const ContributionGraphResponse({
    required this.days,
  });

  factory ContributionGraphResponse.fromJson(Map<String, dynamic> json) {
    // API returns "data", not "days"
    final list = (json['data'] ?? json['days']) as List<dynamic>? ?? [];
    return ContributionGraphResponse(
      days: list
          .map((e) => ContributionDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
