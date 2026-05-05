import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

// =============================================================================
// ReplayUploadService
//
// Exports replay + recommendation data as JSON and uploads it via WebDAV
// according to the user's schedule (weekly/monthly). Deletes local data
// (play_events) only after a successful upload.
// =============================================================================

class ReplayUploadService {
  final Ref _ref;

  ReplayUploadService(this._ref);

  Future<void> performUploadIfNeeded() async {
    final settings = _ref.read(settingsProvider);
    final schedule = settings.analyticsUploadSchedule;
    if (schedule == 'none') return;

    final lastUploadStr = settings.analyticsLastUpload;
    DateTime? lastUpload;
    if (lastUploadStr != null) {
      lastUpload = DateTime.tryParse(lastUploadStr);
    }

    final now = DateTime.now();
    bool shouldUpload = false;

    if (lastUpload == null) {
      shouldUpload = true;
    } else {
      if (schedule == 'weekly') {
        shouldUpload = now.difference(lastUpload).inDays >= 7;
      } else if (schedule == 'monthly') {
        shouldUpload = now.difference(lastUpload).inDays >= 30;
      }
    }

    if (shouldUpload) {
      await uploadData(schedule);
    }
  }

  Future<void> uploadData([String schedule = 'manual']) async {
    debugPrint('[ReplayUpload] Starting $schedule upload...');
    final collector = _ref.read(listenerCollectorProvider);
    final subsonic = _ref.read(subsonicServiceProvider);

    try {
      // 1. Export data as JSON
      final jsonData = await collector.exportJson();
      final jsonString = jsonEncode(jsonData);

      // 2. Upload via WebDAV
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final remoteFileName = 'navivibe_analytics_$timestamp.json';

      await subsonic.uploadTextToWebDav(
        remoteFileName: remoteFileName,
        contents: jsonString,
        contentType: 'application/json; charset=utf-8',
      );

      // 3. Mark last upload time
      final now = DateTime.now();
      await _ref
          .read(settingsProvider.notifier)
          .setAnalyticsLastUpload(now.toIso8601String());

      // 4. Cleanup local data (delete events older than the current upload threshold)
      // Keep recent data so the app doesn't go totally blank right after upload.
      // If we uploaded "weekly", maybe wipe anything older than 7 days, or 30 days.
      // We will clean up play_events older than 30 days to keep the local DB light
      // while preserving enough data for short-term replay features.
      final cleanupThreshold = now.subtract(const Duration(days: 30));
      await collector.deleteDataOlderThan(cleanupThreshold);

      debugPrint('[ReplayUpload] ✅ Upload complete and local data cleaned up.');
    } catch (e) {
      debugPrint('[ReplayUpload] ❌ Upload failed: $e');
    }
  }
}

final replayUploadServiceProvider = Provider<ReplayUploadService>((ref) {
  return ReplayUploadService(ref);
});
