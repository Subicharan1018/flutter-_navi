import 'dart:convert';

import '../../ai_shuffle/data/models/replay_response.dart';
import '../data/wrapped_models.dart';
import 'wrapped_builder.dart';

/// Where a finished Wrapped is kept so it opens offline.
abstract class WrappedStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Where an account's year is kept: one copy per server, user and year.
String wrappedStoreKey(String serverUrl, String username, int year) =>
    'wrapped_v1_${serverUrl.trim().toLowerCase()}|${username.trim().toLowerCase()}_$year';

/// Loads the Wrapped for [year]: a finished past year comes from the device if it is there; otherwise
/// the year and each of its months are asked of the server (two at a time), built, and kept. When the
/// server cannot be reached the kept copy is used; with none, the error reaches the caller.
Future<WrappedData> loadWrapped({
  required int year,
  required int currentYear,
  required String storeKey,
  required WrappedStore store,
  required Future<YearlyReplayResponse> Function(int year) fetchYear,
  required Future<MonthlyReplayResponse> Function(int year, int month) fetchMonth,
}) async {
  WrappedData? kept;
  var keptIsFinal = false;
  try {
    final raw = store.read(storeKey);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      kept = WrappedData.fromJson(Map<String, dynamic>.from(j['data'] as Map));
      keptIsFinal = j['final'] == true; // kept after the year was over
    }
  } catch (_) {
    kept = null; // a damaged copy is as good as none
  }
  if (kept != null && keptIsFinal) return kept;

  try {
    final y = await fetchYear(year);
    final wanted = [
      for (final c in y.monthlyCards)
        if (c.totalPlays > 0) c.month,
    ];
    final months = <MonthlyReplayResponse>[];
    var complete = true;
    for (var i = 0; i < wanted.length; i += 2) {
      final batch = wanted.skip(i).take(2);
      final got = await Future.wait([
        for (final m in batch)
          () async {
            try {
              return await fetchMonth(year, m);
            } catch (_) {
              complete = false;
              return null;
            }
          }(),
      ]);
      months.addAll(got.nonNulls);
    }
    final data = buildWrapped(y, months);
    if (complete && !data.isEmpty) {
      try {
        await store.write(storeKey, jsonEncode({'final': year < currentYear, 'data': data.toJson()}));
      } catch (_) {
        // not being able to keep a copy never stops the story
      }
    }
    return data;
  } catch (_) {
    if (kept != null) return kept;
    rethrow;
  }
}
