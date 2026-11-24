import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'film_assets.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String sayHour(int h) => h == 0
    ? 'midnight'
    : h == 12
    ? 'noon'
    : h < 12
    ? '$h am'
    : '${h - 12} pm';

String sayDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? '' : '${d.day} ${_months[d.month - 1]}';
}

/// The film, in order. A scene with nothing behind it is left out. Until the year is [settled] the film runs only as
/// far as what is known, so nothing is ever added behind you: more of it appears ahead.
List<FilmScene> filmScenes(WrappedData d, {bool settled = true}) {
  final all = _allScenes(d);
  if (settled) return all;
  if (d.isEmpty) return all.take(1).toList();
  const known = {'intro', 'minutes', 'guess', 'number-one', 'top5', 'artists', 'genres', 'clock'};
  return all.takeWhile((s) => known.contains(s.id)).toList();
}

List<FilmScene> _allScenes(WrappedData d) => [
  IgniteScene(),
  SandScene(),
  if (d.songs.length >= 3) GuessScene(),
  if (d.songs.isNotEmpty) RecordScene(),
  if (d.songs.length >= 2) CountdownScene(),
  if (d.artists.isNotEmpty) SolarScene(),
  if (d.genres.isNotEmpty) GalaxyScene(d),
  if (d.hourly.any((v) => v > 0)) SunburstScene(d),
  if (d.days.isNotEmpty) CometScene(d),
  if (d.uniqueSongs > 0) WarpScene(),
  SpiritScene(d),
  if (d.busiestMonth != null) TerrainScene(),
  if (d.bestDay != null) TideScene(d),
  PosterScene(),
];

double _wave(double v) => math.sin(v * kTau);

/// Slow weightless dust, where the swarm rests when a scene does not need a particle.
void _drift(FilmFrame f, int i, Dot o, {double a = 0.3}) {
  final x = rnd(i, 1) * f.w + _wave(f.t * 0.05 + rnd(i, 3)) * 14 * f.u;
  final y = (rnd(i, 2) * f.h - f.t * (4 + rnd(i, 4) * 10) * f.u) % f.h;
  o.set(x, y, (0.5 + rnd(i, 5) * 1.1) * f.u, a * (0.4 + 0.6 * rnd(i, 6)) * (0.6 + 0.4 * _wave(f.t * 0.4 + rnd(i, 7))));
}

/// Particle [i] as pixel of [cover] laid over [box]; false when the particle is not needed.
bool _pixel(FilmCover? cover, Rect box, int i, int n, Dot o) {
  if (cover == null) {
    // no picture: a disc of light stands in
    final r = math.sqrt(rnd(i, 61)) * box.width / 2;
    final a = rnd(i, 62) * kTau;
    o.set(box.center.dx + math.cos(a) * r, box.center.dy + math.sin(a) * r, box.width * 0.008, 0.35 + 0.65 * (r / box.width));
    return true;
  }
  final side = cover.side;
  if (i >= side * side) return false;
  final cell = box.width / side;
  o.set(box.left + (i % side + 0.5) * cell, box.top + (i ~/ side + 0.5) * cell, cell * 0.62, 1, cover.pixels[i] & 0xFFFFFF);
  return true;
}

// ── 1. Ignite ───────────────────────────────────────────────────────────────

/// Black. One point of light swells, bursts, and the sparks find the year.
class IgniteScene extends FilmScene {
  @override
  String get id => 'intro';
  @override
  double get length => 7;
  @override
  String why(WrappedData d) => 'Every point of light in this film is made from your own listening in ${d.year}. Drag to stir them.';
  @override
  String share(WrappedData d) => 'My ${d.year} in music.';
  @override
  String speech(WrappedData d) => 'Your ${d.year} in music. Wrapped.';
  @override
  String? get hint => 'Drag to stir it';

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final t = f.t;
    final c = Offset(f.w / 2, f.h * 0.44);
    final u = f.u;
    if (t < 0.9) {
      final k = t / 0.9;
      final a = rnd(i, 1) * kTau + t * 9;
      final r = (1 - k) * (30 + 120 * rnd(i, 2)) * u * (1 - k) + 3 * u;
      o.set(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r, (0.6 + k * 1.6) * u, k * 0.9);
      return;
    }
    // the burst
    final b = t - 0.9;
    final dir = rnd(i, 3) * kTau;
    final speed = (60 + 330 * rnd(i, 4)) * u;
    final far = speed * (1 - math.exp(-b * 2.6));
    final bx = c.dx + math.cos(dir + b * 0.35) * far;
    final by = c.dy + math.sin(dir + b * 0.35) * far * 1.25;
    final k = ramp(t, 1.7 + rnd(i, 5) * 0.8, 2.9 + rnd(i, 5) * 0.8, Curves.easeInOutQuart);
    final pts = f.assets.year;
    if (pts.length < n * 2) {
      o.set(bx, by, 1.3 * u, 0.8);
      return;
    }
    final w = f.w * 0.84, h = w * 0.46;
    final breathe = 1 + 0.012 * math.sin(t * 2.2);
    final sway = math.sin(t * 1.4 + pts[i * 2] * 5) * 3 * u;
    final gx = c.dx + (pts[i * 2] - 0.5) * w * breathe;
    final gy = c.dy + (pts[i * 2 + 1] - 0.5) * h * breathe + sway;
    final swirl = math.sin(math.pi * k) * 40 * u;
    final twinkle = 0.72 + 0.28 * math.sin(t * 3 + i * 1.7);
    o.set(mix(bx, gx, k) + math.cos(i + t * 3) * swirl, mix(by, gy, k) + math.sin(i + t * 3) * swirl, (1.45 + rnd(i, 6) * 1.1) * u, mix(0.8, twinkle, k));
  }

  @override
  void under(FilmFrame f) {
    // the flash, and the ring it leaves
    final b = f.t - 0.9;
    if (b <= 0 || b > 1.2) return;
    final c = Offset(f.w / 2, f.h * 0.44);
    final k = b / 1.2;
    f.canvas.drawCircle(
      c,
      Curves.easeOutCubic.transform(k) * f.h * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1 - k) * 22 * f.u
        ..color = Color.fromRGBO(255, 255, 255, (1 - k) * 0.5),
    );
    if (b < 0.16) f.canvas.drawRect(Offset.zero & f.size, Paint()..color = Color.fromRGBO(255, 255, 255, (1 - b / 0.16) * 0.8));
  }

  @override
  void over(FilmFrame f) {
    final y = f.h * 0.44 + f.w * 0.27;
    final who = f.name == null || f.name!.isEmpty ? 'Your year in music' : '${f.name}’s year in music';
    final h = f.film.kinetic(f, who, x: f.w / 2, y: y, size: 25 * f.u, at: 3.4, center: true, lines: 2);
    f.film.kinetic(f, 'Wrapped', x: f.w / 2, y: y + h + 6 * f.u, size: 17 * f.u, at: 3.9, center: true, weight: FontWeight.w600, color: kDim);
  }
}

// ── 2. Sand ─────────────────────────────────────────────────────────────────

