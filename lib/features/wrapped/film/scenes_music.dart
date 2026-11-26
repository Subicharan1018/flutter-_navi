import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// Songs and the people who made them.

ui.Image? _cover(FilmFrame f, String title, String artist) => f.assets.covers['$title|$artist'];

// ── Cards ───────────────────────────────────────────────────────────────────

/// Three cards: your top three. They turn face down and are shuffled; follow your number one.
class CardsScene extends FilmScene {
  static const _swaps = [(0, 1), (1, 2), (0, 2), (0, 1), (1, 2)];
  static const _start = 3.0, _each = 0.5;
  static double get ready => _start + _swaps.length * _each + 0.2;

  @override
  String get id => 'guess';
  @override
  String get technique => '3D three-card shuffle';
  @override
  double get length => 14;
  @override
  double get still => 1.9;
  @override
  double end(FilmTouch t) => t.guess == null ? length : t.guessAt + 3.4;
  @override
  String why(WrappedData d) => 'Your three most played songs. The answer is the one your server counted the most plays for.';
  @override
  String share(WrappedData d) => 'My top three of ${d.year}. Which is number one?';
  @override
  String speech(WrappedData d) => 'Your top three: ${[for (final s in d.songs.take(3)) nice(s.title)].join(', ')}. Which was number one?';
  @override
  String? get hint => 'Follow your number one';

  /// The slot (0 left .. 2 right) and the height of card [card] at [t].
  static (double, double) place(int card, double t) {
    final slots = [0, 1, 2]; // slots[card]
    for (var i = 0; i < _swaps.length; i++) {
      final k = clamp01((t - _start - i * _each) / _each);
      final (a, b) = _swaps[i];
      final ca = slots.indexOf(a), cb = slots.indexOf(b);
      if (k < 1) {
        final e = Curves.easeInOut.transform(k);
        if (card == ca) return (mix(a.toDouble(), b.toDouble(), e), math.sin(math.pi * k));
        if (card == cb) return (mix(b.toDouble(), a.toDouble(), e), -math.sin(math.pi * k));
        return (slots[card].toDouble(), 0);
      }
      slots[ca] = b;
      slots[cb] = a;
    }
    return (slots[card].toDouble(), 0);
  }

  Rect _rect(FilmFrame f, int card) {
    final u = f.u;
    final (slot, lift) = place(card, f.t);
    return Rect.fromCenter(center: Offset(f.w / 2 + (slot - 1) * 112 * u, f.h * 0.47 - lift * 70 * u), width: 100 * u, height: 152 * u);
  }

  /// Which of the top three (0 is number one) sits where you tapped, or -1.
  int hit(FilmFrame f, Offset p) => [0, 1, 2].indexWhere((c) => _rect(f, c).inflate(6 * f.u).contains(p));

  @override
  double? tap(FilmFrame f, Offset p) {
    if (f.t < ready || f.touch.guess != null) return null;
    final card = hit(f, p);
    if (card < 0) return null;
    f.touch
      ..guess = card
      ..guessAt = f.t;
    return null;
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final guess = f.touch.guess;
    final since = guess == null ? -1.0 : f.t - f.touch.guessAt;
    final ask = f.t < 2.6 ? 'Remember your number one.' : (f.t < ready ? 'Keep your eye on it.' : 'Now, which one is it?');
    f.film.kinetic(
      f,
      guess == null ? ask : (guess == 0 ? 'You know yourself.' : 'It slipped past you.'),
      x: 24 * u,
      y: f.h * 0.14,
      size: 34 * u,
      at: guess != null
          ? f.touch.guessAt + 0.5
          : f.t < 2.6
          ? 0.3
          : (f.t < ready ? 2.6 : ready),
    );
    final order = [0, 1, 2]..sort((a, b) => place(a, f.t).$2.abs().compareTo(place(b, f.t).$2.abs()));
    for (final card in order) {
      final s = f.d.songs[card];
      final r = _rect(f, card);
      final deal = ramp(f.t, 0.2 + card * 0.15, 0.9 + card * 0.15, Curves.easeOutBack);
      var turn = ramp(f.t, 2.2 + card * 0.1, 2.8 + card * 0.1); // 0 face up, 1 face down
      var scale = 1.0, dy = (1 - deal) * f.h * 0.6, angle = (1 - deal) * (card - 1) * 0.8;
      if (guess != null) {
        turn = 1 - ramp(since, card == guess ? 0.05 : 0.55, card == guess ? 0.5 : 1.0);
        if (card == 0) scale = 1 + 0.22 * ramp(since, 1.0, 1.6, Curves.easeOutBack);
        if (card != 0) {
          final drop = math.max(0.0, since - 1.2);
          dy += 900 * u * drop * drop;
          angle += (card == 1 ? -1 : 1) * drop * 1.6;
        }
      }
      final flip = math.cos(turn * math.pi);
      c.save();
      c.translate(r.center.dx, r.center.dy + dy);
      c.rotate(angle);
      c.scale(scale * math.max(0.02, flip.abs()), scale);
      final box = Rect.fromCenter(center: Offset.zero, width: r.width, height: r.height);
      final rr = RRect.fromRectAndRadius(box, Radius.circular(9 * u));
      if (flip > 0) {
        c.drawRRect(rr, fill(kInk));
        f.film.picture(c, _cover(f, s.title, s.artist), Rect.fromLTWH(box.left + 6 * u, box.top + 6 * u, box.width - 12 * u, box.width - 12 * u), radius: 4 * u, tile: true);
        final (size, rows) = f.film.fit(nice(s.title), 13 * u, box.width - 14 * u, 2, FontWeight.w700);
        for (var i = 0; i < rows.length; i++) {
          f.film.line(c, rows[i], 0, box.top + box.width + 4 * u + i * size * 1.15, size, color: kBlack, align: 0.5, width: box.width - 10 * u);
        }
      } else {
        c.drawRRect(rr, fill(const Color(0xFF1C1C1E)));
        c.drawRRect(rr.deflate(5 * u), stroke(kInk, 1.2 * u));
        c.save();
        c.clipRRect(rr.deflate(8 * u));
        for (var i = 1; i < 9; i++) {
          c.drawCircle(Offset(0, box.height * 0.5), i * 14 * u, stroke(white(0.55), 1.2 * u));
          c.drawCircle(Offset(0, -box.height * 0.5), i * 14 * u, stroke(white(0.55), 1.2 * u));
        }
        c.restore();
      }
      c.restore();
    }
    if (guess != null && since > 1.4) {
      final s = f.d.songs.first;
      f.film.kinetic(f, '${s.plays} plays', x: f.w / 2, y: f.h * 0.68, size: 40 * u, at: f.touch.guessAt + 1.4, center: true);
    }
  }
}

