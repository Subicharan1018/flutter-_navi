import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hive_boxes.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/app_notifier.dart';
import '../../../services/download_notices.dart';
import '../../../utils/app_resume_observer.dart';
import '../../../utils/platform_utils.dart';
import '../../exportify_import/logic/exportify_providers.dart';
import '../../exportify_import/logic/import_finished.dart';

const _kAnnouncedImports = 'announced_imports_v1';

/// What the app does on its own for downloads and imports, with nobody tapping:
///  - carries on with downloads a previous run left unfinished (app killed,
///    phone restarted), a few seconds after launch and once signed in;
///  - looks for imports the server finished fetching since the app last
///    looked, and says so in one notification (no push service: this runs at
///    launch, when the app resumes, and every ten minutes while it is alive).
final backgroundDownloadsBootstrapProvider = Provider<void>((ref) {
  if (!PlatformUtils.supportsOfflineFiles) return;
  var resumed = false;

  Future<void> resumeDownloads() async {
    final s = ref.read(settingsProvider);
    if (s.serverUrl.isEmpty || s.password.isEmpty) return;
    try {
      await ref.read(offlineServiceProvider).initialize();
      await ref.read(downloadStateProvider.notifier).resumePending();
      resumed = true;
    } catch (e) {
      debugPrint('[Downloads] resume failed: $e');
    }
  }

  Future<void> announceImports() async {
    final s = ref.read(settingsProvider);
    if (s.serverUrl.isEmpty || s.password.isEmpty) return;
    try {
      final all = await ref.read(exportifyApiProvider).imports();
      final raw = HiveBoxes.prefs.get(_kAnnouncedImports);
      final seen = raw is List ? [for (final e in raw) '$e'] : null;
      final check = checkFinishedImports(all, seen);
      await HiveBoxes.prefs.put(_kAnnouncedImports, check.seen);
      if (!check.announce) return;
      final text = importFinishedText(check);
      await AppNotifier.show(NotifyChannel.downloads, id: importDoneNoticeId, title: text.title, body: text.body);
    } catch (e) {
      // Offline, or a server without the record: try again at the next look.
      debugPrint('[Imports] finished check: $e');
    }
  }

  void look() {
    if (!resumed) unawaited(resumeDownloads());
    unawaited(announceImports());
  }

  final observer = AppResumeObserver(look);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  ref.listen(settingsProvider.select((s) => s.serverUrl.isNotEmpty && s.password.isNotEmpty), (prev, now) {
    if (now && prev != true) look();
  });
  final first = Timer(const Duration(seconds: 6), look);
  final every = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(announceImports()));
  ref.onDispose(() {
    first.cancel();
    every.cancel();
  });
});