/// The year drains through an hourglass while the minutes race.
class SandScene extends FilmScene {
  @override
  String get id => 'minutes';
  @override
  double get length => 8;
  @override
  double get still => 5.9;
  @override
  String why(WrappedData d) => 'The listening time your server recorded for ${d.year}, over ${d.totalPlays} plays.';
  @override
  String share(WrappedData d) => 'I listened for ${listeningTime(d.totalMinutes)} in ${d.year}.';
  @override
  String speech(WrappedData d) => 'You listened for ${d.totalMinutes} minutes.';
  @override
  String? get hint => 'Tap to shake the glass';

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final u = f.u;
    final hh = 122 * u, hw = 78 * u;
    final c = Offset(f.w / 2, f.h * 0.35);
    final done = ramp(f.t, 1.6, 6.6, Curves.easeInOut);
    final turn = math.pi * ramp(f.t, 0.3, 1.5, Curves.easeInOutBack);
    final rank = i / n;
    double x, y;
    if (rank > done + 0.045) {
      final left = math.max(0.02, 1 - done);
      final q = clamp01((rank - done - 0.045) / math.max(0.01, left - 0.045));
      final level = hh * math.sqrt(left);
      y = -level * math.sqrt(q) - 2 * u;
      x = (rnd(i, 1) * 2 - 1) * hw * (-y / hh);
    } else if (rank > done) {
      // the falling thread
      final k = 1 - (rank - done) / 0.045;
      y = k * k * hh * (1 - 0.6 * done);
      x = _wave(rnd(i, 2) + f.t) * 1.6 * u;
    } else {
      final pile = hh * (1 - math.sqrt(math.max(0, 1 - done)));
      final q = math.sqrt(rnd(i, 3));
      y = hh - pile * (1 - q);
      x = (rnd(i, 1) * 2 - 1) * hw * (y / hh);
    }
    // it starts upside down and swings over
    final ang = turn - math.pi + math.sin(f.t * 1.1) * 0.03;
    final px = x * math.cos(ang) - y * math.sin(ang);
    final py = x * math.sin(ang) + y * math.cos(ang);
    o.set(c.dx + px, c.dy + py, (1.1 + rnd(i, 4) * 0.9) * u, 0.55 + 0.45 * rnd(i, 5));
  }

  @override
  void under(FilmFrame f) {
    final u = f.u;
    final k = ramp(f.t, 0.6, 1.4);
    if (k <= 0) return;
    final hh = 130 * u, hw = 86 * u;
    final c = f.canvas;
    c.save();
    c.translate(f.w / 2, f.h * 0.35);
    c.rotate(math.pi * ramp(f.t, 0.3, 1.5, Curves.easeInOutBack) - math.pi + math.sin(f.t * 1.1) * 0.03);
    final p = Path()
      ..moveTo(-hw, -hh)
      ..quadraticBezierTo(-hw * 0.9, -hh * 0.5, -4 * u, 0)
      ..quadraticBezierTo(-hw * 0.9, hh * 0.5, -hw, hh)
      ..lineTo(hw, hh)
      ..quadraticBezierTo(hw * 0.9, hh * 0.5, 4 * u, 0)
      ..quadraticBezierTo(hw * 0.9, -hh * 0.5, hw, -hh)
      ..close();
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * u
        ..color = Color.fromRGBO(255, 255, 255, 0.28 * k),
    );
    c.restore();
  }

  @override
  void over(FilmFrame f) {
    final u = f.u, x = 24 * u;
    final y = f.h * 0.62;
    f.film.kinetic(f, 'You listened for', x: x, y: y, size: 20 * u, at: 1.2, weight: FontWeight.w600, color: kDim);
    f.film.counter(f, f.d.totalMinutes, _grouped, x: x, y: y + 28 * u, size: 86 * u, from: 1.4, to: 5.4);
    f.film.kinetic(f, 'minutes', x: x, y: y + 124 * u, size: 30 * u, at: 2.2);
    final days = f.d.totalMinutes / 1440;
    if (days >= 1) {
      f.film.kinetic(f, '${days.toStringAsFixed(days >= 10 ? 0 : 1)} whole days, back to back', x: x, y: y + 164 * u, size: 17 * u, at: 5.2, weight: FontWeight.w500, color: kDim);
    }
  }
}

String _grouped(int v) {
  final s = '$v';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ── 3. Guess ────────────────────────────────────────────────────────────────

/// The three songs offered, in a stable order that is not simply the ranking.
List<int> guessOrder(WrappedData d) => [for (var i = 0; i < 3; i++) (i + 1 + d.year % 2) % 3];

/// Three covers hidden in coarse light. Pick one: the wrong ones turn to ash.
class GuessScene extends FilmScene {
  @override
  String get id => 'guess';
  @override
  double get length => 12;
  @override
  double get still => 5;
  @override
  String why(WrappedData d) => 'These are your three most played songs, shuffled. The one you played most is the answer.';
  @override
  String share(WrappedData d) => 'Guess my number one of ${d.year}.';
  @override
  String speech(WrappedData d) => 'Guess your number one: ${[for (final i in guessOrder(d)) d.songs[i].title].join(', ')}.';
  @override
  String? get hint => 'Tap your guess';

  /// Where card [k] hangs.
  static Rect card(Size s, int k, double t) {
    final u = s.width / 360;
    final side = 138 * u;
    final x = [s.width * 0.26, s.width * 0.74, s.width * 0.36][k];
    final y = [s.height * 0.36, s.height * 0.44, s.height * 0.71][k];
    return Rect.fromCenter(center: Offset(x, y + math.sin(t * 1.3 + k * 2) * 6 * u), width: side, height: side);
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final k = i % 3;
    final j = i ~/ 3;
    final box = card(f.size, k, f.t);
    const side = 22;
    if (j >= side * side) return _drift(f, i, o);
    final song = guessOrder(f.d)[k];
    final cover = f.assets.songs[song];
    final cell = box.width / side;
    final gx = j % side, gy = j ~/ side;
    var rgb = 0xFFFFFF;
    var alpha = 0.3 + 0.5 * rnd(gx ~/ 4 + (gy ~/ 4) * 9 + k * 77, 8);
    // after a guess the right one sharpens to its true pixels; before, only coarse blocks of its colour
    final picked = f.touch.guess;
    final since = picked == null ? -1.0 : f.t - f.touch.guessAt;
    final sharp = picked != null && song == 0 ? clamp01(since / 0.8) : 0.0;
    if (cover != null) {
      final block = sharp > 0.5 ? 1 : 5;
      final cx = ((gx ~/ block * block + block / 2) / side * cover.side).floor().clamp(0, cover.side - 1);
      final cy = ((gy ~/ block * block + block / 2) / side * cover.side).floor().clamp(0, cover.side - 1);
      rgb = cover.pixels[cy * cover.side + cx] & 0xFFFFFF;
      alpha = 0.95;
    }
    final wob = _wave(f.t * 0.6 + rnd(i, 9)) * 1.4 * f.u;
    var x = box.left + (gx + 0.5) * cell + wob;
    var y = box.top + (gy + 0.5) * cell + _wave(f.t * 0.5 + rnd(i, 10)) * 1.4 * f.u;
    var r = cell * 0.6;
    if (picked != null && since > 0 && song != 0) {
      final fall = math.max(0.0, since - rnd(i, 11) * 0.5);
      x += (rnd(i, 12) - 0.5) * 160 * f.u * fall;
      y += 420 * f.u * fall * fall - 40 * f.u * fall;
      alpha *= clamp01(1 - fall * 0.9);
      r *= 1 - 0.4 * clamp01(fall);
    } else if (sharp > 0) {
      final g = 1 + 0.16 * Curves.elasticOut.transform(sharp);
      x = box.center.dx + (x - box.center.dx) * g;
      y = box.center.dy + (y - box.center.dy) * g;
      r *= g;
    }
    o.set(x, y, r, alpha, rgb);
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    f.film.kinetic(f, 'Which one was your number one?', x: 24 * u, y: f.h * 0.115, size: 31 * u, at: 0.7);
    final picked = f.touch.guess;
    final order = guessOrder(f.d);
    for (var k = 0; k < 3; k++) {
      if (picked != null && order[k] != 0) continue;
      final box = card(f.size, k, f.t);
      f.film.kinetic(f, f.d.songs[order[k]].title, x: box.center.dx, y: box.bottom + (picked == null ? 10 : 22) * u, size: 15 * u, at: 1.5 + k * 0.2, width: 156 * u, lines: 1, weight: FontWeight.w600, center: true);
    }
    if (picked != null) {
      final said = order[picked] == 0 ? 'You know yourself.' : 'It was this one all along.';
      f.film.kinetic(f, said, x: f.w / 2, y: f.h * 0.86, size: 24 * u, at: f.touch.guessAt + 0.5, center: true, lines: 1);
    }
  }
}

// ── 4. Record ───────────────────────────────────────────────────────────────

/// The cover builds itself from its own pixels, rounds into a record, and spins inside its sound.
class RecordScene extends FilmScene {
  @override
  String get id => 'number-one';
  @override
  double get length => 9;
  @override
  double get still => 6.6;
  @override
  String why(WrappedData d) => 'The song your server counted the most plays for in ${d.year}: ${d.songs.first.plays}.';
  @override
  String share(WrappedData d) => 'My song of ${d.year}: ${d.songs.first.title}.';
  @override
  String speech(WrappedData d) => 'Your song of the year: ${d.songs.first.title} by ${d.songs.first.artist}, ${d.songs.first.plays} plays.';
  @override
  String? get hint => 'Tap to drop the bass';

  Rect _box(FilmFrame f) => Rect.fromCenter(center: Offset(f.w / 2, f.h * 0.38), width: 232 * f.u, height: 232 * f.u);

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final box = _box(f);
    final cover = f.assets.songs[0];
    final leave = ramp(f.t, 2.5 + rnd(i, 20) * 0.6, 3.5 + rnd(i, 20) * 0.6);
    final has = _pixel(cover, box, i, n, o);
    if (!has) _drift(f, i, o);
    if (leave <= 0) return;
    // sound rings, beating
    final ring = i % 4;
    final a = (i ~/ 4) / (n / 4) * kTau + f.t * (0.25 + ring * 0.07) * (ring.isEven ? 1 : -1);
    final beat = math.pow(1 - (f.t * 1.7 % 1), 3).toDouble();
    final bump = math.sin(a * (5 + ring * 2) + f.t * 4) * (5 + 9 * beat) * f.u;
    final r = box.width / 2 + (11 + ring * 11 + beat * 8) * f.u + bump * 0.75;
    final x = box.center.dx + math.cos(a) * r, y = box.center.dy + math.sin(a) * r;
    o.set(mix(o.x, x, leave), mix(o.y, y, leave), mix(o.r, (1.7 - ring * 0.25) * f.u, leave), mix(o.a, 0.95 - ring * 0.18, leave), o.rgb);
  }

  @override
  void under(FilmFrame f) {
    final image = f.assets.songs[0]?.image;
    final box = _box(f);
    final show = ramp(f.t, 2.2, 2.8);
    final round = ramp(f.t, 3.0, 3.9);
    if (show <= 0) return;
    final angle = math.max(0.0, f.t - 3.4) * 1.5 + f.touch.spin;
    final beat = math.pow(1 - (f.t * 1.7 % 1), 3).toDouble() * round;
    final b = Rect.fromCenter(center: box.center, width: box.width * (1 + 0.025 * beat), height: box.width * (1 + 0.025 * beat));
    f.film.picture(f.canvas, image, b, radius: mix(6 * f.u, b.width / 2, round), angle: angle, alpha: show);
    if (round > 0) {
      final groove = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7 * f.u
        ..color = Color.fromRGBO(0, 0, 0, 0.35 * round);
      for (var i = 0; i < 11; i++) {
        f.canvas.drawCircle(b.center, b.width * (0.15 + i * 0.032), groove);
      }
      f.canvas.drawCircle(b.center, b.width * 0.05 * round, Paint()..color = const Color(0xFF000000));
    }
  }

  @override
  void over(FilmFrame f) {
    final u = f.u, s = f.d.songs.first;
    final y = math.max(f.h * 0.71, f.h * 0.38 + 222 * u);
    f.film.kinetic(f, 'Your number one', x: f.w / 2, y: y - 30 * u, size: 17 * u, at: 3.6, weight: FontWeight.w600, color: kDim, center: true);
    final h = f.film.kinetic(f, s.title, x: f.w / 2, y: y, size: 42 * u, at: 3.8, center: true);
    final h2 = f.film.kinetic(f, s.artist, x: f.w / 2, y: y + h + 4 * u, size: 19 * u, at: 4.3, weight: FontWeight.w500, color: kDim, center: true, lines: 1);
    f.film.counter(f, s.plays, (v) => '$v plays', x: f.w / 2, y: y + h + h2 + 18 * u, size: 24 * u, from: 4.6, to: 6, center: true);
  }
}