// ── Turntable ───────────────────────────────────────────────────────────────

/// A deck seen from above. The arm swings over, the needle drops, the record is your cover. Scratch it.
class TurntableScene extends FilmScene {
  @override
  String get id => 'number-one';
  @override
  String get technique => 'turntable, needle drop, scratch';
  @override
  double get length => 9;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) => 'The song your server counted the most plays for in ${d.year}: ${d.songs.first.plays}.';
  @override
  String share(WrappedData d) => 'My song of ${d.year}: ${nice(d.songs.first.title)}.';
  @override
  String speech(WrappedData d) => 'Your song of the year: ${nice(d.songs.first.title)} by ${d.songs.first.artist}, ${d.songs.first.plays} plays.';
  @override
  String? get hint => 'Scratch it';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, s = f.d.songs.first;
    final drop = ramp(f.t, 1.4, 2.6, Curves.easeInOutCubic);
    final mid = Offset(f.w * 0.46, f.h * 0.35);
    final r = 138 * u * ramp(f.t, 0.1, 1.0, Curves.easeOutBack);
    // up to speed before the needle lands
    final run = math.max(0.0, f.t - 0.6);
    final angle = run < 1 ? run * run * 1.2 : 1.2 + (run - 1) * 3.49;
    final spin = angle + f.touch.spin * 2;
    c.drawCircle(mid, r + 7 * u, fill(const Color(0xFF111111)));
    c.drawCircle(mid, r + 7 * u, stroke(white(0.35), 1.4 * u));
    // strobe marks on the rim
    for (var i = 0; i < 60; i++) {
      final a = i / 60 * kTau + spin;
      c.drawLine(mid + Offset.fromDirection(a, r + 2 * u), mid + Offset.fromDirection(a, r + 6 * u), stroke(white(0.6), 1.2 * u));
    }
    f.film.picture(c, _cover(f, s.title, s.artist), Rect.fromCircle(center: mid, radius: r), radius: r, angle: spin, tile: true);
    for (var i = 0; i < 22; i++) {
      c.drawCircle(mid, r * (0.36 + i * 0.028), stroke(const Color(0x66000000), 1.1 * u));
    }
    // light on the grooves stays put while the record turns
    for (final a in [-0.8, 2.34]) {
      final path = Path()
        ..moveTo(mid.dx, mid.dy)
        ..arcTo(Rect.fromCircle(center: mid, radius: r), a, 0.34, false)
        ..close();
      c.drawPath(path, fill(const Color(0x1FFFFFFF)));
    }
    c.drawCircle(mid, 5 * u, fill(kBlack));
    c.drawCircle(mid, 2 * u, fill(kInk));
    // the arm
    final pivot = Offset(f.w * 0.9, f.h * 0.35 - 150 * u);
    final swing = mix(1.55, 2.02, drop) + math.sin(f.t * 3.4) * 0.006 * drop;
    final elbow = pivot + Offset.fromDirection(swing, 150 * u);
    final head = elbow + Offset.fromDirection(swing + 0.38, 42 * u);
    c.drawLine(pivot, elbow, stroke(const Color(0xFFE5E5EA), 5 * u, cap: StrokeCap.round));
    c.drawLine(elbow, head, stroke(kInk, 11 * u, cap: StrokeCap.round));
    c.drawCircle(pivot, 17 * u, fill(const Color(0xFF2C2C2E)));
    c.drawCircle(pivot, 17 * u, stroke(kInk, 2 * u));
    c.drawCircle(pivot, 6 * u, fill(kInk));
    // the groove it is reading, out loud
    final y0 = f.h * 0.625;
    final loud = ramp(f.t, 2.5, 3.0) * (1 + f.touch.punch());
    final path = Path()..moveTo(0, y0);
    for (var i = 0; i <= 90; i++) {
      final x = i / 90;
      final env = math.sin(x * math.pi);
      final v = math.sin(x * 46 - f.t * 13) * math.sin(x * 9 + f.t * 2) * 18 + math.sin(x * 110 + f.t * 21) * 4;
      path.lineTo(x * f.w, y0 + v * env * loud * u);
    }
    c.drawPath(path, stroke(white(0.9), 1.6 * u));
    final h = f.film.kinetic(f, nice(s.title), x: 24 * u, y: f.h * 0.685, size: 50 * u, at: 2.6);
    final h2 = f.film.kinetic(f, s.artist, x: 24 * u, y: f.h * 0.685 + h + 2 * u, size: 19 * u, at: 3.1, weight: FontWeight.w500, color: kDim, lines: 1);
    f.film.counter(f, s.plays, (v) => '$v plays', x: 24 * u, y: f.h * 0.685 + h + h2 + 12 * u, size: 26 * u, from: 3.3, to: 5);
  }
}

