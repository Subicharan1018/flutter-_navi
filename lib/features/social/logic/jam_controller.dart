import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../data/social_api.dart';
import '../data/social_models.dart';
import 'jam_sync.dart';
import 'social_providers.dart';

/// What the Jam screens show.
class JamUiState {
  final JamState? jam;

  /// A one-off line for the screen to show ("The host ended this Jam").
  final String? notice;
  final bool busy;

  /// How far this phone's playhead is from where the Jam says it should be,
  /// in ms (null while paused, hosting, or not measured yet).
  final int? driftMs;
  const JamUiState({this.jam, this.notice, this.busy = false, this.driftMs});

  bool get active => jam != null;
}

/// Holds the Jam this phone is in and keeps the player in step with it.
///
/// Everyone polls the server about once a second. Each phone applies the
/// Jam's queue/playhead to its own player; the host's phone also publishes
/// what its player does (play, pause, skip, seek) so the others follow.
/// While in a Jam the Jam's queue owns the player: if you start other music,
/// the next change from the Jam takes the player back.
class JamController extends Notifier<JamUiState> {
  static const _pollEvery = Duration(seconds: 1);

  Timer? _timer;
  bool _polling = false;
  bool _publishing = false;
  bool _applying = false;
  final JamClock _clock = JamClock();

  // What the player was last told, to apply only what changed.
  List<int> _appliedIds = const []; // Jam item ids
  List<String> _appliedSongIds = const []; // what the player's queue should hold
  JamState? _pending;
  int _appliedIndex = -1;
  bool _appliedPlaying = false;
  int _version = 0;
  int _quietUntilMs = 0; // after we drive the player, don't read its echo as a user action
  int _lastCorrectionMs = 0;

  SocialApi get _api => ref.read(socialApiProvider);
  PlayerNotifier get _player => ref.read(playerProvider.notifier);
  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  @override
  JamUiState build() {
    ref.onDispose(_stopTimer);
    // Back from the background (or a locked screen): catch up at once instead
    // of waiting for the next timer beat.
    final lifecycle = AppLifecycleListener(onResume: () {
      if (state.active) unawaited(_tick());
    });
    ref.onDispose(lifecycle.dispose);
    // A different account has no claim on this Jam.
    ref.listen(settingsProvider.select((s) => s.username), (prev, next) {
      if (prev != next) _reset();
    });
    return const JamUiState();
  }

  // ── entering and leaving ────────────────────────────────────────────────

  /// Picks up a Jam this account is already in (after an app restart).
  Future<void> restore() async {
    if (state.active) return;
    final user = ref.read(settingsProvider).username;
    if (user.isEmpty) return;
    try {
      final jam = await _api.jamCurrent();
      if (jam != null && !state.active) _enter(jam);
    } on SocialException {
      // Nothing to restore; the Jam screens retry when opened.
    }
  }

  Future<bool> start() => _run(() async => _enter(await _api.jamCreate()));

  Future<bool> join(String code) => _run(() async => _enter(await _api.jamJoin(code)));

  Future<void> leave() async {
    final code = state.jam?.code;
    _reset();
    if (code != null) {
      try {
        await _api.jamLeave(code);
      } on SocialException {
        // The server drops silent members itself.
      }
    }
  }

  Future<void> end() async {
    final code = state.jam?.code;
    if (code == null) return;
    await _run(() async {
      await _api.jamEnd(code);
      _reset();
    });
  }

  void clearNotice() {
    if (state.notice != null) state = JamUiState(jam: state.jam, busy: state.busy);
  }

  // ── queue and host controls ─────────────────────────────────────────────

  Future<bool> addSongs(List<Song> songs) => _withJam((code) async => _accept(await _api.jamAddSongs(code, songs)));

  Future<bool> removeItem(int itemId) =>
      _withJam((code) async => _accept(await _api.jamRemoveItem(code, itemId)));

  Future<bool> togglePlay() {
    final jam = state.jam;
    if (jam == null) return Future.value(false);
    return _control(jam.playing ? 'pause' : 'play', positionMs: _localPositionMs());
  }

  Future<bool> next() => _control('next');
  Future<bool> previous() => _control('prev', positionMs: _localPositionMs());
  Future<bool> jumpTo(int index) => _control('jump', index: index);
  Future<bool> seek(int ms) => _control('seek', positionMs: ms);