// ── 5. Countdown ────────────────────────────────────────────────────────────

/// Five to one: each cover shatters, and its pieces become the next.
class CountdownScene extends FilmScene {
  static const beat = 2.0;
  @override
  String get id => 'top5';
  @override
  double get length => 14;
  @override
  double get still => 13.2;
  @override
  String why(WrappedData d) => 'Your songs ranked by how many times you played them in ${d.year}.';
  @override
  String share(WrappedData d) => 'My top five songs of ${d.year}.';
  @override
  String speech(WrappedData d) => 'Your top songs: ${[for (var i = 0; i < d.songs.length; i++) '${i + 1}, ${d.songs[i].title}'].join('; ')}.';
  @override
  String? get hint => 'Tap to smash to the next';

  (int, double) _at(FilmFrame f) {
    final n = f.d.songs.length;
    final t = math.max(0.0, f.t - 1.0);
    final k = math.min(n - 1, t ~/ beat);
    return (n - 1 - k, t - k * beat);
  }

  bool _lineup(FilmFrame f) => f.t > 1.0 + f.d.songs.length * beat;
  Rect _box(FilmFrame f) => Rect.fromCenter(center: Offset(f.w / 2, f.h * 0.43), width: 262 * f.u, height: 262 * f.u);

  Rect _row(FilmFrame f, int k) {
    final u = f.u, side = 76 * u;
    return Rect.fromLTWH(24 * u + k * 8 * u, f.h * 0.2 + k * 88 * u, side, side);
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final (rank, t) = _at(f);
    if (_lineup(f)) {
      final since = f.t - 1.0 - f.d.songs.length * beat;
      _drift(f, i, o, a: 0.45);
      final a = rnd(i, 30) * kTau;
      final far = (1 - math.exp(-since * 3)) * 300 * f.u * rnd(i, 31);
      final k = ramp(since, 0.4, 1.6);
      o.x = mix(f.w / 2 + math.cos(a) * far, o.x, k);
      o.y = mix(f.h * 0.43 + math.sin(a) * far, o.y, k);
      return;
    }
    final box = _box(f);
    final cover = f.assets.songs[rank];
    if (!_pixel(cover, box, i, n, o)) _drift(f, i, o);
    final tx = o.x, ty = o.y, rgb = o.rgb, r = o.r, al = o.a;
    if (rank < f.d.songs.length - 1 && t < 1.05) {
      // the last cover's shards, thrown outwards, called home as the next
      final prev = f.assets.songs[rank + 1];
      if (!_pixel(prev, box, i, n, o)) _drift(f, i, o);
      final ang = math.atan2(o.y - box.center.dy, o.x - box.center.dx) + (rnd(i, 32) - 0.5);
      final blow = math.sin(math.pi * clamp01(t / 1.05)) * (50 + 190 * rnd(i, 33)) * f.u;
      final k = ramp(t, 0.2 + rnd(i, 34) * 0.25, 0.8 + rnd(i, 34) * 0.25);
      o.set(mix(o.x, tx, k) + math.cos(ang) * blow, mix(o.y, ty, k) + math.sin(ang) * blow, mix(o.r, r, k) * (1 + blow / (300 * f.u)), mix(o.a, al, k), k > 0.5 ? rgb : o.rgb);
    }
  }

  @override
  void under(FilmFrame f) {
    if (_lineup(f)) return;
    final (rank, t) = _at(f);
    // the rank, enormous, sliding behind the cover
    final big = f.film.words('${rank + 1}', 430 * f.u, color: const Color(0xFF1C1C1E));
    final k = Curves.easeOutExpo.transform(clamp01(t / 0.7));
    big.paint(f.canvas, Offset(f.w / 2 - big.width / 2 + (1 - k) * f.w, f.h * 0.43 - big.height / 2));
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    final songs = f.d.songs;
    if (!_lineup(f)) {
      if (f.t < 1.0 && songs.isNotEmpty) f.film.kinetic(f, 'The countdown', x: 24 * u, y: f.h * 0.12, size: 31 * u, at: 0.2);
      final (rank, t) = _at(f);
      final image = f.assets.songs[rank]?.image;
      final show = rank == songs.length - 1 ? ramp(f.t, 1.4, 1.8) : ramp(t, 0.95, 1.2);
      final out = 1 - ramp(t, beat - 0.12, beat);
      final pop = 1 + 0.05 * math.sin(math.pi * clamp01((t - 0.95) / 0.4));
      final box = _box(f);
      f.film.picture(f.canvas, image, Rect.fromCenter(center: box.center, width: box.width * pop, height: box.width * pop), radius: 6 * u, alpha: show * (rank == 0 ? 1 : out), angle: (rank.isEven ? 1 : -1) * 0.03 * pop);
      final local = FilmFrame(f.film, f.canvas, f.size, t, f.touch, f.name);
      final y = f.h * 0.71;
      final h = f.film.kinetic(local, songs[rank].title, x: f.w / 2, y: y, size: 33 * u, at: rank == songs.length - 1 ? 0.5 : 0.75, center: true);
      f.film.kinetic(local, songs[rank].artist, x: f.w / 2, y: y + h + 3 * u, size: 17 * u, at: 0.95, weight: FontWeight.w500, color: kDim, center: true, lines: 1);
      return;
    }
    final since = f.t - 1.0 - songs.length * beat;
    final local = FilmFrame(f.film, f.canvas, f.size, since, f.touch, f.name);
    f.film.kinetic(local, 'Your top ${songs.length}', x: 24 * u, y: f.h * 0.11, size: 31 * u, at: 0.2);
    for (var k = 0; k < songs.length; k++) {
      final row = _row(f, k);
      final inK = ramp(since, 0.1 + k * 0.1, 0.7 + k * 0.1, Curves.easeOutBack);
      final from = _box(f);
      final r = Rect.lerp(from, row, inK)!;
      f.film.picture(f.canvas, f.assets.songs[k]?.image, r, radius: 6 * u, alpha: clamp01(inK), angle: (1 - inK) * (k - 2) * 0.5);
      final x = row.right + 14 * u;
      final tx = f.w - x - 20 * u;
      f.film.kinetic(local, '${k + 1}  ${songs[k].title}', x: x, y: row.top + 14 * u, size: 19 * u, at: 0.4 + k * 0.1, width: tx, lines: 1, weight: FontWeight.w700);
      f.film.kinetic(local, '${songs[k].artist} · ${songs[k].plays} plays', x: x, y: row.top + 40 * u, size: 13.5 * u, at: 0.5 + k * 0.1, width: tx, lines: 1, weight: FontWeight.w500, color: kDim);
    }
  }
}

