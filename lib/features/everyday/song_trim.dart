import 'dart:convert';

/// R9: your own start and end point for a song ("always start at 0:42").
/// Two numbers per song; no loops, no A-B repeat.

class SongTrim {
  const SongTrim({this.startMs = 0, this.endMs = 0});

  /// Playback begins here. 0 = from the beginning.
  final int startMs;

  /// Playback moves on from here. 0 = play to the end.
  final int endMs;

  static const none = SongTrim();

  /// The shortest stretch worth keeping between the two points.
  static const minSpanMs = 5000;

  bool get isNone => startMs <= 0 && endMs <= 0;
  bool get hasStart => startMs > 0;
  bool get hasEnd => endMs > 0;

  /// A trim that cannot be wrong for a song [durationMs] long: negatives
  /// become 0, points past the song are dropped, an end too close to (or
  /// before) the start is dropped, a start too close to the end is dropped.
  /// A [durationMs] of 0 (unknown) only fixes negatives and the order.
  SongTrim normalized(int durationMs) {
    var s = startMs < 0 ? 0 : startMs;
    var e = endMs < 0 ? 0 : endMs;
    if (durationMs > 0) {
      if (e >= durationMs - 1000) e = 0; // "end" at the very end is no end
      if (s >= durationMs - minSpanMs) s = 0;
    }
    if (e > 0 && e - s < minSpanMs) e = 0;
    return SongTrim(startMs: s, endMs: e);
  }

  Map<String, dynamic> toJson() => {if (startMs > 0) 's': startMs, if (endMs > 0) 'e': endMs};

  static SongTrim fromJson(Object? j) {
    if (j is! Map) return none;
    int n(Object? v) => v is num && v >= 0 ? v.toInt() : 0;
    return SongTrim(startMs: n(j['s']), endMs: n(j['e']));
  }

  @override
  bool operator ==(Object other) => other is SongTrim && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);
}

/// All trims, song id → trim. Immutable; [with_] returns a new map.
class SongTrims {
  const SongTrims([this.map = const {}]);
  final Map<String, SongTrim> map;

  SongTrim of(String songId) => map[songId] ?? SongTrim.none;

  /// Sets (or, for a "none" trim, removes) the trim for [songId].
  SongTrims with_(String songId, SongTrim trim) {
    final next = {...map};
    if (trim.isNone) {
      next.remove(songId);
    } else {
      next[songId] = trim;
    }
    return SongTrims(next);
  }

  String encode() => jsonEncode({for (final e in map.entries) e.key: e.value.toJson()});

  static SongTrims decode(String? raw) {
    if (raw == null || raw.isEmpty) return const SongTrims();
    try {
      final j = jsonDecode(raw) as Map;
      return SongTrims({
        for (final e in j.entries)
          if (SongTrim.fromJson(e.value) case final t when !t.isNone) e.key as String: t,
      });
    } catch (_) {
      return const SongTrims();
    }
  }
}

/// What playback should do about the trim of the song now playing.
sealed class TrimAction {
  const TrimAction();
}

class TrimNothing extends TrimAction {
  const TrimNothing();
}

/// Jump to [ms] (the start point).
class TrimSeek extends TrimAction {
  const TrimSeek(this.ms);
  final int ms;
}

/// The end point was reached: go on to the next song.
class TrimAdvance extends TrimAction {
  const TrimAdvance();
}

/// Watches playback positions of the current song and says when to act. One
/// instance per player; call [trackChanged] when the song changes and
/// [onPosition] for every position update.
///
/// - Start: acted on once per song start, only while the song is still near
///   its beginning. Scrubbing back before the start later is the listener's
///   choice and is left alone.
/// - End: acted on once per song start, wherever the position came from, so
///   seeking past the end moves on too. With repeat-one the song goes back to
///   its start point instead of moving on.
class TrimGuard {
  TrimGuard({required SongTrim Function(String songId) lookup}) : _lookup = lookup;

  final SongTrim Function(String songId) _lookup;

  String? _songId;
  int _durationMs = 0;
  SongTrim _trim = SongTrim.none;
  bool _startDone = false;
  bool _endDone = false;

  /// A start request is honoured only inside this window from the beginning
  /// of the song; after it, the listener has moved on by choice.
  static const startWindowMs = 4000;

  void trackChanged(String? songId, int durationSec) {
    _songId = songId;
    _durationMs = durationSec * 1000;
    _trim = songId == null ? SongTrim.none : _lookup(songId).normalized(_durationMs);
    _startDone = !_trim.hasStart;
    _endDone = !_trim.hasEnd;
  }

  /// Re-reads the trim of the current song (after it was edited while playing).
  void refresh() {
    final id = _songId;
    if (id == null) return;
    _trim = _lookup(id).normalized(_durationMs);
    _startDone = !_trim.hasStart || _startDone;
    _endDone = !_trim.hasEnd;
  }

  TrimAction onPosition(int positionMs, {required bool repeatOne}) {
    if (_trim.isNone) return const TrimNothing();
    if (!_startDone) {
      if (positionMs >= _trim.startMs) {
        _startDone = true; // already past the start: nothing to skip
      } else if (positionMs <= startWindowMs) {
        _startDone = true;
        return TrimSeek(_trim.startMs);
      } else {
        _startDone = true;
      }
    }
    if (!_endDone && positionMs >= _trim.endMs) {
      if (repeatOne) {
        // Back to the start point; the end counts again on the next pass.
        _startDone = true;
        return TrimSeek(_trim.startMs);
      }
      _endDone = true;
      return const TrimAdvance();
    }
    return const TrimNothing();
  }
}