// ── Split flap ──────────────────────────────────────────────────────────────

/// A departures board clatters round to your top five. Tap to send it round again.
class FlapScene extends FilmScene {
  static const _cols = 17;
  static const _alphabet = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final List<List<String>> _rows;
  FlapScene(WrappedData d)
    : _rows = [
        for (final (i, s) in d.songs.indexed) _letters('${i + 1} ${nice(s.title)}'),
      ];

  static List<String> _letters(String s) {
    final all = [for (final r in s.toUpperCase().runes) String.fromCharCode(r)];
    return [for (var i = 0; i < _cols; i++) i < all.length ? all[i] : ' '];
  }

  @override
  String get id => 'top5';
  @override
  String get technique => 'split-flap departures board';
  @override
  double get length => 10;
  @override
  double get still => 8;
  @override
  String why(WrappedData d) => 'Your songs ranked by how many times you played them in ${d.year}.';
  @override
  String share(WrappedData d) => 'My top five songs of ${d.year}.';
  @override
  String speech(WrappedData d) => 'Your top songs: ${[for (var i = 0; i < d.songs.length; i++) '${i + 1}, ${nice(d.songs[i].title)}'].join('; ')}.';
  @override
  String? get hint => 'Tap to spin the board';
  @override
  double? tap(FilmFrame f, Offset p) => 0.9;

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    f.film.kinetic(f, 'Now boarding: your top ${_rows.length}', x: 24 * u, y: f.h * 0.12, size: 32 * u, at: 0.1);
    final cell = (f.w - 24 * u) / _cols, ch = cell * 1.62;
    final top = f.h * 0.27;
    final gap = math.min(94 * u, (f.h * 0.6) / _rows.length);
    for (var r = 0; r < _rows.length; r++) {
      final y = top + r * gap;
      for (var k = 0; k < _cols; k++) {
        // the last row lands first and number one last
        final land = 1.6 + (_rows.length - 1 - r) * 1.05 + k * 0.055;
        final left = land - f.t;
        var letter = _rows[r][k];
        var flip = 1.0;
        if (left > 0) {
          final step = (left / 0.085).floor();
          letter = _alphabet[(step * 7 + k * 5 + r * 11) % _alphabet.length];
          flip = 1 - (left / 0.085 - step);
        } else if (left > -0.12) {
          flip = -left / 0.12;
        }
        final x = 12 * u + k * cell;
        final box = RRect.fromRectAndRadius(Rect.fromLTWH(x + 0.8 * u, y, cell - 1.6 * u, ch), Radius.circular(2.5 * u));
        // once they have all landed, a ripple keeps running along number one
        final ripple = f.t - 8.0 - k * 0.04;
        if (r == 0 && ripple > 0 && ripple % 2 < 0.16) flip = (ripple % 2 / 0.16).clamp(0.1, 1).toDouble();
        final lit = r == 0 && left <= 0;
        c.drawRRect(box, fill(lit ? kInk : const Color(0xFF1C1C1E)));
        if (letter != ' ') {
          final tp = f.film.words(letter, cell * 0.98, weight: FontWeight.w700, color: lit ? kBlack : kInk);
          c.save();
          c.translate(x + cell / 2, y + ch / 2);
          c.scale(math.min(1, (cell - 2 * u) / tp.width), flip.clamp(0.08, 1).toDouble());
          tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
          c.restore();
        }
        c.drawRect(Rect.fromLTWH(x + 0.8 * u, y + ch / 2 - 0.5 * u, cell - 1.6 * u, 1 * u), fill(kBlack));
      }
      final s = f.d.songs[r];
      final shown = f.t > 1.6 + (_rows.length - 1 - r) * 1.05 + 1.0;
      if (shown) {
        f.film.line(c, s.artist, 13 * u, y + ch + 5 * u, 13 * u, weight: FontWeight.w500, color: kDim, width: f.w * 0.62);
        f.film.line(c, '${s.plays} plays', f.w - 13 * u, y + ch + 5 * u, 13 * u, weight: FontWeight.w700, align: 1);
      }
    }
  }
}

// ── Solar ───────────────────────────────────────────────────────────────────

/// Your number one is the sun. The rest are worlds around it; throw them.
class SolarScene extends FilmScene {
  @override
  String get id => 'artists';
  @override
  String get technique => 'solar system of portraits; dust for corona and orbits';
  @override
  bool get particles => true;
  @override
  double get length => 9;
  @override
  double get still => 6;
  @override
  String why(WrappedData d) => 'Artists by plays across all their songs. The nearer and bigger the world, the more you played it.';
  @override
  String share(WrappedData d) => 'My artist of ${d.year}: ${d.artists.first.name}.';
  @override
  String speech(WrappedData d) => 'Your top artists: ${[for (final a in d.artists) a.name].join(', ')}.';
  @override
  String? get hint => 'Throw the planets';