// ── 6. Solar ────────────────────────────────────────────────────────────────

/// Your number one is the sun. The rest are worlds around it; throw them.
class SolarScene extends FilmScene {
  @override
  String get id => 'artists';
  @override
  double get length => 9;
  @override
  double get still => 6;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'Artists by plays across all their songs. The nearer and bigger the world, the more you played it.';
  @override
  String share(WrappedData d) => 'My artist of ${d.year}: ${d.artists.first.name}.';
  @override
  String speech(WrappedData d) => 'Your top artists: ${[for (final a in d.artists) a.name].join(', ')}.';
  @override
  String? get hint => 'Throw the planets';

  Offset _c(FilmFrame f) => Offset(f.w / 2, f.h * 0.43);
  static const _tilt = 0.42;
  double _orbit(FilmFrame f, int k) => (82 + k * 16) * f.u;

  (Offset, double) _world(FilmFrame f, int k) {
    final a = 1.1 + k * 2.4 + (f.t * 0.75 + f.touch.spin) / (1 + k * 0.28);
    final r = _orbit(f, k);
    final z = math.sin(a);
    final roll = -0.28;
    final x = math.cos(a) * r, y = z * r * _tilt;
    return (_c(f) + Offset(x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll)) * ramp(f.t, 0.4, 1.9, Curves.easeOutBack), z);
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final c = _c(f);
    if (i < n * 0.45) {
      // the corona
      final a = rnd(i, 40) * kTau + f.t * 0.2;
      final flare = math.pow(rnd(i, 41), 3).toDouble();
      final lick = (f.t * (0.25 + rnd(i, 42) * 0.4) + rnd(i, 43)) % 1;
      final r = 58 * f.u + flare * 40 * f.u * lick + 4 * f.u * _wave(a * 2 + f.t * 0.3);
      o.set(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r, (1.9 - lick) * f.u, (1 - lick) * 0.95);
      return;
    }
    final k = i % 5;
    final others = f.d.artists.length - 1;
    if (k >= others) return _drift(f, i, o);
    final a = rnd(i, 44) * kTau + (f.t * 0.75 + f.touch.spin) / (1 + k * 0.28);
    final r = _orbit(f, k) + (rnd(i, 45) - 0.5) * 3 * f.u;
    final z = math.sin(a);
    final x = math.cos(a) * r, y = z * r * _tilt;
    o.set(c.dx + x * math.cos(-0.28) - y * math.sin(-0.28), c.dy + x * math.sin(-0.28) + y * math.cos(-0.28), (0.7 + 0.5 * (z + 1) / 2) * f.u, 0.12 + 0.3 * (z + 1) / 2);
  }

  void _planet(FilmFrame f, int k) {
    final (p, z) = _world(f, k);
    final size = (64 - k * 6) * f.u * (1 + z * 0.22) * ramp(f.t, 0.6 + k * 0.1, 1.5 + k * 0.1, Curves.easeOutBack);
    final rect = Rect.fromCenter(center: p, width: size, height: size);
    f.canvas.drawOval(rect.inflate(1.5 * f.u), Paint()..color = const Color(0xFF000000));
    final image = f.assets.artists[k + 1];
    if (image == null) {
      f.canvas.drawOval(rect, Paint()..shader = const RadialGradient(center: Alignment(-0.5, -0.6), radius: 1.1, colors: [Color(0xFFE5E5EA), Color(0xFF48484A), Color(0xFF111111)]).createShader(rect));
    } else {
      f.film.picture(f.canvas, image, rect, radius: size / 2);
      // the side away from the sun is in shadow
      final toSun = (_c(f) - p) / (p - _c(f)).distance.clamp(1, double.infinity);
      f.canvas.drawOval(rect, Paint()..shader = RadialGradient(center: Alignment(toSun.dx * 0.6, toSun.dy * 0.6), radius: 1, colors: const [Color(0x00000000), Color(0x00000000), Color(0xB3000000)], stops: const [0, 0.5, 1]).createShader(rect));
    }
  }

  @override
  void under(FilmFrame f) {
    for (var k = math.min(5, f.d.artists.length - 1) - 1; k >= 0; k--) {
      if (_world(f, k).$2 < 0) _planet(f, k);
    }
    final pulse = 1 + 0.02 * math.sin(f.t * 3);
    final s = 112 * f.u * ramp(f.t, 0.2, 1.1, Curves.easeOutBack) * pulse;
    final rect = Rect.fromCenter(center: _c(f), width: s, height: s);
    f.canvas.drawOval(rect, Paint()..color = kInk);
    f.film.picture(f.canvas, f.assets.artists[0], rect.deflate(2 * f.u), radius: s / 2);
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    final list = f.d.artists;
    for (var k = 0; k < math.min(5, list.length - 1); k++) {
      final (p, z) = _world(f, k);
      if (z >= 0) _planet(f, k);
      final show = ramp(f.t, 2 + k * 0.1, 2.6 + k * 0.1) * clamp01((z + 0.5) * 2);
      if (show > 0.02) {
        final (s, rows) = f.film.fit(list[k + 1].name, 13 * u, 110 * u, 1, FontWeight.w600);
        final tp = f.film.words(rows.first, s, weight: FontWeight.w600, color: Color.fromRGBO(255, 255, 255, (show * 10).round() / 10));
        final left = (p.dx - tp.width / 2).clamp(8 * u, math.max(8 * u, f.w - tp.width - 8 * u)).toDouble();
        tp.paint(f.canvas, Offset(left, p.dy + (36 - k * 3) * u * (1 + z * 0.2)));
      }
    }
    final y = f.h * 0.72;
    f.film.kinetic(f, 'Everything revolved around', x: f.w / 2, y: y, size: 18 * u, at: 1.0, weight: FontWeight.w600, color: kDim, center: true, lines: 1);
    final h = f.film.kinetic(f, list.first.name, x: f.w / 2, y: y + 26 * u, size: 45 * u, at: 1.3, center: true);
    f.film.kinetic(f, '${list.first.plays} plays · ${list.first.songs} songs', x: f.w / 2, y: y + 32 * u + h, size: 16 * u, at: 2.0, weight: FontWeight.w500, color: kDim, center: true, lines: 1);
  }
}

// ── 7. Galaxy ───────────────────────────────────────────────────────────────

/// Your sound as a spiral galaxy: one arm for each genre, as many stars as its share.
class GalaxyScene extends FilmScene {
  final List<double> _edges = [];
  GalaxyScene(WrappedData d) {
    final g = d.genres.take(5).toList();
    final total = g.fold<double>(0, (a, b) => a + b.pct);
    var acc = 0.0;
    for (final x in g) {
      acc += total <= 0 ? 1 / g.length : x.pct / total;
      _edges.add(acc);
    }
  }
  @override
  String get id => 'genres';
  @override
  double get length => 8;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'One arm for each of your biggest genres, with as many stars as its share of your plays.';
  @override
  String share(WrappedData d) => 'My sound of ${d.year}: ${d.genres.first.name}.';
  @override
  String speech(WrappedData d) => 'Your genres: ${[for (final g in d.genres) '${g.name} ${g.pct.round()} percent'].join(', ')}.';
  @override
  String? get hint => 'Spin your galaxy';

  Offset _c(FilmFrame f) => Offset(f.w / 2, f.h * 0.37);

  Offset _project(FilmFrame f, double r, double a) {
    final tilt = 0.5 + 0.1 * math.sin(f.t * 0.5) + f.touch.tiltY * 0.2;
    final x = math.cos(a) * r, y = math.sin(a) * r * tilt;
    const roll = -0.35;
    return _c(f) + Offset(x * math.cos(roll) - y * math.sin(roll), x * math.sin(roll) + y * math.cos(roll));
  }

