import 'dart:math' as math;

import '../../../../models/song.dart';
import '../../data/models/recommended_song.dart';
import '../../logic/pick_why.dart';

/// One pick as the taste field sees it: where it sits (closeness, mood) and
/// how it sounds (energy, danceability). Plain numbers, so the maths is testable
/// without a widget.
class TastePoint {
  final String id;
  final String title;
  final String artist;

  /// Server's overall fit for this moment, 0..1 (higher = closer).
  final double score;
  final double energy;
  final double valence;
  final double dance;

  /// Why the server picked it, in words (see [pickWhy]).
  final PickWhy why;

  const TastePoint({
    required this.id,
    required this.title,
    required this.artist,
    required this.score,
    required this.energy,
    required this.valence,
    required this.dance,
    this.why = PickWhy.generic,
  });

  factory TastePoint.of(Song song, RecommendedSong rec) => TastePoint(
        id: song.id,
        title: song.title,
        artist: song.artist,
        score: rec.scores.finalScore,
        energy: rec.audio.energy.clamp(0.0, 1.0),
        valence: rec.audio.valence.clamp(0.0, 1.0),
        dance: rec.audio.danceability.clamp(0.0, 1.0),
        why: pickWhy(rec),
      );
}

/// Inner ring (the moment itself) and outer edge, as fractions of the radius.
const double tasteInner = 0.16;
const double tasteOuter = 0.96;

/// True when the picks differ enough in energy for a dial to mean something
/// (a server that sends no audio features gives every song 0).
bool hasEnergySpread(Iterable<TastePoint> points) {
  if (points.length < 3) return false;
  var lo = 1.0, hi = 0.0;
  for (final p in points) {
    lo = math.min(lo, p.energy);
    hi = math.max(hi, p.energy);
  }
  return hi - lo >= 0.08;
}

/// Mean energy of the picks, where the dial rests before it is touched.
double meanEnergy(Iterable<TastePoint> points) {
  if (points.isEmpty) return 0.5;
  return points.fold<double>(0, (a, p) => a + p.energy) / points.length;
}

/// Radius (0..1 of the field) for each point. With no dial: distance is how
/// poorly the song fits this moment, spread across the field. With the dial:
/// distance is how far the song's energy is from the dial.
Map<String, double> tasteRadii(List<TastePoint> points, {double? dial}) {
  final out = <String, double>{};
  if (points.isEmpty) return out;
  if (dial != null) {
    for (final p in points) {
      final d = ((p.energy - dial).abs() / 0.6).clamp(0.0, 1.0);
      out[p.id] = tasteInner + (tasteOuter - tasteInner) * d;
    }
    return out;
  }
  var lo = double.infinity, hi = -double.infinity;
  for (final p in points) {
    lo = math.min(lo, p.score);
    hi = math.max(hi, p.score);
  }
  final span = hi - lo;
  for (var i = 0; i < points.length; i++) {
    final p = points[i];
    // Equal scores (or none): fall back to list order, best first.
    final closeness = span < 0.01 ? 1 - i / math.max(1, points.length - 1) * 0.6 : (p.score - lo) / span;
    out[p.id] = tasteInner + (tasteOuter - tasteInner) * (1 - closeness).clamp(0.0, 1.0) * 0.92;
  }
  return out;
}

/// Where a point sits around the centre, in radians. Brighter songs (valence)
/// sweep clockwise from the left; a golden-ratio nudge keeps neighbours from
/// stacking. Deterministic: the same mix always draws the same field.
double tasteAngle(TastePoint p, int index) {
  final spread = (index * 0.6180339887) % 1.0;
  return (p.valence * 0.7 + spread * 0.3) * 2 * math.pi - math.pi;
}

/// The mix re-ordered toward [dial] (0 calm … 1 lively): the songs whose energy
/// is nearest first. Stable: equal distances keep the server's order, and songs
/// with no known energy are treated as middling. Null dial = untouched.
List<Song> reshapeByEnergy(List<Song> songs, Map<String, double> energyById, double? dial) {
  if (dial == null || songs.length < 2) return songs;
  final keyed = <(double, Song)>[
    for (var i = 0; i < songs.length; i++)
      ((( energyById[songs[i].id] ?? 0.5) - dial).abs() + i * 0.002, songs[i]),
  ];
  keyed.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final k in keyed) k.$2];
}

/// The word for a dial position.
String energyWord(double v) {
  if (v < 0.2) return 'Calm';
  if (v < 0.4) return 'Easy';
  if (v < 0.6) return 'Steady';
  if (v < 0.8) return 'Upbeat';
  return 'Lively';
}
