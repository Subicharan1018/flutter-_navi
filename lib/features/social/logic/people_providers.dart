import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../data/social_api.dart';
import '../data/social_models.dart';
import 'social_providers.dart';
import 'social_rules.dart';

// ── alert settings (this device) ─────────────────────────────────────────────

/// Where the alert switches live. Hive in the app; swapped for a memory store in tests.
abstract class AlertPrefsStore {
  Map<String, Object?> read();
  void write(Map<String, Object?> value);
}

class HiveAlertPrefsStore implements AlertPrefsStore {
  static const _key = 'friend_alerts_v1';

  @override
  Map<String, Object?> read() {
    try {
      final v = HiveBoxes.prefs.get(_key);
      return v is Map ? Map<String, Object?>.from(v) : const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  void write(Map<String, Object?> value) {
    try {
      HiveBoxes.prefs.put(_key, value);
    } catch (_) {}
  }
}

final alertPrefsStoreProvider = Provider<AlertPrefsStore>((ref) => HiveAlertPrefsStore());

/// "Tell me when a friend starts listening": off until switched on; per-friend
/// mute; quiet hours. Saved on this device.
class FriendAlertSettingsNotifier extends Notifier<FriendAlertSettings> {
  @override
  FriendAlertSettings build() {
    final m = ref.read(alertPrefsStoreProvider).read();
    return FriendAlertSettings(
      enabled: m['enabled'] == true,
      muted: {for (final n in (m['muted'] as List? ?? const [])) n.toString().toLowerCase()},
      quietFromMin: m['quiet_from'] as int?,
      quietToMin: m['quiet_to'] as int?,
    );
  }

  void _set(FriendAlertSettings s) {
    state = s;
    ref.read(alertPrefsStoreProvider).write({
      'enabled': s.enabled,
      'muted': s.muted.toList(),
      'quiet_from': s.quietFromMin,
      'quiet_to': s.quietToMin,
    });
  }

  void setEnabled(bool on) => _set(state.copyWith(enabled: on));

  void setMuted(String friend, bool muted) {
    final next = {...state.muted};
    muted ? next.add(friend.toLowerCase()) : next.remove(friend.toLowerCase());
    _set(state.copyWith(muted: next));
  }

  /// Both null clears quiet hours.
  void setQuietHours(int? fromMin, int? toMin) => _set(state.copyWith(quietFromMin: fromMin, quietToMin: toMin));
}

final friendAlertSettingsProvider =
    NotifierProvider<FriendAlertSettingsNotifier, FriendAlertSettings>(FriendAlertSettingsNotifier.new);

// ── showing an alert ─────────────────────────────────────────────────────────

/// Raises one "friend started listening" notification. The real one (local
/// notifications on Android, a toast on Windows) is set at startup; the default
/// does nothing, so tests and unsupported platforms stay quiet.
abstract class FriendAlertSink {
  Future<void> show(FriendAlert alert);
}

class NoAlertSink implements FriendAlertSink {
  const NoAlertSink();
  @override
  Future<void> show(FriendAlert alert) async {}
}

final friendAlertSinkProvider = Provider<FriendAlertSink>((ref) => const NoAlertSink());

// ── People, polled ───────────────────────────────────────────────────────────

class PeopleState {
  final PeopleList? list;
  final bool loading;
  final bool failed;
  const PeopleState({this.list, this.loading = false, this.failed = false});
}

/// Polls /social/people while social features are on and either the People view
/// is open or friend alerts are switched on. Each poll feeds the alert policy.
///
/// Battery: one small request per [interval] (60 s) and none at all when neither
/// the People view nor alerts need it. It only runs while the app process is
/// alive (the foreground, or while music keeps it running); there is no push
/// service on a self-hosted server.
class PeopleNotifier extends Notifier<PeopleState> {
  static const interval = Duration(seconds: 60);
  static const viewInterval = Duration(seconds: 20);

  Timer? _timer;
  bool _busy = false;
  int _viewers = 0;
  PeopleList? _previous;
  late final FriendAlertPolicy _policy = FriendAlertPolicy();

  @override
  PeopleState build() {
    ref.onDispose(() => _timer?.cancel());
    // Start, stop and re-time whenever the things that decide it change.
    final enabled = ref.watch(socialEnabledProvider);
    final alerts = ref.watch(friendAlertSettingsProvider.select((s) => s.enabled));
    _schedule(enabled && (alerts || _viewers > 0));
    if (!enabled) _previous = null;
    return const PeopleState();
  }

  /// The People view calls this while it is on screen (and the returned
  /// function when it leaves) so the list refreshes quickly while looked at.
  VoidCallback watching() {
    _viewers++;
    _schedule(ref.read(socialEnabledProvider));
    unawaited(refresh());
    var done = false;
    return () {
      if (done) return;
      done = true;
      _viewers--;
      _schedule(ref.read(socialEnabledProvider) && (ref.read(friendAlertSettingsProvider).enabled || _viewers > 0));
    };
  }

  void _schedule(bool on) {
    _timer?.cancel();
    _timer = null;
    if (!on) return;
    _timer = Timer.periodic(_viewers > 0 ? viewInterval : interval, (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy || !ref.read(socialEnabledProvider)) return;
    _busy = true;
    if (state.list == null) state = const PeopleState(loading: true);
    try {
      final list = await ref.read(socialApiProvider).people();
      final alerts = _policy.evaluate(
        previous: _previous,
        current: list,
        settings: ref.read(friendAlertSettingsProvider),
        now: DateTime.now(),
      );
      _previous = list;
      state = PeopleState(list: list);
      for (final a in alerts) {
        unawaited(ref.read(friendAlertSinkProvider).show(a));
      }
    } on SocialException catch (e) {
      debugPrint('[People] ${e.message}');
      state = PeopleState(list: state.list, failed: true);
    } finally {
      _busy = false;
    }
  }
}

final peopleProvider = NotifierProvider<PeopleNotifier, PeopleState>(PeopleNotifier.new);