  double _angle(FilmFrame f, int arm, double q) => arm * kTau / _edges.length + q * 3.6 + f.t * 0.32 + f.touch.spin * 0.6;

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final v = (i + 0.5) / n;
    final arm = _edges.indexWhere((e) => v <= e).clamp(0, _edges.length - 1);
    final q = math.pow(rnd(i, 50), 0.7).toDouble();
    final open = ramp(f.t, 0.2, 2.2, Curves.easeOutCubic);
    final spread = (rnd(i, 51) + rnd(i, 52) - 1) * (0.25 + 0.5 * (1 - q));
    final p = _project(f, q * 165 * f.u * (0.25 + 0.75 * open), _angle(f, arm, q * open) + spread);
    final shade = (255 - arm * 34).clamp(90, 255);
    final tw = 0.6 + 0.4 * math.sin(f.t * 2.5 + i);
    o.set(p.dx, p.dy, (0.8 + (1 - q) * 1.5 * rnd(i, 53) + rnd(i, 54) * 0.6) * f.u, tw * (1 - q * 0.35), (shade << 16) | (shade << 8) | shade);
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    final g = f.d.genres.take(5).toList();
    f.film.kinetic(f, 'Your universe is mostly', x: 24 * u, y: f.h * 0.645, size: 18 * u, at: 1.2, weight: FontWeight.w600, color: kDim);
    final h = f.film.kinetic(f, g.first.name, x: 24 * u, y: f.h * 0.645 + 25 * u, size: 46 * u, at: 1.5, lines: 1);
    var y = f.h * 0.645 + 34 * u + h;
    for (var k = 0; k < g.length; k++) {
      final at = 2.2 + k * 0.14;
      final shade = (255 - k * 34).clamp(90, 255);
      final grow = ramp(f.t, at, at + 0.9, Curves.easeOutExpo);
      if (grow > 0) {
        // each share is a burst of light whose length is the share
        f.canvas.drawLine(
          Offset(24 * u, y + 9 * u),
          Offset(24 * u + 92 * u * grow * g[k].pct / math.max(1, g.first.pct), y + 9 * u),
          Paint()
            ..strokeWidth = 5 * u
            ..strokeCap = StrokeCap.round
            ..color = Color.fromRGBO(shade, shade, shade, 1),
        );
      }
      f.film.kinetic(f, '${g[k].name}  ${g[k].pct.round()}%', x: 132 * u, y: y, size: 15 * u, at: at, width: f.w - 156 * u, lines: 1, weight: FontWeight.w600);
      y += 23 * u;
    }
  }
}

// ── 8. Sunburst ─────────────────────────────────────────────────────────────

/// A day of your life as 24 rays. A hand sweeps round and stops at your hour; drag to turn back time.
class SunburstScene extends FilmScene {
  final List<double> _edges = [];
  SunburstScene(WrappedData d) {
    final total = d.hourly.fold<int>(0, (a, b) => a + b);
    var acc = 0.0;
    for (final v in d.hourly) {
      acc += v / math.max(1, total);
      _edges.add(acc);
    }
  }
  @override
  String get id => 'clock';
  @override
  double get length => 8;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'Plays for each hour of the day as your server recorded them, midnight at the top. Longer, denser rays are busier hours.';
  @override
  String share(WrappedData d) => 'My music hour of ${d.year}: ${sayHour(d.peakHour)}.';
  @override
  String speech(WrappedData d) => 'Your busiest hour is ${sayHour(d.peakHour)}.';
  @override
  String? get hint => 'Drag through the day';

  Offset _c(FilmFrame f) => Offset(f.w / 2, f.h * 0.42);

  int _hour(FilmFrame f) {
    final s = f.touch.scrubX;
    if (s != null) return (s * 24).floor().clamp(0, 23);
    return (f.d.peakHour * ramp(f.t, 0.9, 3.2, Curves.easeInOutQuart)).round().clamp(0, 23);
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final v = (i + 0.5) / n;
    var hour = _edges.indexWhere((e) => v <= e);
    if (hour < 0) hour = 23;
    final peak = f.d.hourly.fold<int>(1, math.max);
    final share = f.d.hourly[hour] / peak;
    final now = _hour(f);
    final hot = hour == now;
    final q = rnd(i, 60);
    final travel = (q + f.t * (hot ? 0.5 : 0.1)) % 1;
    final grow = ramp(f.t, 0.3 + hour * 0.03, 1.4 + hour * 0.03, Curves.easeOutBack);
    final r = 84 * f.u + travel * (14 + 72 * share + (hot ? 18 : 0)) * f.u * grow;
    final a = (hour + 0.5) / 24 * kTau - math.pi / 2 + (rnd(i, 61) - 0.5) * 0.13;
    final lit = hour <= now;
    final c = _c(f);
    o.set(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r, (hot ? 2.3 : 1.35) * f.u * (1 - travel * 0.4), (hot ? 1 : (lit ? 0.62 : 0.25)) * (1 - travel * 0.55));
  }

  @override
  void under(FilmFrame f) {
    final c = _c(f);
    final a = (_hour(f) + 0.5) / 24 * kTau - math.pi / 2;
    final k = ramp(f.t, 0.5, 1.2);
    f.canvas.drawLine(
      c + Offset.fromDirection(a, 62 * f.u),
      c + Offset.fromDirection(a, 62 * f.u + 16 * f.u * k),
      Paint()
        ..color = kInk
        ..strokeWidth = 3.4 * f.u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void over(FilmFrame f) {
    final u = f.u, c = _c(f), h = _hour(f);
    if (f.t > 0.8) {
      final tp = f.film.words(sayHour(h), h == 0 ? 25 * u : 36 * u);
      tp.paint(f.canvas, c - Offset(tp.width / 2, tp.height / 2 + 7 * u));
      final p = f.film.words('${compactCount(f.d.hourly[h])} plays', 13 * u, weight: FontWeight.w600, color: kDim);
      p.paint(f.canvas, c + Offset(-p.width / 2, 15 * u));
    }
    final peak = f.d.peakHour;
    final line = peak >= 22 || peak < 5
        ? 'You come alive after dark.'
        : peak < 12
        ? 'You start the day loud.'
        : peak < 17
        ? 'Afternoons had a soundtrack.'
        : 'Evenings were yours.';
    f.film.kinetic(f, line, x: f.w / 2, y: f.h * 0.75, size: 34 * u, at: 3.3, center: true);
  }
}

// ── 9. Comet ────────────────────────────────────────────────────────────────

/// The year as a spiral of days. A comet runs your longest streak and sets it alight.
class CometScene extends FilmScene {
  final List<double> _minutes;
  int _from = -1, _to = -1;
  CometScene(WrappedData d) : _minutes = List.filled(366, 0) {
    var peak = 1;
    for (final day in d.days) {
      peak = math.max(peak, day.minutes);
    }
    for (final day in d.days) {
      final t = day.parsed;
      if (t != null) _minutes[_index(t)] = day.minutes / peak;
    }
    final s = DateTime.tryParse(d.streakStart ?? ''), e = DateTime.tryParse(d.streakEnd ?? '');
    if (s != null && e != null) {
      _from = _index(s);
      _to = _index(e);
    }
  }
  static int _index(DateTime t) => DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(t.year)).inDays.clamp(0, 365);

  @override
  String get id => 'streak';
  @override
  double get length => 8;
  @override
  double get still => 6.8;
  @override
  String why(WrappedData d) => 'Days in a row with music. Every point on the spiral is a day, January at the centre; brighter days had more minutes.';
  @override
  String share(WrappedData d) => 'My longest streak of ${d.year}: ${d.longestStreak} days.';
  @override
  String speech(WrappedData d) => 'Your longest streak was ${d.longestStreak} days, ${sayDate(d.streakStart)} to ${sayDate(d.streakEnd)}.';

  Offset _day(FilmFrame f, double i, double turn) {
    final q = math.sqrt((i + 14) / 380);
    final a = q * 4.2 * kTau + turn;
    return Offset(f.w / 2, f.h * 0.39) + Offset(math.cos(a), math.sin(a)) * q * 158 * f.u;
  }

  double _head(FilmFrame f) => _from < 0 ? -1 : mix(_from.toDouble(), _to.toDouble(), ramp(f.t, 2.0, 5.2, Curves.easeInOutCubic));

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final turn = f.t * 0.1 - 1.2 * (1 - ramp(f.t, 0, 2.2, Curves.easeOutCubic));
    final head = _head(f);
    if (i < 366) {
      final p = _day(f, i.toDouble(), turn);
      final m = _minutes[i];
      var r = m > 0 ? 1.8 + m * 1.6 : 1.1;
      var a = m > 0 ? 0.3 + 0.4 * m : 0.14;
      if (f.t > 2 && i >= _from && i <= head && _from >= 0) {
        r = 4.2 + 1.0 * math.sin(f.t * 9 + i);
        a = 1;
      }
      o.set(p.dx, p.dy, r * f.u, a);
      return;
    }
    if (_from >= 0 && f.t > 2 && i % 3 != 0) {
      // sparks thrown off the burning stretch
      final life = (f.t * (0.6 + rnd(i, 70) * 0.9) + rnd(i, 71)) % 1;
      final born = mix(_from.toDouble(), head, rnd(i, 72));
      final p = _day(f, born, turn);
      final a = rnd(i, 73) * kTau;
      o.set(p.dx + math.cos(a) * life * 22 * f.u, p.dy + math.sin(a) * life * 22 * f.u - life * life * 30 * f.u, (1.8 - life * 1.4) * f.u, (1 - life) * 0.85);
      return;
    }
    _drift(f, i, o, a: 0.22);
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    final y = f.h * 0.66;
    if (_from >= 0 && f.t > 2 && f.t < 5.6) {
      final p = _day(f, _head(f), f.t * 0.1 - 1.2 * (1 - ramp(f.t, 0, 2.2, Curves.easeOutCubic)));
      f.canvas.drawCircle(p, (7 + math.sin(f.t * 30)) * u, Paint()..color = kInk);
    }
    f.film.counter(f, f.d.longestStreak, (v) => '$v', x: 24 * u, y: y, size: 104 * u, from: 2, to: 5.2, width: 190 * u);
    final tp = f.film.words('${f.d.longestStreak}', 104 * u);
    f.film.kinetic(f, f.d.longestStreak == 1 ? 'day' : 'days in a row', x: 24 * u + math.min(190 * u, tp.width) + 12 * u, y: y + 46 * u, size: 25 * u, at: 2.4, width: f.w - 60 * u - math.min(190 * u, tp.width), lines: 2);
    f.film.kinetic(f, 'You kept the fire going, ${sayDate(f.d.streakStart)} to ${sayDate(f.d.streakEnd)}.', x: 24 * u, y: y + 122 * u, size: 18 * u, at: 4.6, weight: FontWeight.w500, color: kDim);
  }
}