  Offset _c(FilmFrame f) => Offset(f.w / 2, f.h * 0.41);
  double _orbit(FilmFrame f, int k) => (84 + k * 16) * f.u;
  Offset _roll(double x, double y) => Offset(x * 0.961 + y * 0.276, -x * 0.276 + y * 0.961);

  (Offset, double) _world(FilmFrame f, int k) {
    final a = 1.1 + k * 2.4 + (f.t * 0.75 + f.touch.spin) / (1 + k * 0.28);
    final r = _orbit(f, k), z = math.sin(a);
    return (_c(f) + _roll(math.cos(a) * r, z * r * 0.46) * ramp(f.t, 0.4, 1.9, Curves.easeOutBack), z);
  }

  void _planet(FilmFrame f, int k) {
    final (p, z) = _world(f, k);
    final size = (64 - k * 6) * f.u * (1 + z * 0.22) * ramp(f.t, 0.6 + k * 0.1, 1.5 + k * 0.1, Curves.easeOutBack);
    final rect = Rect.fromCenter(center: p, width: size, height: size);
    f.canvas.drawOval(rect.inflate(1.5 * f.u), fill(kBlack));
    f.film.picture(f.canvas, f.assets.people[f.d.artists[k + 1].name], rect, radius: size / 2, tile: true);
    final toSun = (_c(f) - p) / (p - _c(f)).distance.clamp(1, double.infinity);
    f.canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(toSun.dx * 0.6, toSun.dy * 0.6),
          radius: 1,
          colors: const [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  void paint(FilmFrame f) {
    final u = f.u, list = f.d.artists, c = _c(f);
    final n = math.min(5, list.length - 1);
    final dust = (f.film.grains * 0.38).round();
    for (var k = n - 1; k >= 0; k--) {
      if (_world(f, k).$2 < 0) _planet(f, k);
    }
    final s = 116 * u * ramp(f.t, 0.2, 1.1, Curves.easeOutBack) * (1 + 0.02 * math.sin(f.t * 3) + 0.12 * f.touch.punch());
    f.canvas.drawCircle(c, s / 2, fill(kInk));
    f.film.picture(f.canvas, f.assets.people[list.first.name], Rect.fromCircle(center: c, radius: s / 2 - 2 * u), radius: s / 2, tile: true);
    f.film.dots(f.canvas, dust, (i, o) {
      if (i.isEven || n <= 0) {
        final a = rnd(i, 40) * kTau + f.t * 0.2;
        final lick = (f.t * (0.25 + rnd(i, 42) * 0.4) + rnd(i, 43)) % 1;
        final r = 60 * u + math.pow(rnd(i, 41), 3) * 40 * u * lick;
        o.set(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r, (2.2 - lick) * u, 1 - lick);
      } else {
        final k = (i ~/ 2) % n;
        final a = rnd(i, 44) * kTau + (f.t * 0.75 + f.touch.spin) / (1 + k * 0.28);
        final z = math.sin(a), r = _orbit(f, k);
        final p = c + _roll(math.cos(a) * r, z * r * 0.46);
        o.set(p.dx, p.dy, (0.9 + 0.5 * (z + 1) / 2) * u, 0.15 + 0.3 * (z + 1) / 2);
      }
    });
    for (var k = 0; k < n; k++) {
      final (p, z) = _world(f, k);
      if (z < 0) continue;
      _planet(f, k);
      if (z > 0.35 && f.t > 2) {
        final tp = f.film.words(f.film.fit(list[k + 1].name, 13 * u, 110 * u, 1, FontWeight.w600).$2.first, 13 * u, weight: FontWeight.w600);
        tp.paint(f.canvas, Offset((p.dx - tp.width / 2).clamp(8 * u, math.max(8 * u, f.w - tp.width - 8 * u)).toDouble(), p.dy + (40 - k * 3) * u));
      }
    }
    final y = f.h * 0.70;
    f.film.kinetic(f, 'Everything revolved around', x: f.w / 2, y: y, size: 18 * u, at: 1.0, weight: FontWeight.w600, color: kDim, center: true, lines: 1);
    final h = f.film.kinetic(f, list.first.name, x: f.w / 2, y: y + 26 * u, size: 45 * u, at: 1.3, center: true);
    f.film.kinetic(f, '${list.first.plays} plays · ${list.first.songs} songs', x: f.w / 2, y: y + 32 * u + h, size: 16 * u, at: 2.0, weight: FontWeight.w500, color: kDim, center: true, lines: 1);
  }
}

// ── Race ────────────────────────────────────────────────────────────────────

/// Bars overtake each other month by month, the whole year in seven seconds. Drag to wind it.
class RaceScene extends FilmScene {
  final List<String> _names;
  RaceScene(WrappedData d) : _names = d.story.race.keys.toList();
  @override
  String get id => 'race';
  @override
  String get technique => 'bar-chart race';
  @override
  double get length => 10;
  @override
  double get still => 9;
  @override
  int get scrubSteps => 12;
  @override
  String why(WrappedData d) => 'Plays added up from each month’s top artists. A month in which an artist was not in that list adds nothing here.';
  @override
  String share(WrappedData d) => 'My artist race of ${d.year}.';
  @override
  String speech(WrappedData d) => 'By the end of the year the order was ${_names.join(', ')}.';
  @override
  String? get hint => 'Drag through the months';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final race = f.d.story.race;
    var lastMonth = 11;
    for (var m = 0; m < 12; m++) {
      if (f.d.months[m].minutes > 0) lastMonth = m;
    }
    final at = f.touch.scrubX != null ? f.touch.scrubX! * (lastMonth + 0.0) : ramp(f.t, 0.8, 7.6, Curves.easeInOutSine) * lastMonth;
    final lo = at.floor(), hi = math.min(lastMonth, lo + 1);
    final k = at - lo;
    double value(String n, int m) => race[n]![m].toDouble();
    List<String> order(int m) => [..._names]..sort((a, b) {
      final d = value(b, m).compareTo(value(a, m));
      return d != 0 ? d : a.compareTo(b);
    });
    final a = order(lo), b = order(hi);
    final big = f.film.words(monthNames[at.round()].substring(0, 3), 150 * u, color: const Color(0xFF1C1C1E));
    big.paint(c, Offset(f.w - big.width - 14 * u, f.h * 0.72));
    f.film.kinetic(f, 'The race for your ears', x: 24 * u, y: f.h * 0.12, size: 32 * u, at: 0.1);
    final top = f.h * 0.235, rowH = math.min(66 * u, f.h * 0.54 / _names.length);
    var most = 1.0;
    for (final n in _names) {
      most = math.max(most, mix(value(n, lo), value(n, hi), k));
    }
    final full = f.w - 24 * u - 62 * u - 24 * u;
    for (final n in [..._names]..sort((x, y) => a.indexOf(y).compareTo(a.indexOf(x)))) {
      final pos = mix(a.indexOf(n).toDouble(), b.indexOf(n).toDouble(), Curves.easeInOutCubic.transform(k));
      final v = mix(value(n, lo), value(n, hi), k);
      final y = top + pos * rowH;
      final enter = ramp(f.t, 0.2, 0.9, Curves.easeOutCubic);
      final bw = math.max(4 * u, full * v / most * enter);
      final lead = pos < 0.5;
      c.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(0, y, 24 * u + bw, rowH - 12 * u), topRight: Radius.circular(8 * u), bottomRight: Radius.circular(8 * u)),
        fill(lead ? kInk : grey((96 - pos * 8).round().clamp(40, 96))),
      );
      final inside = bw > 130 * u;
      f.film.line(
        c, n, inside ? 24 * u : 24 * u + bw + 58 * u, y + (rowH - 12 * u) / 2 - 9 * u, 15 * u,
        color: inside && lead ? kBlack : kInk, width: inside ? bw - 8 * u : f.w - (24 * u + bw + 64 * u),
      );
      final pr = (rowH - 8 * u) / 2;
      final pc = Offset(24 * u + bw + pr + 4 * u + math.sin(f.t * 7 + pos * 1.3) * 2.2 * u, y + (rowH - 12 * u) / 2 - math.sin(f.t * 14 + pos * 2).abs() * 2.5 * u);
      f.film.picture(c, f.assets.people[n], Rect.fromCircle(center: pc, radius: pr), radius: pr, tile: true);
      if (inside) f.film.line(c, '${v.round()}', f.w - 8 * u, y + (rowH - 12 * u) / 2 - 8 * u, 13 * u, align: 1, color: kDim, width: math.max(20 * u, f.w - pc.dx - pr - 10 * u));
    }
  }
}

