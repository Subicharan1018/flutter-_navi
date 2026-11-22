import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/library_provider.dart' show isOfflineProvider;

/// Decides when the "Offline. Playing what's already loaded." notice shows.
///
/// One notice per outage: it appears once the connection has been gone for
/// [showAfter] (a blink never flashes it) and clears once the connection has
/// been back for [clearAfter]. A connection that flaps inside that window is
/// still the same outage, so reconnecting over and over never repeats it.
///
/// Pure and clock-free: the caller passes `now`, so it is tested without timers.
class OfflineNoticeGate {
  OfflineNoticeGate({
    this.showAfter = const Duration(milliseconds: 1500),
    this.clearAfter = const Duration(seconds: 5),
  });

  final Duration showAfter;
  final Duration clearAfter;

  bool _offline = false;
  DateTime? _since;
  bool _visible = false;

  bool get visible => _visible;

  /// Feed the current connectivity. Returns whether the notice is visible now.
  bool update({required bool offline, required DateTime now}) {
    if (offline != _offline) {
      _offline = offline;
      _since = now;
    }
    return tick(now);
  }

  /// Re-evaluates with the clock only (call at [nextCheck]).
  bool tick(DateTime now) {
    final since = _since;
    if (since != null) {
      final held = now.difference(since);
      if (_offline && !_visible && held >= showAfter) _visible = true;
      if (!_offline && _visible && held >= clearAfter) _visible = false;
    }
    return _visible;
  }

  /// When [tick] next changes the answer, or null when nothing is pending.
  DateTime? get nextCheck {
    final since = _since;
    if (since == null) return null;
    if (_offline && !_visible) return since.add(showAfter);
    if (!_offline && _visible) return since.add(clearAfter);
    return null;
  }
}

/// True while the offline notice should be on screen.
final offlineNoticeProvider = NotifierProvider<OfflineNoticeNotifier, bool>(
  OfflineNoticeNotifier.new,
);

class OfflineNoticeNotifier extends Notifier<bool> {
  final _gate = OfflineNoticeGate();
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<bool>(isOfflineProvider, (_, offline) => _apply(gateUpdate: offline));
    _gate.update(offline: ref.read(isOfflineProvider), now: DateTime.now());
    _schedule();
    return _gate.visible;
  }

  void _apply({bool? gateUpdate}) {
    final now = DateTime.now();
    final v = gateUpdate == null ? _gate.tick(now) : _gate.update(offline: gateUpdate, now: now);
    if (v != state) state = v;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final at = _gate.nextCheck;
    if (at == null) return;
    final wait = at.difference(DateTime.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () => _apply());
  }
}

/// Whether a restored song has to wait for the network before it can load:
/// offline, and no copy of it on the device.
bool needsNetworkToLoad({
  required bool offline,
  required String songId,
  required bool Function(String id) hasLocalCopy,
}) =>
    offline && !hasLocalCopy(songId);
