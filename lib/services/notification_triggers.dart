import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import '../features/social/logic/social_providers.dart';
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

void wireNotificationTriggers(ProviderContainer container) {
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
