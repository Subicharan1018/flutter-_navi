import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../core/hive_boxes.dart';
import '../features/social/logic/people_providers.dart';
import '../features/social/logic/social_providers.dart';
import '../features/social/logic/social_rules.dart';
import '../widgets/app_scaffold.dart' show AppTab, selectAppTab;
import '../features/updates/logic/update_providers.dart';
import 'app_notifier.dart';

/// Decides what is worth a notification; [wireNotificationTriggers] connects
/// those decisions to the providers that know about updates and invitations.
/// (Download completion is posted by the download provider itself.)

/// An update is announced once per build, and not again if the person already
/// dismissed it on Home.
@visibleForTesting
bool shouldAnnounceUpdate({required int build, required int notifiedBuild, required int dismissedBuild}) =>
    build > notifiedBuild && build > dismissedBuild;

/// Only a *rise* in waiting invitations is news; answering one is not.
@visibleForTesting
bool invitationsIncreased(int? previous, int next) => next > (previous ?? 0);

@visibleForTesting
String invitationText(int count) =>
    count == 1 ? 'You have a new invitation waiting.' : 'You have $count invitations waiting.';

/// Invitations come from the server, which has no push channel, so while the
/// app is alive they are re-read at this interval (only with social turned on).
const invitationPollEvery = Duration(minutes: 10);

// ── friends starting to listen ───────────────────────────────────────────────

/// Title and body of the "friend started listening" notification.
@visibleForTesting
(String, String) friendAlertText(FriendAlert a) {
  final s = a.song;
  final song = s == null ? null : (s.artist.isEmpty ? s.title : '${s.title} · ${s.artist}');
  final room = a.roomMode == null
      ? null
      : (a.joinCode != null ? 'In a ${a.roomMode!.label} room. Open People to join.' : 'In a ${a.roomMode!.label} room.');
  return ('${a.username} is listening', [?song, ?room].join(' · '));
}

/// Raises the notification (only when the app is not on screen; the People
/// view already shows it otherwise) and remembers that one is waiting, so
/// opening the app straight after lands on People.
class AppFriendAlertSink implements FriendAlertSink {
  const AppFriendAlertSink();

  @override
  Future<void> show(FriendAlert alert) async {
    final (title, body) = friendAlertText(alert);
    final shown = await AppNotifier.show(
      NotifyChannel.social,
      // One slot per friend: a newer alert replaces their older one.
      id: 100 + (alert.username.toLowerCase().hashCode & 0xfff),
      title: title,
      body: body,
    );
    if (shown) FriendAlertOpen.mark();
  }
}

/// A notification tap just brings the app forward (the native side has no
/// payload), so "opens that friend's activity" is done on the next resume: if
/// a friend alert was posted in the last couple of minutes, show People.
class FriendAlertOpen {
  FriendAlertOpen._();
  static const window = Duration(minutes: 2);
  static DateTime? _at;

  static void mark([DateTime? now]) => _at = now ?? DateTime.now();

  /// True once per posted alert, and only inside [window].
  static bool consume([DateTime? now]) {
    final at = _at;
    _at = null;
    return at != null && (now ?? DateTime.now()).difference(at) <= window;
  }
}

void wireNotificationTriggers(ProviderContainer container) {
  // Friend alerts: start the People poll (it only runs while social features
  // and alerts are on) and open People when the app comes forward after one.
  container.read(peopleProvider);
  AppLifecycleListener(onResume: () {
    if (FriendAlertOpen.consume()) selectAppTab(AppTab.jam);
  });

  container.listen(updateCheckProvider, (_, next) {
    final check = next.asData?.value;
    if (check == null || !check.available) return;
    final build = check.manifest.build;
    final notified = HiveBoxes.prefs.get(HiveBoxes.kUpdateNotifiedBuild);
    if (!shouldAnnounceUpdate(
      build: build,
      notifiedBuild: notified is int ? notified : 0,
      dismissedBuild: container.read(dismissedUpdateProvider),
    )) {
      return;
    }
    unawaited(() async {
      final shown = await AppNotifier.show(
        NotifyChannel.updates,
        id: 2,
        title: 'Update available',
        body: 'NaviVibe ${check.manifest.version} is ready to install.',
      );
      // Remember only a notification that was really posted, so one skipped
      // because the app was open is still sent the next time it is in the background.
      if (shown) await HiveBoxes.prefs.put(HiveBoxes.kUpdateNotifiedBuild, build);
    }());
  });

  container.listen(invitationCountProvider, (prev, next) {
    if (!invitationsIncreased(prev, next)) return;
    unawaited(AppNotifier.show(
      NotifyChannel.social,
      id: 3,
      title: 'Invitation',
      body: invitationText(next),
    ));
  });

  Timer.periodic(invitationPollEvery, (_) {
    if (!container.read(socialEnabledProvider)) return;
    container.invalidate(collabListProvider);
    container.invalidate(blendListProvider);
  });
}
