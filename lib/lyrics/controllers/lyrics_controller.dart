import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../models/lyric_line.dart';
import '../models/lyrics_result.dart';
import '../services/lyrics_repository.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum LyricsStatus { loading, synced, plain, empty, error }

class LyricsState {
  final LyricsStatus status;
  final SyncedLyrics? lyrics;

  /// Index of the currently active line. -1 means before the first line or
  /// no synced lyrics are loaded.
  final int activeLineIndex;

  final String? errorMessage;

  const LyricsState({
    required this.status,
    this.lyrics,
    this.activeLineIndex = -1,
    this.errorMessage,
  });

  LyricsState copyWith({
    LyricsStatus? status,
    SyncedLyrics? lyrics,
    int? activeLineIndex,
    String? errorMessage,
  }) {
    return LyricsState(
      status: status ?? this.status,
      lyrics: lyrics ?? this.lyrics,
      activeLineIndex: activeLineIndex ?? this.activeLineIndex,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

class LyricsController extends Notifier<LyricsState> {
  StreamSubscription<Duration>? _posSub;

  @override
  LyricsState build() {
    ref.onDispose(() {
      _posSub?.cancel();
    });

    // React to song changes.
    ref.listen<Song?>(playerProvider.select((s) => s.currentSong), (
      prev,
      next,
    ) {
      if (next != null && next.id != (prev?.id ?? '')) {
        _loadLyrics(next);
      }
    });

    // PERF: Position subscription is deferred — only started once synced
    // lyrics are loaded (see _loadLyrics). This avoids wasting frame ticks
    // on position events when there are no lyrics to track.

    // Load lyrics for whatever is currently playing.
    final song = ref.read(playerProvider).currentSong;
    if (song != null) {
      // Schedule async work after build returns
      Future.microtask(() => _loadLyrics(song));
      return const LyricsState(status: LyricsStatus.loading);
    } else {
      return const LyricsState(status: LyricsStatus.empty);
    }
  }

  // ── Position tracking ─────────────────────────────────────────────────────

  void _subscribeToPosition() {
    try {
      final player = ref.read(playerProvider.notifier).player;
      _posSub = player.positionStream.listen((position) {
        _onPosition(position);
      });
    } catch (e) {
      debugPrint(
        '[LyricsController] Could not subscribe to positionStream: $e',
      );
    }
  }

  void _onPosition(Duration position) {
    final lyrics = state.lyrics;
    if (lyrics == null || state.status != LyricsStatus.synced) return;

    final idx = lyrics.getCurrentLineIndex(position);
    if (idx != state.activeLineIndex) {
      state = state.copyWith(activeLineIndex: idx);
    }
  }

  // ── Lyrics loading ────────────────────────────────────────────────────────

  Future<void> _loadLyrics(Song song) async {
    _posSub?.cancel();
    state = const LyricsState(status: LyricsStatus.loading);

    try {
      final result = await ref.read(lyricsRepositoryProvider).getLyrics(song);

      switch (result.type) {
        case LyricsType.synced:
          state = LyricsState(
            status: LyricsStatus.synced,
            lyrics: result.lyrics,
            activeLineIndex: -1,
          );
          // PERF: Only subscribe to position stream when we have synced
          // lyrics to track. Cancel any previous subscription first.
          _posSub?.cancel();
          _subscribeToPosition();
        case LyricsType.plain:
          state = LyricsState(
            status: LyricsStatus.plain,
            lyrics: result.lyrics,
            activeLineIndex: -1,
          );
        case LyricsType.none:
          state = const LyricsState(status: LyricsStatus.empty);
      }
    } catch (e) {
      debugPrint('[LyricsController] Error loading lyrics: $e');
      state = LyricsState(
        status: LyricsStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Manually trigger a reload — used by the Retry button in the error state.
  Future<void> retry() async {
    final song = ref.read(playerProvider).currentSong;
    if (song != null) await _loadLyrics(song);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// autoDispose: cleaned up automatically when the lyrics sheet is dismissed.
final lyricsControllerProvider =
    NotifierProvider.autoDispose<LyricsController, LyricsState>(
      LyricsController.new,
    );
