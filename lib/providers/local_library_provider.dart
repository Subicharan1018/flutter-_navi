import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../core/hive_boxes.dart';
import 'settings_provider.dart';

// =============================================================================
// localLibrarySongsProvider
//
// Watches the list of configured local folders from SettingsState and, when
// the user triggers a scan, returns the scanned Song list.
//
// Design:
//   - The scan is expensive (isolate, disk I/O). We do NOT run it automatically
//     on every state change — that would re-scan on every settings rebuild.
//   - Instead we expose a manually triggered AsyncNotifier that the UI drives.
//   - When isLocalMode is false, the provider returns an empty list immediately.
// =============================================================================

/// State object for the local library scanner.
class LocalLibraryState {
  final List<Song> songs;
  final bool isScanning;
  final String? error;

  const LocalLibraryState({
    this.songs = const [],
    this.isScanning = false,
    this.error,
  });

  LocalLibraryState copyWith({
    List<Song>? songs,
    bool? isScanning,
    String? error,
  }) => LocalLibraryState(
    songs: songs ?? this.songs,
    isScanning: isScanning ?? this.isScanning,
    error: error,
  );
}

class LocalLibraryNotifier extends StateNotifier<LocalLibraryState> {
  final Ref _ref;

  LocalLibraryNotifier(this._ref) : super(const LocalLibraryState()) {
    _init();
  }

  static const _kLocalLibraryKey = 'local_library_index';

  /// Loads the persisted index from Hive on startup.
  void _init() {
    try {
      final jsonStr = HiveBoxes.audio.get(_kLocalLibraryKey) as String?;
      if (jsonStr != null) {
        final List<dynamic> list = json.decode(jsonStr);
        final songs = list
            .map((m) => Song.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        state = state.copyWith(songs: songs);
      }
    } catch (_) {
      // Index corrupt or missing — silent fail, user can re-scan.
    }
  }

  /// Triggers a full recursive scan of all configured local folders.
  Future<void> scan() async {
    final folders = _ref.read(settingsProvider).localMusicFolders;
    if (folders.isEmpty) {
      state = state.copyWith(
        error: 'No local folders configured. Add folders in Settings.',
        isScanning: false,
      );
      return;
    }

    state = state.copyWith(isScanning: true, error: null);
    try {
      final service = _ref.read(localLibraryServiceProvider);
      final songs = await service.scanFolders(folders);

      // Persist to Hive for offline/restart access.
      final jsonStr = json.encode(songs.map((s) => s.toMap()).toList());
      await HiveBoxes.audio.put(_kLocalLibraryKey, jsonStr);

      state = state.copyWith(songs: songs, isScanning: false);
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  /// Clears the current scan results.
  void clear() => state = const LocalLibraryState();

  /// Updates a song's duration in the index.
  void updateSongDuration(String songId, int duration) {
    bool changed = false;
    final updatedSongs = state.songs.map((s) {
      if (s.id == songId && s.duration != duration) {
        changed = true;
        return s.copyWith(duration: duration);
      }
      return s;
    }).toList();

    if (!changed) return;

    state = state.copyWith(songs: updatedSongs);

    // Persist update
    final jsonStr = json.encode(updatedSongs.map((s) => s.toMap()).toList());
    HiveBoxes.audio.put(_kLocalLibraryKey, jsonStr);
  }
}

final localLibraryProvider =
    StateNotifierProvider<LocalLibraryNotifier, LocalLibraryState>((ref) {
      return LocalLibraryNotifier(ref);
    });
