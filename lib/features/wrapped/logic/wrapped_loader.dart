import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../ai_shuffle/data/models/replay_response.dart';
import '../data/wrapped_models.dart';
import 'wrapped_builder.dart';

/// Where a Wrapped is kept so it opens at once, and offline.
abstract class WrappedStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Where an account's year is kept: one copy per server, user and year.
String wrappedStoreKey(String serverUrl, String username, int year) =>
    'wrapped_v1_${serverUrl.trim().toLowerCase()}|${username.trim().toLowerCase()}_$year';

/// How far a Wrapped has got. Until it is [settled] the days (streak, biggest day) are not known yet.
class WrappedLoad {
  final WrappedData data;
  final bool settled;

  /// Months answered, of how many were asked.
  final int done;
  final int total;
  const WrappedLoad(this.data, {required this.settled, this.done = 0, this.total = 0});
}

/// Months asked of the server side by side.
const _parallel = 5;

/// The Wrapped of [year], in stages. A kept copy is given at once and is the only event: the server is asked behind
/// it and the answer kept for next time. With none, the year comes as soon as it answers, then each month is counted
/// in, then the settled whole. A month is asked twice before it is given up; with one missing, the days are left out
/// rather than guessed. The copy is kept even when nobody is listening any more.
Stream<WrappedLoad> watchWrapped({
  required int year,
  required int currentYear,
  required String storeKey,
  required WrappedStore store,
  required Future<YearlyReplayResponse> Function(int year) fetchYear,
  required Future<MonthlyReplayResponse> Function(int year, int month) fetchMonth,
  Duration yearTimeout = const Duration(seconds: 45),
  Duration monthTimeout = const Duration(seconds: 20),
  void Function(String)? log,
}) {
  final say = log ?? (m) => debugPrint('[Wrapped] $m');
  final out = StreamController<WrappedLoad>();
  final clock = Stopwatch()..start();
  void emit(WrappedLoad l) {
    if (!out.isClosed && out.hasListener) out.add(l);
  }

  Future<void> run() async {
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
    final quiet = kept != null;
    say('kept copy ${kept == null ? 'none' : 'found'}, ${clock.elapsedMilliseconds} ms');
    if (kept != null) {
      emit(WrappedLoad(kept, settled: true));
      if (keptIsFinal) return;
    }

    final YearlyReplayResponse y;
    final yearClock = Stopwatch()..start();
    try {
      y = await fetchYear(year).timeout(yearTimeout);
      say('year ${yearClock.elapsedMilliseconds} ms');
    } catch (e) {
      say('year failed after ${yearClock.elapsedMilliseconds} ms (${e.runtimeType})');
      if (quiet) return;
      rethrow;
    }
    final wanted = [
      for (final c in y.monthlyCards)
        if (c.totalPlays > 0) c.month,
    ];
    final first = buildWrapped(y, const []);
    if (!quiet && !first.isEmpty) emit(WrappedLoad(first, settled: false, total: wanted.length));

    final months = <MonthlyReplayResponse>[];
    var complete = true;
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < wanted.length) {
        final m = wanted[next++];
        final one = Stopwatch()..start();
        MonthlyReplayResponse? got;
        for (var attempt = 0; attempt < 2 && got == null; attempt++) {
          try {
            got = await fetchMonth(year, m).timeout(monthTimeout);
          } on TimeoutException {
            break; // a slow server is not asked twice
          } catch (_) {
            // asked once more
          }
        }
        say('month $m ${got == null ? 'failed after ' : ''}${one.elapsedMilliseconds} ms');
        got == null ? complete = false : months.add(got);
        done++;
        if (!quiet && done < wanted.length) emit(WrappedLoad(first, settled: false, done: done, total: wanted.length));
      }
    }

    if (!first.isEmpty) await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    final build = Stopwatch()..start();
    final data = complete ? buildWrapped(y, months) : first;
    say('build ${build.elapsedMilliseconds} ms');
    if (!quiet) emit(WrappedLoad(data, settled: true, done: done, total: wanted.length));
    say('settled ${clock.elapsedMilliseconds} ms, ${months.length} of ${wanted.length} months');
    if (complete && !data.isEmpty) {
      try {
        await store.write(storeKey, jsonEncode({'final': year < currentYear, 'data': data.toJson()}));
      } catch (_) {
        // not being able to keep a copy never stops the film
      }
    }
  }

  out.onListen = () => run()
      .catchError((Object e, StackTrace s) {
        if (out.hasListener) out.addError(e, s);
      })
      .whenComplete(out.close);
  return out.stream;
}