// ── Obsession ───────────────────────────────────────────────────────────────

/// One cover, then one for every time you played it that month. The camera has to keep backing away.
class ObsessionScene extends FilmScene {
  Float32List _t = Float32List(0), _r = Float32List(0);
  @override
  String get id => 'obsession';
  @override
  String get technique => 'one tile per play, endless zoom-out';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) =>
      'The song with the most plays inside a single month: ${d.story.obsession!.plays} in ${monthNames[d.story.obsession!.month - 1]}. Each tile is one play${d.story.obsession!.plays > 400 ? ' (the first 400 are drawn)' : ''}.';
  @override
  String share(WrappedData d) => 'I played ${nice(d.story.obsession!.title)} ${d.story.obsession!.plays} times in ${monthNames[d.story.obsession!.month - 1]}.';
  @override
  String speech(WrappedData d) =>
      'In ${monthNames[d.story.obsession!.month - 1]} you could not stop playing ${nice(d.story.obsession!.title)}: ${d.story.obsession!.plays} times.';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, o = f.d.story.obsession!;
    final total = math.min(400, o.plays);
    final image = _cover(f, o.title, o.artist);
    final k = ramp(f.t, 1.0, 5.0, Curves.easeInOutSine);
    final n = math.exp(math.log(math.max(1, total)) * k); // doubles at a steady beat
    final side = math.sqrt(n);
    final area = Rect.fromLTWH(0, f.h * 0.1, f.w, f.h * 0.52);
    final cell = math.min(area.width, area.height) / math.max(1, side);
    final cols = math.max(1, (area.width / cell).ceil());
    final shown = k >= 1 ? total : n.ceil().clamp(1, total);
    c.save();
    c.clipRect(area);
    final cx = area.center.dx, cy = area.center.dy;
    // laid out in rings from the middle, so a new play always joins the edge
    if (image != null) {
      if (_t.length != total * 4) {
        _t = Float32List(total * 4);
        _r = Float32List(total * 4);
      }
      final px = math.min(image.width, image.height).toDouble();
      for (var i = 0; i < total; i++) {
        final (gx, gy) = _spiral(i);
        final pop = i < shown ? 1.0 + 0.06 * math.sin(f.t * 9 - i * 0.6) : 0.0;
        final s = (cell - 2 * u) / px * pop;
        _t[i * 4] = s;
        _t[i * 4 + 1] = 0;
        _t[i * 4 + 2] = cx + gx * cell - px * s / 2;
        _t[i * 4 + 3] = cy + gy * cell - px * s / 2;
        _r[i * 4] = (image.width - px) / 2;
        _r[i * 4 + 1] = (image.height - px) / 2;
        _r[i * 4 + 2] = _r[i * 4] + px;
        _r[i * 4 + 3] = _r[i * 4 + 1] + px;
      }
      c.drawRawAtlas(image, _t, _r, null, null, null, Paint()..filterQuality = FilterQuality.low);
    } else {
      for (var i = 0; i < shown; i++) {
        final (gx, gy) = _spiral(i);
        c.drawRect(Rect.fromCenter(center: Offset(cx + gx * cell, cy + gy * cell), width: cell - 2 * u, height: cell - 2 * u), fill(grey(40 + (i * 37) % 120)));
      }
    }
    c.restore();
    assert(cols > 0);
    final y = f.h * 0.655;
    f.film.kinetic(f, 'In ${monthNames[o.month - 1]} you were obsessed', x: 24 * u, y: y, size: 18 * u, at: 0.6, weight: FontWeight.w600, color: kDim, lines: 1);
    final h = f.film.kinetic(f, nice(o.title), x: 24 * u, y: y + 26 * u, size: 38 * u, at: 0.9);
    f.film.counter(f, o.plays, (v) => '$v times', x: 24 * u, y: y + 32 * u + h, size: 56 * u, from: 1.0, to: 5.0);
  }

  /// Square spiral: 0 is the middle, then round and round it.
  static (int, int) _spiral(int i) {
    if (i == 0) return (0, 0);
    final r = ((math.sqrt(i) + 1) / 2).floor();
    final first = (2 * r - 1) * (2 * r - 1);
    final p = i - first, leg = 2 * r;
    return switch (p ~/ leg) {
      0 => (r, -r + 1 + p % leg),
      1 => (r - 1 - p % leg, r),
      2 => (-r, r - 1 - p % leg),
      _ => (-r + 1 + p % leg, -r),
    };
  }
}