  /// Host: drag queue item [itemId] to position [toIndex].
  Future<bool> moveItem(int itemId, int toIndex) => _withJam(
        (code) async => _accept(await _api.jamControl(code, 'move', index: toIndex, itemId: itemId)),
      );

  Future<bool> _control(String action, {int? positionMs, int? index}) => _withJam(
        (code) async => _accept(await _api.jamControl(code, action, positionMs: positionMs, index: index)),
      );

  // ── plumbing ────────────────────────────────────────────────────────────

  Future<bool> _withJam(Future<void> Function(String code) call) async {
    final code = state.jam?.code;
    if (code == null) return false;
    return _run(() => call(code));
  }

  Future<bool> _run(Future<void> Function() call) async {
    state = JamUiState(jam: state.jam, busy: true);
    try {
      await call();
      if (state.busy) state = JamUiState(jam: state.jam);
      return true;
    } on SocialException catch (e) {
      if (e.ended || (e.notInJam && state.jam != null)) {
        _reset(notice: e.ended ? 'This Jam has ended.' : 'You’re no longer in this Jam.');
      } else {
        state = JamUiState(jam: state.jam, notice: e.message);
      }
      return false;
    }
  }

  void _enter(JamState jam) {
    _appliedIds = const [];
    _appliedSongIds = const [];
    _appliedIndex = -1;
    _appliedPlaying = false;
    _version = 0;
    state = JamUiState(jam: jam);
    _timer ??= Timer.periodic(_pollEvery, (_) => _tick());
    unawaited(_apply(jam));
  }

  void _reset({String? notice}) {
    _stopTimer();
    _appliedIds = const [];
    _appliedSongIds = const [];
    _appliedIndex = -1;
    _pending = null;
    state = JamUiState(notice: notice);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final jam = state.jam;
    if (jam == null || _polling) return;
    _polling = true;
    try {
      final t0 = _nowMs;
      final poll = await _api.jamPoll(jam.code, _version == 0 ? jam.version : _version);
      _clock.add(t0, _nowMs, poll.serverMs);
      final fresh = poll.state;
      if (fresh != null) _accept(fresh);
      await _hostPublish();
      await _correctDrift();
    } on SocialException catch (e) {
      if (e.ended) {
        _reset(notice: 'This Jam has ended.');
      } else if (e.notInJam) {
        await _rejoinOrLeave(jam.code);
      }
      // Network blips just skip a beat; the next poll catches up.
    } finally {
      _polling = false;
    }
  }

  /// Dropped for being silent too long (a tunnel hiccup): try the code once.
  Future<void> _rejoinOrLeave(String code) async {
    try {
      _enter(await _api.jamJoin(code));
    } on SocialException {
      _reset(notice: 'You’re no longer in this Jam.');
    }
  }

  void _accept(JamState fresh) {
    if (state.jam == null) return;
    final old = state.jam!;
    _version = fresh.version;
    state = JamUiState(jam: fresh, notice: state.notice);
    if (!old.youAreHost && fresh.youAreHost) {
      state = JamUiState(jam: fresh, notice: 'You’re the host now.');
    }
    unawaited(_apply(fresh));
  }

  int _localPositionMs() => _player.player.position.inMilliseconds;