// ── 10. Warp ────────────────────────────────────────────────────────────────

/// Hyperspace through everything you played.
class WarpScene extends FilmScene {
  final Float32List _lines = Float32List(360 * 4);
  @override
  String get id => 'discovery';
  @override
  double get length => 7;
  @override
  String why(WrappedData d) => 'How many different songs and artists you played in ${d.year}.';
  @override
  String share(WrappedData d) => 'I travelled through ${d.uniqueSongs} songs in ${d.year}.';
  @override
  String speech(WrappedData d) => 'You played ${d.uniqueSongs} different songs by ${d.uniqueArtists} artists.';
  @override
  String? get hint => 'Drag to steer';
  @override
  bool get drags => true;

  double _run(double t) => t * 0.16 + 1.5 * ramp(t, 0.8, 3.4, Curves.easeInOutCubic);

  Offset _vanish(FilmFrame f) => Offset(f.w / 2 + f.touch.tiltX * 90 * f.u, f.h * 0.42 + f.touch.tiltY * 90 * f.u);

  double _z(int i, double t) => 1 - ((rnd(i, 80) + _run(t)) % 1);

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final z = _z(i, f.t);
    final a = rnd(i, 81) * kTau + f.t * 0.12;
    final r = (14 + 190 * math.sqrt(rnd(i, 82))) * f.u / (z + 0.06) * 0.42;
    final v = _vanish(f);
    final x = v.dx + math.cos(a) * r, y = v.dy + math.sin(a) * r;
    // once the words are up the stars behind them go out
    final words = (y - (f.h * 0.42 + 34 * f.u)).abs() < 104 * f.u && (x - f.w / 2).abs() < 170 * f.u;
    final dim = words ? 1 - 0.88 * ramp(f.t, 2.8, 3.8) : 1.0;
    o.set(x, y, (0.5 + (1 - z) * 2.4) * f.u, math.min(1, (1 - z) * 1.5) * dim);
  }

  @override
  void under(FilmFrame f) {
    final speed = ramp(f.t, 1.0, 1.8) * (1 - ramp(f.t, 2.8, 3.8));
    if (speed <= 0.01) return;
    final v = _vanish(f);
    for (var i = 0; i < 360; i++) {
      final z = _z(i, f.t);
      final a = rnd(i, 81) * kTau + f.t * 0.12;
      final k = (14 + 190 * math.sqrt(rnd(i, 82))) * f.u * 0.42;
      final r1 = k / (z + 0.06), r2 = k / (z + 0.06 + 0.22 * speed);
      _lines[i * 4] = v.dx + math.cos(a) * r1;
      _lines[i * 4 + 1] = v.dy + math.sin(a) * r1;
      _lines[i * 4 + 2] = v.dx + math.cos(a) * r2;
      _lines[i * 4 + 3] = v.dy + math.sin(a) * r2;
    }
    f.canvas.drawRawPoints(
      PointMode.lines,
      _lines,
      Paint()
        ..strokeWidth = 1.3 * f.u
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(255, 255, 255, 0.5 * speed),
    );
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    // the numbers fly at you from the vanishing point
    final k = ramp(f.t, 1.6, 3.6, Curves.easeOutExpo);
    if (k > 0.01) {
      f.canvas.save();
      final c = Offset(f.w / 2, f.h * 0.42);
      f.canvas.translate(c.dx, c.dy);
      f.canvas.scale(0.05 + 0.95 * k);
      f.canvas.translate(-c.dx, -c.dy);
      f.film.counter(f, f.d.uniqueSongs, _grouped, x: f.w / 2, y: f.h * 0.42 - 62 * u, size: 112 * u, from: 1.6, to: 3.6, center: true);
      f.canvas.restore();
    }
    f.film.kinetic(f, 'different songs', x: f.w / 2, y: f.h * 0.42 + 64 * u, size: 30 * u, at: 3.0, center: true, lines: 1);
    f.film.kinetic(f, 'from ${_grouped(f.d.uniqueArtists)} artists', x: f.w / 2, y: f.h * 0.42 + 104 * u, size: 20 * u, at: 3.7, weight: FontWeight.w500, color: kDim, center: true, lines: 1);
  }
}

// ── 11. Spirit ──────────────────────────────────────────────────────────────

/// Your personality takes a body: a moon, a compass, a heart, an endless loop or a wave, turning in space.
class SpiritScene extends FilmScene {
  final WrappedPersonality me;
  SpiritScene(WrappedData d) : me = d.personality;
  @override
  String get id => 'personality';
  @override
  double get length => 8;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) =>
      'Four measures from your year: how many different songs for your plays, how much was one artist, how much came between 10 pm and 5 am, and how big your biggest day was next to a usual one. The strongest names you.';
  @override
  String share(WrappedData d) => 'I am ${d.personality.name}.';
  @override
  String speech(WrappedData d) => 'Your listening personality: ${d.personality.name}. ${d.personality.line}';
  @override
  String? get hint => 'Turn it around';

  /// A point of the body in -1..1, with depth.
  (double, double, double) _body(int i, int n) {
    final v = i / n, j = rnd(i, 100), z = (rnd(i, 101) - 0.5) * 0.36;
    switch (me.id) {
      case 'night': // a crescent: a disc with a disc bitten out
        for (var k = 0; k < 6; k++) {
          final a = rnd(i, 102 + k) * kTau, r = math.sqrt(rnd(i, 110 + k));
          final x = math.cos(a) * r, y = math.sin(a) * r;
          if ((x - 0.42) * (x - 0.42) + (y + 0.12) * (y + 0.12) > 0.68) return (x + 0.2, y, z);
        }
        final a = 0.7 + v * 5.0;
        return (math.cos(a) + 0.2, math.sin(a), z);
      case 'explorer': // a compass star
        final a = v * kTau * 3 % kTau;
        final spike = math.pow((math.cos(a * 2)).abs(), 3.2).toDouble();
        final small = math.pow((math.sin(a * 2)).abs(), 9).toDouble() * 0.5;
        final r = (0.16 + 0.92 * spike + small) * math.sqrt(j);
        return (math.cos(a) * r, math.sin(a) * r, z * (1 - r * 0.7));
      case 'devotee': // a heart
        final a = v * kTau * 5 % kTau;
        final s = math.sqrt(j);
        final x = 16 * math.pow(math.sin(a), 3) / 17;
        final y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a)) / 17;
        return (x * s, y * s, z * (1.4 - s));
      case 'marathon': // an endless loop
        final a = v * kTau * 3 % kTau;
        final den = 1 + math.sin(a) * math.sin(a);
        final tube = rnd(i, 103) * kTau;
        return (1.15 * math.cos(a) / den + math.cos(tube) * 0.1, 1.15 * math.sin(a) * math.cos(a) / den * 1.35 + math.sin(tube) * 0.1, math.sin(a) * 0.3 + z * 0.4);
      default: // a calm wave
        final x = v * 2 - 1;
        final row = i % 9;
        return (x, math.sin(x * 4 + row * 0.3) * 0.28 + (row - 4) * 0.11, (row - 4) * 0.08);
    }
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final body = (n * 0.86).floor();
    if (i >= body) return _drift(f, i, o, a: 0.5);
    final (x, y, z) = _body(i, body);
    final turn = math.sin(f.t * 0.7) * 0.5 + f.touch.spin;
    final cx = x * math.cos(turn) + z * math.sin(turn);
    final cz = -x * math.sin(turn) + z * math.cos(turn);
    final persp = 1 / (1.6 - cz * 0.35) * 1.6;
    final beat = me.id == 'devotee' ? 1 + 0.07 * math.pow(math.max(0, math.sin(f.t * 4.4)), 4) : 1 + 0.015 * math.sin(f.t * 2);
    // light pours along the body
    final flow = me.id == 'marathon' || me.id == 'easy' ? (i / body * 3 - f.t * 0.5) % 1 : rnd(i, 104);
    final glow = 0.45 + 0.55 * math.pow(0.5 + 0.5 * math.cos((flow + f.t * 0.15) * kTau), 2);
    o.set(f.w / 2 + cx * 122 * f.u * persp * beat, f.h * 0.37 + y * 122 * f.u * persp * beat, (1.2 + rnd(i, 105) * 0.9) * f.u * persp, glow * clamp01(0.65 + cz * 0.4));
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    f.film.kinetic(f, 'You are', x: f.w / 2, y: f.h * 0.655, size: 20 * u, at: 1.5, weight: FontWeight.w600, color: kDim, center: true);
    final h = f.film.kinetic(f, me.name, x: f.w / 2, y: f.h * 0.655 + 27 * u, size: 55 * u, at: 1.9, center: true, stagger: 0.25);
    f.film.kinetic(f, me.line, x: f.w / 2, y: f.h * 0.655 + 38 * u + h, size: 18 * u, at: 2.8, weight: FontWeight.w500, color: kDim, center: true, width: f.w - 64 * u, lines: 3, stagger: 0.04);
  }
}

