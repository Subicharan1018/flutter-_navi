import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/hive_boxes.dart';
import '../../features/ai_shuffle/data/services/shuffle_api_service.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../models/lyric_translation.dart';
import '../services/lyrics_server_api.dart';
import 'lyrics_controller.dart';

const _kShowTranslation = 'lyrics_show_translation';
const _kShowPronunciation = 'lyrics_show_pronunciation';

final lyricsServerApiProvider = Provider<LyricsServerApi>((ref) {
  return LyricsServerApi(
    createShuffleDio(() {
      final s = ref.read(settingsProvider);
      return (s.username, s.password);
    }, logTag: 'LyricsServer'),
  );
});

class LyricsTranslationState {
  /// Show the English translation under each line.
  final bool showTranslation;

  /// Show the Latin-script pronunciation under each line.
  final bool showPronunciation;
  final bool loading;
  final String? error;

  /// The current song's translation, once the server has answered.
  final LyricsTranslation? data;

  const LyricsTranslationState({
    this.showTranslation = false,
    this.showPronunciation = false,
    this.loading = false,
    this.error,
    this.data,
  });

  bool get wanted => showTranslation || showPronunciation;

  LyricsTranslationState copyWith({
    bool? showTranslation,
    bool? showPronunciation,
    bool? loading,
    String? error,
    bool clearError = false,
    LyricsTranslation? data,
    bool clearData = false,
  }) => LyricsTranslationState(
    showTranslation: showTranslation ?? this.showTranslation,
    showPronunciation: showPronunciation ?? this.showPronunciation,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    data: clearData ? null : (data ?? this.data),
  );
}

/// Translation and pronunciation for the lyrics that are showing. Nothing is
/// requested until a toggle is on; the server keeps each song's result, and
/// this keeps it for the session, so flipping toggles or revisiting a song
/// costs nothing. The result stays index-aligned with the lyric lines, so
/// synced lines keep their timing.
class LyricsTranslationController extends Notifier<LyricsTranslationState> {
  final _memo = <String, LyricsTranslation>{};
  int _generation = 0;

  @override
  LyricsTranslationState build() {
    ref.onDispose(() => _generation++);
    // The lyrics load (or change with the song) after this builds.
    ref.listen(
      lyricsControllerProvider.select((s) => s.lyrics),
      (_, _) => _sync(),
    );
    Future.microtask(_sync);
    return LyricsTranslationState(
      showTranslation: _readPref(_kShowTranslation),
      showPronunciation: _readPref(_kShowPronunciation),
    );
  }

  static bool _readPref(String key) {
    try {
      return HiveBoxes.prefs.get(key, defaultValue: false) == true;
    } catch (_) {
      return false; // storage not open (tests)
    }
  }

  static void _writePref(String key, bool value) {
    try {
      HiveBoxes.prefs.put(key, value);
    } catch (_) {}
  }

  void setTranslation(bool on) {
    _writePref(_kShowTranslation, on);
    state = state.copyWith(showTranslation: on);
    _sync();
  }

  void setPronunciation(bool on) {
    _writePref(_kShowPronunciation, on);
    state = state.copyWith(showPronunciation: on);
    _sync();
  }

  void retry() => _sync();

  String? get _songId => ref.read(playerProvider).currentSong?.id;

  Future<void> _sync() async {
    if (!ref.mounted) return;
    final song = ref.read(playerProvider).currentSong;
    final lyrics = ref.read(lyricsControllerProvider).lyrics;
    if (song == null || lyrics == null || lyrics.isEmpty) {
      _generation++;
      state = state.copyWith(loading: false, clearError: true, clearData: true);
      return;
    }
    final lines = [for (final l in lyrics.lines) l.text.trim()];
    final key = '${song.id}|${lines.length}';
    final memo = _memo[key];
    if (memo != null) {
      _generation++;
      state = state.copyWith(loading: false, clearError: true, data: memo);
      return;
    }
    if (!state.wanted) {
      _generation++;
      state = state.copyWith(loading: false, clearError: true, clearData: true);
      return;
    }
    final gen = ++_generation;
    state = state.copyWith(loading: true, clearError: true, clearData: true);
    try {
      final result = await ref
          .read(lyricsServerApiProvider)
          .translate(
            songId: song.id,
            title: song.title,
            artist: song.artist,
            lines: lines,
          );
      if (!ref.mounted || gen != _generation || _songId != song.id) return;
      _memo[key] = result;
      state = state.copyWith(loading: false, data: result);
    } on LyricsServerException catch (e) {
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      debugPrint('[LyricsTranslation] $e');
      if (!ref.mounted || gen != _generation) return;
      state = state.copyWith(
        loading: false,
        error: 'Couldn’t translate these lyrics.',
      );
    }
  }
}

/// autoDispose with the lyrics sheet, like [lyricsControllerProvider].
final lyricsTranslationProvider =
    NotifierProvider.autoDispose<
      LyricsTranslationController,
      LyricsTranslationState
    >(LyricsTranslationController.new);