// ── Cassette ────────────────────────────────────────────────────────────────

/// Side A is how the year began, side B where it has got to. The tape winds across and turns over.
class CassetteScene extends FilmScene {
  @override
  String get id => 'bookends';
  @override
  String get technique => 'cassette, reels and a side flip';
  @override
  double get length => 10;
  @override
  double get still => 8.6;
  @override
  String why(WrappedData d) => 'The first and the latest play of ${d.year} in your play log.';
  @override
  String share(WrappedData d) => 'My ${d.year} began with ${nice(d.story.ends!.first.title)}.';
  @override
  String speech(WrappedData d) => 'Your year began with ${nice(d.story.ends!.first.title)} and the latest song is ${nice(d.story.ends!.last.title)}.';
  @override
  String? get hint => 'Tap to flip the tape';
  @override
  double? tap(FilmFrame f, Offset p) => f.t < 4.6 ? 4.6 : 0.6;

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, ends = f.d.story.ends!;
    final flip = ramp(f.t, 4.6, 5.6, Curves.easeInOutCubic);
    final b = flip > 0.5;
    final play = b ? ends.last : ends.first;
    final wind = clamp01(b ? (f.t - 5.4) / 4.6 : (f.t - 0.6) / 4.2);
    c.save();
    c.translate(f.w / 2, f.h * 0.36 - math.sin(flip * math.pi) * 40 * u);
    c.rotate(-0.05 + math.sin(f.t * 1.3) * 0.012);
    c.scale(math.max(0.03, math.cos(flip * math.pi).abs()) * ramp(f.t, 0, 0.8, Curves.easeOutBack), ramp(f.t, 0, 0.8, Curves.easeOutBack));
    final box = Rect.fromCenter(center: Offset.zero, width: 310 * u, height: 196 * u);
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(14 * u)), fill(const Color(0xFF1C1C1E)));
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(14 * u)), stroke(kInk, 2 * u));
    for (final s in [const Offset(-1, -1), const Offset(1, -1), const Offset(-1, 1), const Offset(1, 1)]) {
      c.drawCircle(Offset(s.dx * 144 * u, s.dy * 87 * u), 3 * u, fill(const Color(0xFF636366)));
    }
    final label = Rect.fromLTRB(-136 * u, -84 * u, 136 * u, 50 * u);
    c.drawRRect(RRect.fromRectAndRadius(label, Radius.circular(7 * u)), fill(kInk));
    f.film.line(c, b ? 'B' : 'A', label.left + 10 * u, label.top + 5 * u, 30 * u, weight: FontWeight.w800, color: kBlack);
    f.film.line(c, nice(play.title), label.left + 42 * u, label.top + 9 * u, 21 * u, color: kBlack, width: 222 * u);
    f.film.line(c, play.artist, label.left + 42 * u, label.top + 34 * u, 13 * u, weight: FontWeight.w500, color: const Color(0xFF48484A), width: 222 * u);
    final window = RRect.fromRectAndRadius(Rect.fromLTRB(-100 * u, -22 * u, 100 * u, 38 * u), Radius.circular(30 * u));
    c.drawRRect(window, fill(kBlack));
    c.save();
    c.clipRRect(window);
    for (final left in [true, false]) {
      final hub = Offset((left ? -62 : 62) * u, 8 * u);
      final share = left ? 1 - wind : wind;
      c.drawCircle(hub, (22 + 34 * share) * u, fill(const Color(0xFF3A3A3C)));
      c.drawCircle(hub, 19 * u, fill(kInk));
      c.drawCircle(hub, 11 * u, fill(kBlack));
      final a0 = f.t * 5 / (0.6 + share) + f.touch.spin * 3;
      for (var i = 0; i < 6; i++) {
        final a = a0 + i * kTau / 6;
        c.drawLine(hub + Offset.fromDirection(a, 10 * u), hub + Offset.fromDirection(a, 5.5 * u), stroke(kInk, 3 * u));
      }
    }
    c.restore();
    final foot = Path()
      ..moveTo(-96 * u, 98 * u)
      ..lineTo(-84 * u, 62 * u)
      ..lineTo(84 * u, 62 * u)
      ..lineTo(96 * u, 98 * u);
    c.drawPath(foot, stroke(kInk, 1.6 * u));
    c.drawCircle(Offset(-54 * u, 82 * u), 6 * u, stroke(kInk, 1.6 * u));
    c.drawCircle(Offset(54 * u, 82 * u), 6 * u, stroke(kInk, 1.6 * u));
    c.restore();
    final y = f.h * 0.62;
    final local = b ? f.at(f.t - 5.2) : f;
    f.film.kinetic(local, b ? 'And most recently' : 'It all began with', x: 24 * u, y: y, size: 18 * u, at: b ? 0.1 : 0.8, weight: FontWeight.w600, color: kDim);
    final h = f.film.kinetic(local, nice(play.title), x: 24 * u, y: y + 26 * u, size: 44 * u, at: b ? 0.3 : 1.1);
    f.film.kinetic(local, '${play.artist} · ${sayDate(play.at.split(' ').first)}', x: 24 * u, y: y + 34 * u + h, size: 17 * u, at: b ? 0.6 : 1.5, weight: FontWeight.w500, color: kDim);
  }
}