// ── 12. Terrain ─────────────────────────────────────────────────────────────

/// Fly low over your year: twelve months as a mountain range made of light. Drag to climb any of them.
class TerrainScene extends FilmScene {
  static const _cols = 50;
  @override
  String get id => 'journey';
  @override
  double get length => 9;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'Minutes listened in each month, January on the left. Taller is more.';
  @override
  String share(WrappedData d) => '${_months[d.busiestMonth!.month - 1]} was my month of ${d.year}.';
  @override
  String speech(WrappedData d) => '${_months[d.busiestMonth!.month - 1]} was your biggest month, ${listeningTime(d.busiestMonth!.minutes)}.';
  @override
  String? get hint => 'Drag across the year';

  int _month(FilmFrame f) {
    final s = f.touch.scrubX;
    if (s != null) return (s * 12).floor().clamp(0, 11);
    final flown = ramp(f.t, 0.9, 4.6, Curves.easeInOutCubic);
    return f.t > 4.9 ? f.d.busiestMonth!.month - 1 : (flown * 11.99).floor();
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final rows = n ~/ _cols;
    final col = i % _cols, row = i ~/ _cols;
    if (row >= rows) return _drift(f, i, o);
    final x = (col + 0.5) / _cols; // the year, left to right
    final z = ((row + f.t * 0.9) % rows) / rows; // rows come towards you
    final m = x * 12 - 0.5;
    final i0 = m.floor().clamp(0, 11), i1 = (i0 + 1).clamp(0, 11);
    final months = f.d.months;
    final peak = months.fold<int>(1, (a, b) => math.max(a, b.minutes));
    final height = mix(months[i0].minutes.toDouble(), months[i1].minutes.toDouble(), clamp01(m - i0)) / peak;
    final depth = math.exp(-math.pow((z - 0.55) * 3.1, 2));
    final ragged = 1 + 0.18 * math.sin(x * 60 + row * 1.7) * depth;
    final grow = ramp(f.t, 0.5 + x * 0.7, 1.8 + x * 0.7, Curves.easeOutBack);
    final near = 1 / (1.7 - z);
    final sel = _month(f);
    final hot = (x * 12).floor() == sel;
    final px = f.w / 2 + (x - 0.5) * f.w * 1.02 * near;
    final py = f.h * (0.30 + 0.35 * z * near) - height * height * 150 * f.u * depth * ragged * grow + math.sin(f.t * 1.5 + x * 9 + z * 6) * 3 * f.u;
    o.set(px, py, (0.8 + near * 1.1) * f.u * (hot ? 1.45 : 1), (hot ? 1 : 0.3 + 0.3 * height) * clamp01(math.sin(z * math.pi) * 1.8));
  }

  @override
  void over(FilmFrame f) {
    final u = f.u;
    final k = _month(f), m = f.d.months[k];
    final y = f.h * 0.70;
    if (f.t > 0.8) {
      final tp = f.film.words(_months[k], 50 * u);
      tp.paint(f.canvas, Offset(24 * u, y));
      final line = m.minutes == 0 ? 'A quiet one.' : [listeningTime(m.minutes), ?m.topGenre, ?m.topSong].join(' · ');
      final (s, rows) = f.film.fit(line, 17 * u, f.w - 48 * u, 2, FontWeight.w500);
      for (var r = 0; r < rows.length; r++) {
        f.film.words(rows[r], s, weight: FontWeight.w500, color: kDim).paint(f.canvas, Offset(24 * u, y + 60 * u + r * s * 1.2));
      }
    }
    f.film.kinetic(f, '${_months[f.d.busiestMonth!.month - 1]} was your mountain.', x: 24 * u, y: f.h * 0.115, size: 31 * u, at: 4.9);
  }
}

// ── 13. Tide ────────────────────────────────────────────────────────────────

/// The sea rises past a usual day and keeps rising. Tilt it with your finger.
class TideScene extends FilmScene {
  final double usual;
  TideScene(WrappedData d)
    : usual = d.days.isEmpty || d.bestDay!.minutes == 0 ? 0 : clamp01(d.days.fold<int>(0, (a, b) => a + b.minutes) / d.days.length / d.bestDay!.minutes);
  @override
  String get id => 'best-day';
  @override
  double get length => 8;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'Your day with the most minutes. The line is your average over the days you listened.';
  @override
  String share(WrappedData d) => 'My biggest music day of ${d.year}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String speech(WrappedData d) => 'Your biggest day was ${sayDate(d.bestDay!.date)}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String? get hint => 'Tip the sea';

  double _level(double t) => mix(usual * ramp(t, 0.3, 1.8, Curves.easeOutCubic), 1, ramp(t, 2.6, 4.6, Curves.easeInOutBack));
  double _surface(FilmFrame f, double v) => f.h * (0.97 - 0.49 * v);

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    final top = _surface(f, _level(f.t));
    final x = rnd(i, 120) * (f.w + 20) - 10;
    final spray = i % 11 == 0 && f.t > 2.8;
    final swell = math.sin(x / f.w * 7 + f.t * 2.2) * 9 * f.u + math.sin(x / f.w * 15 - f.t * 3.1) * 4 * f.u;
    final tip = (x / f.w - 0.5) * f.touch.tiltX * 170 * f.u;
    if (spray) {
      final life = (f.t * 0.8 + rnd(i, 121)) % 1;
      final up = math.sin(life * math.pi) * (14 + 40 * rnd(i, 122)) * f.u;
      o.set(x + (rnd(i, 123) - 0.5) * 60 * f.u * life, top + swell + tip - up, 1.7 * f.u, (1 - life) * 0.9);
      return;
    }
    final q = rnd(i, 124);
    final depth = q * q * (f.h - top + 20 * f.u);
    final calm = 1 / (1 + depth / (80 * f.u));
    o.set(x + math.sin(f.t * 1.3 + i) * 5 * f.u, top + depth + (swell + tip) * (0.3 + 0.7 * calm), (1.1 + calm * 1.5) * f.u, 0.22 + 0.78 * calm * (0.7 + 0.3 * math.sin(f.t * 3 + i)));
  }

  @override
  void over(FilmFrame f) {
    final u = f.u, best = f.d.bestDay!;
    final k = ramp(f.t, 1.2, 2.0) * (1 - ramp(f.t, 3.0, 3.6));
    if (k > 0) {
      final y = _surface(f, usual);
      final p = Paint()
        ..color = Color.fromRGBO(255, 255, 255, 0.8 * k)
        ..strokeWidth = 1.6 * u;
      for (var x = 0.0; x < f.w * k; x += 12 * u) {
        f.canvas.drawLine(Offset(x, y - 22 * u), Offset(x + 6 * u, y - 22 * u), p);
      }
      f.film.kinetic(f, 'a usual day', x: 24 * u, y: y - 46 * u, size: 15 * u, at: 1.4, weight: FontWeight.w600);
    }
    f.film.kinetic(f, sayDate(best.date), x: 24 * u, y: f.h * 0.115, size: 44 * u, at: 2.7, lines: 1);
    f.film.kinetic(f, 'The day the music didn’t stop.', x: 24 * u, y: f.h * 0.115 + 54 * u, size: 18 * u, at: 3.2, weight: FontWeight.w500, color: kDim);
    f.film.counter(f, best.minutes, listeningTime, x: 24 * u, y: f.h * 0.115 + 86 * u, size: 74 * u, from: 3.0, to: 5.0);
  }
}