  /// Brings the player in line with [jam]. Only what changed is applied, so a
  /// listener who paused locally isn't resumed by an unrelated queue change.
  Future<void> _apply(JamState jam) async {
    if (_applying) {
      _pending = jam; // applied as soon as the current pass finishes
      return;
    }
    _applying = true;
    try {
      final player = _player..permitClaim(); // being in a Jam is a person's choice to play here
      final nextIds = [for (final q in jam.queue) q.id];
      final songs = [for (final q in jam.queue) q.toSong()];
      if (songs.isEmpty) return;

      final localIds = [for (final s in ref.read(playerProvider).queue) s.id];
      final detached = _appliedIds.isNotEmpty && !listEquals(localIds, _appliedSongIds);
      final diff = detached || _appliedIds.isEmpty
          ? const QueueDiff(QueueChange.replace)
          : diffQueue(_appliedIds, nextIds, ref.read(playerProvider).currentIndex);

      final target = projectPositionMs(jam, _clock.serverNow(_nowMs));
      _quietUntilMs = _nowMs + 2500;
      var rebuilt = false;
      switch (diff.change) {
        case QueueChange.none:
          break;
        case QueueChange.append:
          await player.addAllToQueue(songs.sublist(diff.at));
        case QueueChange.removeOne:
          await player.removeFromQueue(diff.at);
        case QueueChange.move:
          await player.reorderQueue(diff.at, diff.to);
        case QueueChange.replace:
          await player.setQueue(songs, jam.index.clamp(0, songs.length - 1));
          rebuilt = true;
      }
      final indexChanged = jam.index != _appliedIndex;
      final playingChanged = jam.playing != _appliedPlaying;
      _appliedIds = nextIds;
      _appliedSongIds = [for (final s in songs) s.id];

      final curIdx = ref.read(playerProvider).currentIndex;
      if (!rebuilt && curIdx != jam.index) {
        await player.jumpTo(jam.index);
        rebuilt = true;
      }
      if (rebuilt || indexChanged) {
        await player.seekMs(target < 0 ? 0 : target);
      }
      if (rebuilt || playingChanged || indexChanged) {
        if (jam.playing) {
          await player.play();
        } else {
          await player.pause();
        }
      }
      _appliedIndex = jam.index;
      _appliedPlaying = jam.playing;
      _quietUntilMs = _nowMs + 2500;
    } catch (e) {
      debugPrint('[Jam] apply failed: $e');
    } finally {
      _applying = false;
      final again = _pending;
      _pending = null;
      if (again != null && state.jam != null) unawaited(_apply(again));
    }
  }

  /// A listener whose playhead strayed (buffering, a call) is pulled back.
  Future<void> _correctDrift() async {
    final jam = state.jam;
    if (jam == null || jam.youAreHost || !jam.playing || _applying) {
      _showDrift(null);
      return;
    }
    final now = _nowMs;
    final ps = ref.read(playerProvider);
    if (!ps.isPlaying || ps.currentIndex != jam.index) {
      _showDrift(null);
      return;
    }
    final target = projectPositionMs(jam, _clock.serverNow(now));
    _showDrift((_localPositionMs() - target).abs());
    if (now - _lastCorrectionMs < 4000 || now < _quietUntilMs) return;
    if (needsDriftCorrection(_localPositionMs(), target)) {
      _lastCorrectionMs = now;
      _quietUntilMs = now + 1500;
      await _player.seekMs(target);
    }
  }

  /// Publishes the drift to the screens only when it crosses a visible band.
  void _showDrift(int? ms) {
    final band = ms == null ? null : (ms <= jamDriftToleranceMs ? 0 : 1);
    final was = state.driftMs == null ? null : (state.driftMs! <= jamDriftToleranceMs ? 0 : 1);
    if (band == was && (ms == null) == (state.driftMs == null)) return;
    state = JamUiState(jam: state.jam, notice: state.notice, busy: state.busy, driftMs: ms);
  }

  /// The host's phone reports what its player is doing.
  Future<void> _hostPublish() async {
    final jam = state.jam;
    if (jam == null || !jam.youAreHost || _publishing || _applying) return;
    if (_nowMs < _quietUntilMs) return;
    final ps = ref.read(playerProvider);
    // Only while the player still holds the Jam's queue: other music isn't the Jam.
    final localIds = [for (final s in ps.queue) s.id];
    if (!listEquals(localIds, [for (final q in jam.queue) q.songId])) return;
    final act = hostPublish(
      server: jam,
      serverNowMs: _clock.serverNow(_nowMs),
      localIndex: ps.currentIndex,
      localPlaying: ps.isPlaying,
      localPositionMs: _localPositionMs(),
    );
    if (act == null) return;
    _publishing = true;
    try {
      final fresh = await _api.jamControl(jam.code, act.action, positionMs: act.positionMs, index: act.index);
      _version = fresh.version;
      _appliedIndex = fresh.index;
      _appliedPlaying = fresh.playing;
      state = JamUiState(jam: fresh, notice: state.notice);
    } on SocialException {
      // Next tick retries.
    } finally {
      _publishing = false;
    }
  }
}

final jamControllerProvider = NotifierProvider<JamController, JamUiState>(JamController.new);
