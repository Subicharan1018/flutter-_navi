import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../ai_shuffle/data/repositories/shuffle_exception.dart';
import '../../ai_shuffle/logic/shuffle_providers.dart';
import '../../local_library/logic/local_models.dart' show isLocalSongId;
import '../../ai_shuffle/data/models/feedback_request.dart';
import 'play_outbox.dart';
import 'play_outbox_delivery.dart';

/// The device-side queue of undelivered plays, or null where its box is not
/// open (some tests). Callers then fall back to sending directly.
final playOutboxProvider = Provider<PlayOutbox?>((ref) {
  try {
    return PlayOutbox(HiveBoxes.playOutbox);
  } catch (_) {
    return null;
  }
});

/// Whether a delivery attempt can succeed now: signed in and not offline.
bool _canSend(Ref ref) {
  final s = ref.read(settingsProvider);
  return s.serverUrl.isNotEmpty && s.password.isNotEmpty && !ref.read(isOfflineProvider);
}

/// 4xx answers other than "try later" mean the server will never take this
/// play; retrying only fills the queue.
bool _isFinalRefusal(int status) =>
    status >= 400 && status < 500 && status != 401 && status != 408 && status != 425 && status != 429;

final playOutboxDeliveryProvider = Provider<PlayOutboxDelivery?>((ref) {
  final outbox = ref.watch(playOutboxProvider);
  if (outbox == null) return null;
  final delivery = PlayOutboxDelivery(
    outbox: outbox,
    canSend: () => _canSend(ref),
    sendScrobble: (songId, timeMs) =>
        ref.read(subsonicServiceProvider).scrobble(songId, submission: true, timeMs: timeMs, strict: true),
    sendFeedback: (request) async {
      try {
        await ref.read(shuffleApiServiceProvider).postFeedback(request);
      } on ShuffleServerError catch (e) {
        if (_isFinalRefusal(e.statusCode)) throw OutboxRefused('feedback ${e.statusCode}');
        rethrow;
      }
    },
  );
  ref.onDispose(delivery.dispose);
  return delivery;
});

/// What the player calls when a play qualifies: write it to the outbox first
/// (online or not), then try to deliver straight away.
class PlayRecorder {
  PlayRecorder(this.outbox, this.delivery);
  final PlayOutbox outbox;
  final PlayOutboxDelivery delivery;

  /// The play passed the scrobble threshold.
  Future<void> scrobbleQualified({
    required String playId,
    required String songId,
    required int startedAtMs,
  }) async {
    await outbox.recordScrobble(
      playId: playId,
      songId: songId,
      startedAtMs: startedAtMs,
      scrobble: !isLocalSongId(songId),
    );
    unawaited(delivery.flush());
  }

  /// The play ended or was skipped.
  Future<void> feedbackReady({
    required String playId,
    required String songId,
    required int startedAtMs,
    required FeedbackRequest request,
  }) async {
    await outbox.recordFeedback(
      playId: playId,
      songId: songId,
      startedAtMs: startedAtMs,
      request: request,
    );
    unawaited(delivery.flush());
  }
}

final playRecorderProvider = Provider<PlayRecorder?>((ref) {
  final outbox = ref.watch(playOutboxProvider);
  final delivery = ref.watch(playOutboxDeliveryProvider);
  if (outbox == null || delivery == null) return null;
  return PlayRecorder(outbox, delivery);
});

/// Plays waiting for a server, for the Status screen.
final playOutboxPendingCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(playOutboxProvider)?.pendingCount ?? 0;
});

/// Pushes waiting plays out, and re-fetches missing download covers, when it
/// can matter: start-up, sign-in, the network coming back, the app resuming.
final offlineSyncBootstrapProvider = Provider<void>((ref) {
  void run() {
    unawaited(ref.read(playOutboxDeliveryProvider)?.flush());
    unawaited(_backfillCovers(ref));
  }

  final observer = _ResumeObserver(run);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  ref.listen<AsyncValue<List<ConnectivityResult>>>(connectivityStreamProvider, (prev, next) {
    final wasOffline = prev?.asData?.value.contains(ConnectivityResult.none) ?? false;
    final nowOffline = next.asData?.value.contains(ConnectivityResult.none) ?? true;
    if (wasOffline && !nowOffline) run();
  });
  ref.listen(settingsProvider.select((s) => s.serverUrl.isNotEmpty && s.password.isNotEmpty), (prev, now) {
    if (now && prev != true) run();
  });

  final startup = Timer(const Duration(seconds: 8), run);
  ref.onDispose(startup.cancel);
});

Future<void> _backfillCovers(Ref ref) async {
  try {
    if (!_canSend(ref)) return;
    await ref.read(offlineServiceProvider).backfillMissingCovers(ref.read(subsonicServiceProvider));
  } catch (e) {
    debugPrint('[Downloads] cover backfill: $e');
  }
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