// ── 14. Poster ──────────────────────────────────────────────────────────────

/// Everything falls into place. The poster tilts in your hand and the light runs across it.
class PosterScene extends FilmScene {
  @override
  String get id => 'finale';
  @override
  double get length => 9;
  @override
  double get still => 6.2;
  @override
  bool get drags => true;
  @override
  String why(WrappedData d) => 'Your year on one poster. Your name is on what you share only if you turn it on.';
  @override
  String share(WrappedData d) => 'My ${d.year} Wrapped.';
  @override
  String speech(WrappedData d) =>
      '${d.year} Wrapped. ${listeningTime(d.totalMinutes)}${d.songs.isEmpty ? '' : ', number one ${d.songs.first.title}'}${d.artists.isEmpty ? '' : ', top artist ${d.artists.first.name}'}. ${d.personality.name}.';
  @override
  String? get hint => 'Tilt it';

  void _square(FilmFrame f) {
    final u = f.u, d = f.d, side = f.w * 0.4, rec = Offset(f.w * 0.72, f.h * 0.29);
    f.film.picture(f.canvas, d.songs.isEmpty ? null : f.assets.songs[0]?.image, Rect.fromCenter(center: rec, width: side, height: side), radius: side / 2, angle: f.t * 0.5);
    f.canvas.drawCircle(rec, side * 0.045, Paint()..color = const Color(0xFF000000));
    final x = 24 * u;
    final who = f.name == null || f.name!.isEmpty ? '${d.year} Wrapped' : '${f.name} · ${d.year}';
    f.film.kinetic(f, who, x: x, y: 24 * u, size: 16 * u, at: 0, weight: FontWeight.w700, lines: 1, width: 150 * u);
    f.film.kinetic(f, d.personality.name, x: x, y: 70 * u, size: 36 * u, at: 0, lines: 3, width: 140 * u);
    var y = 208 * u;
    for (final (k, v) in [
      ('Listened', '${_grouped(d.totalMinutes)} minutes'),
      if (d.songs.isNotEmpty) ('Song', d.songs.first.title),
      if (d.artists.isNotEmpty) ('Artist', d.artists.first.name),
      if (d.longestStreak > 1) ('Streak', '${d.longestStreak} days'),
    ]) {
      f.film.kinetic(f, k, x: x, y: y + 3 * u, size: 13 * u, at: 0, weight: FontWeight.w500, color: kDim, lines: 1);
      f.film.kinetic(f, v, x: x + 72 * u, y: y, size: 17 * u, at: 0, weight: FontWeight.w700, lines: 1, width: f.w - 120 * u);
      y += 26 * u;
    }
    f.film.kinetic(f, 'NaviVibe', x: x, y: f.h - 38 * u, size: 14 * u, at: 0, weight: FontWeight.w700);
  }

  @override
  void place(FilmFrame f, int i, int n, Dot o) {
    // confetti of light, then a slow halo around the record
    final square = f.h < f.w * 1.2;
    final c = square ? Offset(f.w * 0.72, f.h * 0.29) : Offset(f.w * 0.5, f.h * 0.29);
    final a = rnd(i, 130) * kTau + f.t * 0.18 * (i.isEven ? 1 : -1);
    final r = f.w * (square ? 0.225 : 0.315) + math.pow(rnd(i, 131), 2.4) * f.w * 0.4 + math.sin(a * 6 + f.t * 2) * 4 * f.u;
    final hx = c.dx + math.cos(a) * r, hy = c.dy + math.sin(a) * r;
    final fall = math.max(0.0, f.t - rnd(i, 132) * 0.8);
    final bx = f.w / 2 + (rnd(i, 133) - 0.5) * f.w * 1.5 * (1 - math.exp(-fall * 2.4));
    final by = f.h * 0.5 - 430 * f.u * fall * (0.4 + rnd(i, 134)) + 330 * f.u * fall * fall;
    final k = ramp(f.t, 1.2 + rnd(i, 135) * 0.6, 2.4 + rnd(i, 135) * 0.6);
    final rgb = i < (f.assets.songs[0]?.pixels.length ?? 0) ? f.assets.songs[0]!.pixels[i] & 0xFFFFFF : 0xFFFFFF;
    o.set(mix(bx, hx, k), mix(by, hy, k), (1.0 + rnd(i, 136) * 1.1) * f.u, mix(0.95, 0.7 * (0.6 + 0.4 * math.sin(f.t * 2 + i)), k), rgb);
  }

  @override
  void over(FilmFrame f) {
    final u = f.u, c = f.canvas, d = f.d;
    if (f.h < f.w * 1.2) return _square(f);
    c.save();
    final tilt = Matrix4.identity()
      ..setEntry(3, 2, 0.0011 / u)
      ..rotateY(f.touch.tiltX * 0.35)
      ..rotateX(-f.touch.tiltY * 0.3);
    c.translate(f.w / 2, f.h / 2);
    c.transform(tilt.storage);
    c.translate(-f.w / 2, -f.h / 2);
    final rec = Offset(f.w / 2, f.h * 0.29);
    final side = f.w * 0.56 * ramp(f.t, 1.4, 2.4, Curves.easeOutBack);
    f.film.picture(c, d.songs.isEmpty ? null : f.assets.songs[0]?.image, Rect.fromCenter(center: rec, width: side, height: side), radius: side / 2, angle: f.t * 0.5 + f.touch.spin * 0.4);
    if (side > 4) c.drawCircle(rec, side * 0.045, Paint()..color = const Color(0xFF000000));
    final x = 26 * u;
    var y = f.h * 0.535;
    final who = f.name == null || f.name!.isEmpty ? '${d.year} Wrapped' : '${f.name} · ${d.year} Wrapped';
    f.film.kinetic(f, who, x: x, y: f.h * 0.055, size: 17 * u, at: 1.6, weight: FontWeight.w700, lines: 1);
    y += f.film.kinetic(f, d.personality.name, x: x, y: y, size: 40 * u, at: 2.1, lines: 1) + 8 * u;
    void row(String k, String v, double at) {
      f.film.kinetic(f, k, x: x, y: y + 3 * u, size: 13 * u, at: at, weight: FontWeight.w500, color: kDim, lines: 1);
      f.film.kinetic(f, v, x: x + 74 * u, y: y, size: 18 * u, at: at + 0.08, width: f.w - x * 2 - 74 * u, lines: 1, weight: FontWeight.w700);
      y += 27 * u;
    }

    row('Listened', '${_grouped(d.totalMinutes)} minutes', 2.5);
    if (d.songs.isNotEmpty) row('Song', d.songs.first.title, 2.7);
    if (d.artists.isNotEmpty) row('Artist', d.artists.first.name, 2.9);
    if (d.genres.isNotEmpty) row('Sound', d.genres.first.name, 3.1);
    if (d.longestStreak > 1) row('Streak', '${d.longestStreak} days', 3.3);
    if (d.uniqueSongs > 0) row('Explored', '${_grouped(d.uniqueSongs)} songs', 3.5);
    f.film.kinetic(f, 'NaviVibe', x: x, y: f.h * 0.935, size: 15 * u, at: 3.8, weight: FontWeight.w700);
    // a band of light runs over the words
    final s = ramp(f.t % 4, 3.0, 3.9) * 1.6 - 0.3;
    if (s > -0.3 && s < 1.3) {
      c.save();
      c.translate(f.w * s, 0);
      c.skew(-0.35, 0);
      c.drawRect(Rect.fromLTWH(0, 0, 40 * u, f.h), Paint()..color = const Color(0x12FFFFFF));
      c.restore();
    }
    c.restore();
  }
}