// ── Film reel ───────────────────────────────────────────────────────────────

/// The people who wrote it, on a strip of film that runs and slows to a stop. Drag to run it yourself.
class ReelScene extends FilmScene {
  @override
  String get id => 'composers';
  @override
  String get technique => 'running film strip';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'Composers of the ${d.story.known} of your most played songs that are in your library, by plays.';
  @override
  String share(WrappedData d) => '${d.story.composers.first.name} scored my ${d.year}.';
  @override
  String speech(WrappedData d) => 'Written by ${[for (final x in d.story.composers.take(4)) x.name].join(', ')}.';
  @override
  String? get hint => 'Pull the film';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final list = f.d.story.composers.take(6).toList();
    final fh = 172 * u, fw = 236 * u;
    // runs, then settles with the first frame in the gate
    final travel = (1 - ramp(f.t, 0.2, 4.2, Curves.easeOutQuart)) * list.length * 3 * fh - f.touch.spin * 90 * u;
    final mid = f.h * 0.4;
    final left = f.w / 2 - fw / 2;
    final speed = math.max(0.0, 4.2 - f.t) / 4.2;
    c.save();
    c.translate(math.sin(f.t * 40) * speed * 2 * u, 0);
    c.drawRect(Rect.fromLTWH(left - 30 * u, 0, fw + 60 * u, f.h), fill(const Color(0xFF111111)));
    final hole = 21.5 * u;
    final shift = (travel % hole + hole) % hole;
    for (var y = -hole + shift; y < f.h + hole; y += hole) {
      for (final x in [left - 22 * u, left + fw + 8 * u]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 14 * u, 11 * u), Radius.circular(3 * u)), fill(const Color(0xFFD1D1D6)));
      }
    }
    final first = ((-mid - travel) / fh).floor() - 1, last = ((f.h - mid - travel) / fh).ceil() + 1;
    for (var i = first; i <= last; i++) {
      final y = mid + travel + i * fh - fh / 2;
      if (y > f.h || y + fh < 0) continue;
      final who = list[(i % list.length + list.length) % list.length];
      final rank = list.indexOf(who) + 1;
      final near = clamp01(1 - ((y + fh / 2 - mid).abs() / fh));
      final box = Rect.fromLTWH(left, y + 5 * u, fw, fh - 10 * u);
      c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(6 * u)), fill(Color.lerp(const Color(0xFF1C1C1E), kInk, near)!));
      final ink = near > 0.5 ? kBlack : kInk;
      f.film.line(c, '$rank', box.left + 14 * u, box.top + 8 * u, 40 * u, weight: FontWeight.w800, color: ink);
      final (s, rows) = f.film.fit(who.name, 29 * u, fw - 28 * u, 2, FontWeight.w800);
      for (var r = 0; r < rows.length; r++) {
        f.film.line(c, rows[r], box.left + 14 * u, box.bottom - 34 * u - (rows.length - r) * s * 1.06, s, weight: FontWeight.w800, color: ink, width: fw - 28 * u);
      }
      f.film.line(c, '${who.plays} plays · ${who.songs} ${who.songs == 1 ? 'song' : 'songs'}', box.left + 14 * u, box.bottom - 27 * u, 14 * u, weight: FontWeight.w600, color: near > 0.5 ? const Color(0xFF48484A) : kDim, width: fw - 28 * u);
    }
    c.restore();
    // the dark below the gate, for the title
    c.drawRect(Rect.fromLTWH(0, f.h * 0.735, f.w, f.h), fill(kBlack));
    f.film.kinetic(f, 'Music by', x: 24 * u, y: f.h * 0.755, size: 18 * u, at: 3.0, weight: FontWeight.w600, color: kDim);
    f.film.kinetic(f, list.first.name, x: 24 * u, y: f.h * 0.755 + 25 * u, size: 46 * u, at: 3.2);
  }
}

