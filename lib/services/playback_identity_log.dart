import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/hive_boxes.dart';

/// Evidence for "the song I hear is not the song on screen".
///
/// The audio handler notes every queue and skip operation here, and compares
/// the song in the player with the song the app shows once things are quiet.
/// A difference is printed (logcat keeps it in release builds too) and saved on
/// the device with the operations that led to it, so it can be read afterwards.
class PlaybackIdentityLog {
  static const String hiveKey = 'playback_mismatch_log';
  static const int _opsKept = 25;
  static const int _reportsKept = 10;

  final Queue<String> _ops = Queue<String>();
  String? _lastReported;

  /// The most recent report, for tests and diagnostics.
  String? lastReport;

  void note(String op) {
    _ops.add('${DateTime.now().toIso8601String().substring(11, 23)} $op');
    if (_ops.length > _opsKept) _ops.removeFirst();
  }

  /// [heard] is the song loaded in the player, [current] the one the queue says
  /// is playing, [published] the one on the notification and [onScreen] the one
  /// the app draws. Null means "not known" and is not compared. Returns true
  /// when they disagree.
  bool check({
    required String? heard,
    required String? current,
    required String? published,
    required String? onScreen,
    required String detail,
  }) {
    if (heard == null) return false;
    final wrong = [
      if (current != null && current != heard) 'queue',
      if (published != null && published != heard) 'notification',
      if (onScreen != null && onScreen != heard) 'screen',
    ];
    if (wrong.isEmpty) {
      _lastReported = null;
      return false;
    }
    final key = '$heard|$current|$published|$onScreen';
    if (key == _lastReported) return true; // already written down
    _lastReported = key;
    final report = '[PlayMismatch] ${DateTime.now().toIso8601String()} wrong: ${wrong.join(', ')} | '
        'heard=$heard queue=$current notification=$published screen=$onScreen | $detail\n'
        '  recent: ${_ops.join(' ; ')}';
    lastReport = report;
    debugPrint('🚨 $report');
    try {
      final saved = HiveBoxes.session.get(hiveKey);
      final list = [if (saved is List) ...saved.whereType<String>(), report];
      HiveBoxes.session.put(hiveKey, list.length > _reportsKept ? list.sublist(list.length - _reportsKept) : list);
    } catch (_) {
      // Bookkeeping only (boxes not open in some tests).
    }
    return true;
  }
}
