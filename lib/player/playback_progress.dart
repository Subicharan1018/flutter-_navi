import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Position — a flash-free, throttled position source.
// just_audio briefly emits 0 while switching sources; a naive StreamBuilder
// shows a one-frame jump to 0:00. This keeps the last real position until the
// song actually changes.
// ─────────────────────────────────────────────────────────────────────────────

class PlaybackPosition extends StatefulWidget {
  final AudioPlayer player;
  final String songId;
  final Widget Function(BuildContext context, Duration position) builder;

  /// Minimum change before rebuilding (sub-second resolution isn't visible
  /// on a 300px bar; 250 ms keeps the playhead visibly fluid).
  final Duration resolution;

  const PlaybackPosition({
    super.key,
    required this.player,
    required this.songId,
    required this.builder,
    this.resolution = const Duration(milliseconds: 250),
  });

  @override
  State<PlaybackPosition> createState() => _PlaybackPositionState();
}

class _PlaybackPositionState extends State<PlaybackPosition> {
  StreamSubscription<Duration>? _sub;
  Duration _pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pos = widget.player.position;
    _sub = widget.player.positionStream.listen(_onPos);
  }

  void _onPos(Duration p) {
    if (!mounted) return;
    // A zero while playing is just_audio switching sources; a zero while
    // paused is a real rewind (end of queue, restart) and must show.
    if (p == Duration.zero &&
        _pos > const Duration(seconds: 1) &&
        widget.player.playing) {
      return;
    }
    if ((p - _pos).abs() >= widget.resolution || p < _pos) {
      setState(() => _pos = p);
    }
  }

  @override
  void didUpdateWidget(PlaybackPosition old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _sub?.cancel();
      _pos = widget.player.position;
      _sub = widget.player.positionStream.listen(_onPos);
    }
    if (old.songId != widget.songId) _pos = Duration.zero;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _pos);
}

/// Maps between the player's timeline and the song's real timeline.
///
/// The track length is [Song.duration] from Navidrome. The player's own
/// duration is trusted only when it agrees with the server within
/// [agreement]: a transcoded stream (`format=mp3&estimateContentLength=true`)
/// can report a wrong length, and a player whose timeline is stretched that
/// way also seeks to the wrong place.
///
/// When the two disagree, the player's timeline is taken as proportional to
/// the real one, so positions are rescaled in both directions ([toReal] for
/// display, [toPlayer] for seeking). This is the one place that assumption
/// lives.
@immutable
class ProgressTimeline {
  static const Duration agreement = Duration(seconds: 2);

  /// Real length of the song; zero when nothing is known.
  final Duration total;

  /// Player-timeline seconds per real second (1.0 when they agree).
  final double scale;

  const ProgressTimeline._(this.total, this.scale);

  const ProgressTimeline.unknown() : this._(Duration.zero, 1.0);

  factory ProgressTimeline.resolve({
    required int songSeconds,
    required Duration? playerDuration,
  }) {
    final song = Duration(seconds: songSeconds);
    final player = playerDuration ?? Duration.zero;
    if (song <= Duration.zero) return ProgressTimeline._(player, 1.0);
    if (player <= Duration.zero) return ProgressTimeline._(song, 1.0);
    if ((player - song).abs() <= agreement) {
      return ProgressTimeline._(player, 1.0);
    }
    return ProgressTimeline._(
      song,
      player.inMilliseconds / song.inMilliseconds,
    );
  }

  /// Player position → real position, clamped to the song.
  Duration toReal(Duration playerPosition) =>
      _clamp(Duration(microseconds: (playerPosition.inMicroseconds / scale).round()));

  /// Real position → the position to hand to `player.seek`.
  Duration toPlayer(Duration real) =>
      Duration(microseconds: (_clamp(real).inMicroseconds * scale).round());

  Duration _clamp(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (total > Duration.zero && d > total) return total;
    return d;
  }

  @override
  bool operator ==(Object other) =>
      other is ProgressTimeline && other.total == total && other.scale == scale;

  @override
  int get hashCode => Object.hash(total, scale);
}

/// What the Now Playing scrubber and the mini player both draw from.
@immutable
class PlaybackProgress {
  final ProgressTimeline timeline;
  final Duration position;

  const PlaybackProgress(this.timeline, this.position);

  Duration get total => timeline.total;
  Duration get remaining => total - position;

  /// 0–1, or 0 when the length is unknown.
  double get fraction => total > Duration.zero
      ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  /// Seeks [player] to [real] on the song's real timeline.
  void seekTo(AudioPlayer player, Duration real) =>
      player.seek(timeline.toPlayer(real));
}

/// Rebuilds [builder] with one [PlaybackProgress] shared by every surface.
/// Position comes from [player] (flash-free, see [PlaybackPosition]); the
/// timeline re-resolves when the song changes or the player reports a new
/// duration.
class PlaybackProgressBuilder extends StatefulWidget {
  final AudioPlayer player;
  final Song song;
  final Duration resolution;
  final Widget Function(BuildContext context, PlaybackProgress progress)
  builder;

  const PlaybackProgressBuilder({
    super.key,
    required this.player,
    required this.song,
    required this.builder,
    this.resolution = const Duration(milliseconds: 250),
  });

  @override
  State<PlaybackProgressBuilder> createState() =>
      _PlaybackProgressBuilderState();
}

class _PlaybackProgressBuilderState extends State<PlaybackProgressBuilder> {
  StreamSubscription<Duration?>? _sub;
  Duration? _playerDuration;

  @override
  void initState() {
    super.initState();
    _playerDuration = widget.player.duration;
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.player.durationStream.listen((d) {
      if (!mounted || d == _playerDuration) return;
      setState(() => _playerDuration = d);
    });
  }

  @override
  void didUpdateWidget(PlaybackProgressBuilder old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _playerDuration = widget.player.duration;
      _listen();
    } else if (old.song.id != widget.song.id) {
      // The old track's length must never size the new track's bar; the
      // duration stream re-fills this when the new source reports.
      _playerDuration = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ProgressTimeline.resolve(
      songSeconds: widget.song.duration,
      playerDuration: _playerDuration,
    );
    return PlaybackPosition(
      player: widget.player,
      songId: widget.song.id,
      resolution: widget.resolution,
      builder: (context, raw) =>
          widget.builder(context, PlaybackProgress(timeline, timeline.toReal(raw))),
    );
  }
}