// ── Stamps ──────────────────────────────────────────────────────────────────

/// A passport page. Every language you listened in comes down as its own stamp.
class StampsScene extends FilmScene {
  @override
  String get id => 'languages';
  @override
  String get technique => 'passport stamps, thumped';
  @override
  double get length => 8;
  @override
  double get still => 6.6;
  @override
  String why(WrappedData d) => 'The main language of the ${d.story.known} of your most played songs your library knows, by plays.';
  @override
  String share(WrappedData d) => 'I listened in ${d.story.languages.length} languages in ${d.year}.';
  @override
  String speech(WrappedData d) => 'You listened in ${[for (final l in d.story.languages) '${l.name}, ${l.pct.round()} percent'].join('; ')}.';

  static const _spots = [Offset(0.34, 0.30), Offset(0.70, 0.42), Offset(0.30, 0.55), Offset(0.68, 0.62), Offset(0.62, 0.23), Offset(0.36, 0.69)];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final list = f.d.story.languages.take(6).toList();
    var shake = 0.0;
    for (var i = 0; i < list.length; i++) {
      final since = f.t - (1.0 + i * 0.75);
      if (since > 0 && since < 0.25) shake = (1 - since / 0.25) * math.sin(since * 90) * 5 * u;
    }
    c.save();
    c.translate(shake, shake * 0.6);
    // the page: guilloche, the way a passport is printed
    for (var k = 0; k < 13; k++) {
      final path = Path();
      for (var i = 0; i <= 60; i++) {
        final x = i / 60 * f.w;
        final y = f.h * (0.14 + k * 0.047) + math.sin(i * 0.42 + k * 0.8 + f.t * 0.25) * 11 * u;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      c.drawPath(path, stroke(const Color(0xFF232325), 1 * u));
    }
    for (var i = 0; i < list.length; i++) {
      final at = 1.0 + i * 0.75;
      if (f.t < at - 0.2) continue;
      final k = ramp(f.t, at - 0.2, at, Curves.easeInQuad);
      final big = list[i].pct / math.max(1, list.first.pct);
      final r = (46 + 34 * math.sqrt(big)) * u;
      c.save();
      c.translate(f.w * _spots[i].dx, f.h * _spots[i].dy);
      c.rotate((rnd(i, 7) - 0.5) * 0.7 + (1 - k) * 0.5 + f.touch.tiltX * 0.2);
      c.scale(mix(3.2, 1, k) * (1 + 0.06 * math.sin(math.pi * clamp01((f.t - at) / 0.3))));
      _stamp(f, i, list[i], r, white(k * (i.isEven ? 1 : 0.8)));
      c.restore();
    }
    c.restore();
    final n = list.length;
    f.film.kinetic(f, '${list.first.name} ran through it all', x: 24 * u, y: f.h * 0.775, size: 38 * u, at: 1.4 + n * 0.6);
  }

  void _stamp(FilmFrame f, int i, WrappedGenre l, double r, Color ink) {
    final c = f.canvas, u = f.u;
    final pen = stroke(ink, 3 * u), thin = stroke(ink, 1.3 * u);
    final box = Rect.fromCenter(center: Offset.zero, width: r * 2.3, height: r * 1.3);
    switch (i % 4) {
      case 0:
        c.drawCircle(Offset.zero, r, pen);
        c.drawCircle(Offset.zero, r - 6 * u, thin);
        for (var k = 0; k < 36; k++) {
          final a = k / 36 * kTau;
          c.drawLine(Offset.fromDirection(a, r - 6 * u), Offset.fromDirection(a, r - 12 * u), thin);
        }
      case 1:
        c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(8 * u)), pen);
        c.drawRRect(RRect.fromRectAndRadius(box.deflate(6 * u), Radius.circular(4 * u)), thin);
      case 2:
        c.drawOval(box.inflate(6 * u), pen);
        c.drawOval(box, thin);
      default:
        final p = Path();
        for (var k = 0; k < 8; k++) {
          final o = Offset.fromDirection(k * kTau / 8 + kTau / 16, r);
          k == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
        }
        c.drawPath(p..close(), pen);
    }
    f.film.line(c, l.name.toUpperCase(), 0, -15 * u, r * 0.38, weight: FontWeight.w800, color: ink, align: 0.5, width: r * 1.62);
    f.film.line(c, l.pct < 1 ? 'under 1%' : '${l.pct.round()}%', 0, r * 0.3, 15 * u, weight: FontWeight.w700, color: ink, align: 0.5);
  }
}
