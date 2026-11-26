import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// The opening run: how much, your songs, your people.

int _rgb(Color c) => c.toARGB32() & 0xFFFFFF;

// ── Ignite ──────────────────────────────────────────────────────────────────

/// Black. One point of light swells, bursts, and the sparks find the year. Sparks are particles because they are sparks.
class IgniteScene extends FilmScene {
  @override
  String get id => 'intro';
  @override
  String get technique => 'spark burst that settles into the year';
  @override
  bool get particles => true;
  @override
  double get length => 7;
  @override
  String why(WrappedData d) => 'Your year, from your own server’s play log. Drag to stir the sparks.';
  @override
  String share(WrappedData d) => 'My ${d.year} in music.';
  @override
  String speech(WrappedData d) => 'Your ${d.year} in music. Wrapped.';
  @override
  String? get hint => 'Drag to stir it';

  @override
  void paint(FilmFrame f) {
    final c = Offset(f.w / 2, f.h * 0.42), u = f.u, t = f.t;
    f.sky(const Color(0xFF12052B), const Color(0xFF000000));
    final bloom = ramp(t, 0.6, 2.4, Curves.easeOutCubic);
    f.glow(c, f.w * (0.3 + 0.6 * bloom), Tone.magenta.withValues(alpha: 0.35 * bloom));
    f.glow(c + Offset(0, f.h * 0.15), f.w * 0.9 * bloom, Tone.indigo.withValues(alpha: 0.25 * bloom));
    final b = t - 0.9;
    if (b > 0 && b < 1.2) {
      final k = b / 1.2;
      f.canvas.drawCircle(c, Curves.easeOutCubic.transform(k) * f.h * 0.7, stroke(Color.lerp(Tone.gold, Tone.magenta, k)!.withValues(alpha: (1 - k) * 0.8), (1 - k) * 22 * u));
      if (b < 0.16) f.canvas.drawRect(Offset.zero & f.size, fill(white((1 - b / 0.16) * 0.8)));
    }
    final pts = f.assets.year;
    final n = f.grains(1300);
    final finger = f.touch.finger;
    f.film.dots(f.canvas, n, (i, o) {
      final q = (i * 1300 ~/ n) % 1300;
      if (t < 0.9) {
        final k = t / 0.9;
        final a = rnd(q, 1) * kTau + t * 9;
        final r = (1 - k) * (1 - k) * (30 + 120 * rnd(q, 2)) * u + 3 * u;
        o.set(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r, (0.6 + k * 1.6) * u, k * 0.9, _rgb(Tone.gold));
        return;
      }
      final dir = rnd(q, 3) * kTau;
      final far = (60 + 330 * rnd(q, 4)) * u * (1 - math.exp(-b * 2.6));
      var x = c.dx + math.cos(dir + b * 0.35) * far, y = c.dy + math.sin(dir + b * 0.35) * far * 1.25;
      var hue = Color.lerp(Tone.gold, Tone.coral, rnd(q, 9))!;
      if (pts.length >= 2600) {
        final k = ramp(t, 1.7 + rnd(q, 5) * 0.8, 2.9 + rnd(q, 5) * 0.8, Curves.easeInOutQuart);
        final w = f.w * 0.84, h = w * 0.46;
        final px = pts[q * 2], py = pts[q * 2 + 1];
        final gx = c.dx + (px - 0.5) * w, gy = c.dy + (py - 0.5) * h + math.sin(t * 1.4 + px * 5) * 3 * u;
        final swirl = math.sin(math.pi * k) * 40 * u;
        x = mix(x, gx, k) + math.cos(q + t * 3) * swirl;
        y = mix(y, gy, k) + math.sin(q + t * 3) * swirl;
        // the year runs from gold to magenta, left to right
        hue = Color.lerp(hue, Color.lerp(Tone.gold, Tone.magenta, px)!, k)!;
      }
      if (finger != null) {
        final dx = x - finger.dx, dy = y - finger.dy, dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 90 * u && dist > 0.5) {
          final push = (1 - dist / (90 * u)) * 46 * u;
          x += dx / dist * push - dy / dist * push * 0.5;
          y += dy / dist * push + dx / dist * push * 0.5;
        }
      }
      o.set(x, y, (1.4 + rnd(q, 6) * 1.1) * u, 0.75 + 0.25 * math.sin(t * 3 + q * 1.7), _rgb(hue));
    });
    final y = f.h * 0.44 + f.w * 0.27;
    final who = f.name == null || f.name!.isEmpty ? 'Your year in music' : '${f.name}’s year in music';
    final h = f.film.kinetic(f, who, x: f.w / 2, y: y, size: 26 * u, at: 3.4, center: true);
    f.film.kinetic(f, 'Wrapped', x: f.w / 2, y: y + h + 6 * u, size: 18 * u, at: 3.9, center: true, weight: FontWeight.w600, color: const Color(0xFFFFC2DC));
  }
}

// ── Sand ────────────────────────────────────────────────────────────────────

/// The year drains through an hourglass while the minutes race; the sand warms from gold to ember as it falls.
class SandScene extends FilmScene {
  @override
  String get id => 'minutes';
  @override
  String get technique => 'hourglass of warming sand';
  @override
  bool get particles => true;
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
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final done = ramp(f.t, 1.6, 6.6, Curves.easeInOut);
    final heat = Color.lerp(Tone.gold, Tone.ember, done)!;
    f.sky(Color.lerp(const Color(0xFF2A1604), const Color(0xFF2E0B04), done)!, const Color(0xFF000000));
    final mid = Offset(f.w / 2, f.h * 0.35);
    f.glow(mid + Offset(0, 40 * u), 190 * u, heat.withValues(alpha: 0.22));
    final shake = f.touch.punch();
    final ang = math.pi * ramp(f.t, 0.3, 1.5, Curves.easeInOutBack) - math.pi + math.sin(f.t * 1.1) * 0.03 + math.sin(f.touch.kick * 30) * 0.12 * shake;
    c.save();
    c.translate(mid.dx, mid.dy);
    c.rotate(ang);
    final gh = 132 * u, gw = 90 * u;
    Path bulb(double sign) => Path()
      ..moveTo(-gw, sign * gh)
      ..quadraticBezierTo(-gw * 0.95, sign * gh * 0.45, -5 * u, 0)
      ..lineTo(5 * u, 0)
      ..quadraticBezierTo(gw * 0.95, sign * gh * 0.45, gw, sign * gh)
      ..close();
    // the glass: a faint body, a bright rim, and a highlight down one side
    for (final s in [-1.0, 1.0]) {
      c.drawPath(bulb(s), fill(white(0.05)));
      c.drawPath(bulb(s), stroke(white(0.55), 1.8 * u));
    }
    c.drawLine(Offset(-gw * 0.72, -gh * 0.85), Offset(-gw * 0.32, -gh * 0.2), stroke(white(0.35), 5 * u, cap: StrokeCap.round));
    c.drawLine(Offset(-gw * 0.72, gh * 0.85), Offset(-gw * 0.32, gh * 0.2), stroke(white(0.2), 5 * u, cap: StrokeCap.round));
    // the frame, wood-dark with brass caps
    for (final y in [-gh - 6 * u, gh + 6 * u]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y), width: gw * 2.4, height: 14 * u), Radius.circular(6 * u)), fill(const Color(0xFF5A3214)));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y), width: gw * 2.4, height: 14 * u), Radius.circular(6 * u)), stroke(Tone.gold, 1.4 * u));
    }
    for (final x in [-gw * 1.14, gw * 1.14]) {
      c.drawLine(Offset(x, -gh - 6 * u), Offset(x, gh + 6 * u), stroke(const Color(0xFF5A3214), 6 * u, cap: StrokeCap.round));
    }
    final hh = 122 * u, hw = 80 * u;
    final n = f.grains(1500);
    f.film.dots(c, n, (i, o) {
      final rank = i / n;
      double x, y;
      var tone = Color.lerp(Tone.gold, const Color(0xFFFFE08A), rnd(i, 7))!;
      if (rank > done + 0.04) {
        final left = math.max(0.02, 1 - done);
        final q = clamp01((rank - done - 0.04) / math.max(0.01, left - 0.04));
        y = -hh * math.sqrt(left) * math.sqrt(q) - 2 * u;
        x = (rnd(i, 1) * 2 - 1) * hw * (-y / hh);
      } else if (rank > done) {
        final k = 1 - (rank - done) / 0.04;
        y = k * k * hh * (1 - 0.62 * done);
        x = math.sin((rnd(i, 2) + f.t) * kTau) * 1.3 * u;
        tone = const Color(0xFFFFF1C4);
      } else {
        final pile = hh * (1 - math.sqrt(math.max(0, 1 - done)));
        // the pile is a cone: tallest in the middle
        final across = rnd(i, 1) * 2 - 1;
        y = hh - pile * (1 - math.sqrt(rnd(i, 3))) * (1 - across.abs() * 0.55);
        x = across * hw * (y / hh);
        tone = Color.lerp(Tone.gold, Tone.ember, clamp01(0.3 + rnd(i, 8) * 0.7 * (1 - rank / math.max(0.01, done)) + done * 0.4))!;
      }
      if (shake > 0) {
        x += (rnd(i, 8) - 0.5) * 34 * u * shake;
        y += (rnd(i, 9) - 0.5) * 34 * u * shake;
      }
      o.set(x, y, (1.5 + rnd(i, 4) * 1.4) * u, 0.75 + 0.25 * rnd(i, 5), _rgb(tone));
    });
    c.restore();
    final x = 24 * u, y = f.h * 0.62;
    f.film.kinetic(f, 'You listened for', x: x, y: y, size: 20 * u, at: 1.2, weight: FontWeight.w600, color: const Color(0xFFFFD79A));
    f.film.counter(f, f.d.totalMinutes, grouped, x: x, y: y + 28 * u, size: 86 * u, from: 1.4, to: 5.4);
    f.film.kinetic(f, 'minutes', x: x, y: y + 124 * u, size: 30 * u, at: 2.2, color: heat);
    final days = f.d.totalMinutes / 1440;
    if (days >= 1) {
      f.film.kinetic(f, '${days.toStringAsFixed(days >= 10 ? 0 : 1)} whole days, back to back', x: x, y: y + 164 * u, size: 17 * u, at: 4.9, weight: FontWeight.w500, color: const Color(0xFFFFD79A));
    }
  }
}

// ── Scratch ─────────────────────────────────────────────────────────────────

/// Three scratch tickets, one for each of your top three. Scratch the one you think is your number one.
class ScratchScene extends FilmScene {
  static const _inks = [Tone.teal, Tone.coral, Tone.gold];
  static const _need = 150.0; // how far you scratch (in 360-wide units) before it counts

  @override
  String get id => 'guess';
  @override
  String get technique => 'scratch-off tickets';
  @override
  double get length => 12;
  @override
  double get still => 11;
  @override
  double end(FilmTouch t) => t.guess == null ? length : t.guessAt + 3.6;
  @override
  String why(WrappedData d) => 'Your three most played songs. Under the foil is where each one finished; scratch the one you think came first.';
  @override
  String share(WrappedData d) => 'My top three of ${d.year}. Which one is number one?';
  @override
  String speech(WrappedData d) => 'Scratch to guess your number one: ${[for (final i in order(d)) nice(d.songs[i].title)].join(', ')}.';
  @override
  String? get hint => 'Scratch your guess';

  /// The tickets top to bottom, as ranks (0 is number one): never simply in order.
  static List<int> order(WrappedData d) => [for (var i = 0; i < 3; i++) (i + 1 + d.year % 2) % 3];

  Rect ticket(FilmFrame f, int k) {
    final u = f.u;
    final enter = ramp(f.t, 0.15 + k * 0.18, 0.95 + k * 0.18, Curves.easeOutBack);
    return Rect.fromLTWH(20 * u + (1 - enter) * f.w * (k.isEven ? 1 : -1), f.h * 0.2 + k * f.h * 0.205, f.w - 40 * u, f.h * 0.18);
  }

  Rect foil(FilmFrame f, int k) {
    final r = ticket(f, k);
    return Rect.fromLTRB(r.left + r.width * 0.56, r.top + 14 * f.u, r.right - 14 * f.u, r.bottom - 14 * f.u);
  }

  /// How far the finger has scratched inside ticket [k]'s foil.
  double scratched(FilmFrame f, int k) {
    final box = foil(f, k);
    var run = 0.0;
    final trail = f.touch.trail;
    for (var i = 1; i < trail.length; i++) {
      final a = trail[i - 1], b = trail[i];
      if (a == null || b == null || !box.contains(b)) continue;
      run += (b - a).distance;
    }
    return run / f.u;
  }

  @override
  double? tap(FilmFrame f, Offset p) {
    // a tap is a small scratch
    f.touch.trail
      ..add(null)
      ..add(p)
      ..add(p + Offset(9 * f.u, 0));
    return null;
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, ranks = order(f.d);
    f.sky(const Color(0xFF0B1A3D), const Color(0xFF02040C));
    f.glow(Offset(f.w * 0.8, f.h * 0.1), f.w * 0.8, Tone.azure.withValues(alpha: 0.18));
    // the pick is made inside paint so a scratch is judged on exactly what is drawn
    if (f.touch.guess == null) {
      for (var k = 0; k < 3; k++) {
        if (scratched(f, k) >= _need) {
          f.touch
            ..guess = ranks[k]
            ..guessAt = f.t;
          break;
        }
      }
    }
    final guess = f.touch.guess;
    final since = guess == null ? -1.0 : f.t - f.touch.guessAt;
    final auto = ramp(f.t, 8.5, 9.6);
    String say;
    if (guess == null) {
      say = f.t < 8.5 ? 'Scratch the one you think was your number one' : 'Here’s how they finished';
    } else {
      say = guess == 0 ? 'You know yourself.' : 'So close. Look again.';
    }
    f.film.kinetic(f, say, x: 24 * u, y: f.h * 0.07, size: 28 * u, at: guess == null ? (f.t < 8.5 ? 0.3 : 8.5) : f.touch.guessAt + 0.3);
    for (var k = 0; k < 3; k++) {
      final rank = ranks[k], s = f.d.songs[rank];
      final r = ticket(f, k), box = foil(f, k);
      final ink = _inks[k];
      final mine = guess != null && ranks.indexOf(guess) == k;
      final peel = guess == null ? auto : ramp(since, mine ? 0.0 : 0.6 + k * 0.15, mine ? 0.5 : 1.2 + k * 0.15);
      final win = rank == 0 && (guess != null || auto > 0.5);
      c.save();
      if (win) {
        final pop = 1 + 0.05 * math.sin(math.pi * clamp01((peel - 0.6) / 0.4));
        c.translate(r.center.dx, r.center.dy);
        c.scale(pop);
        c.translate(-r.center.dx, -r.center.dy);
      }
      // the ticket: coloured stock, perforated edge, the song printed on it
      final rr = RRect.fromRectAndRadius(r, Radius.circular(14 * u));
      c.drawRRect(rr, fill(ink));
      c.drawRRect(rr, stroke(win ? Tone.cream : const Color(0x33000000), win ? 4 * u : 1 * u));
      for (var y = r.top + 10 * u; y < r.bottom - 6 * u; y += 12 * u) {
        c.drawCircle(Offset(r.left + r.width * 0.53, y), 2.2 * u, fill(const Color(0x40000000)));
      }
      f.film.line(c, 'TICKET ${k + 1}', r.left + 16 * u, r.top + 12 * u, 11 * u, weight: FontWeight.w800, color: const Color(0xB3000000));
      final (size, rows) = f.film.fit(nice(s.title), 22 * u, r.width * 0.46, 2, FontWeight.w800);
      for (var i = 0; i < rows.length; i++) {
        f.film.line(c, rows[i], r.left + 16 * u, r.top + 32 * u + i * size * 1.08, size, weight: FontWeight.w800, color: const Color(0xFF0A0A0A), width: r.width * 0.48);
      }
      f.film.line(c, s.artist, r.left + 16 * u, r.bottom - 30 * u, 13 * u, weight: FontWeight.w600, color: const Color(0xCC000000), width: r.width * 0.48);
      // what is under the foil
      final under = RRect.fromRectAndRadius(box, Radius.circular(8 * u));
      c.drawRRect(under, fill(const Color(0xFF0A0A0A)));
      f.film.line(c, 'No.', box.left + 12 * u, box.top + 8 * u, 13 * u, weight: FontWeight.w700, color: ink);
      final tp = f.film.words('${rank + 1}', 64 * u, color: rank == 0 ? Tone.cream : ink);
      tp.paint(c, Offset(box.right - tp.width - 12 * u, box.bottom - tp.height + 6 * u));
      // the foil, scratched through where your finger went, then peeled away
      if (peel < 1) {
        c.saveLayer(box.inflate(2), Paint());
        c.translate(0, -peel * box.height * 1.4);
        c.save();
        c.translate(box.center.dx, box.bottom);
        c.rotate(-peel * 0.5);
        c.translate(-box.center.dx, -box.bottom);
        c.drawRRect(
          under,
          Paint()
            ..shader = ui.Gradient.linear(box.topLeft, box.bottomRight, const [Color(0xFFE8E8EE), Color(0xFF9EA0AA), Color(0xFFF4F4F8), Color(0xFF8A8C96)], const [0, 0.35, 0.6, 1]),
        );
        for (var i = 0; i < 14; i++) {
          // four-point glints pressed into the foil
          final p = Offset(box.left + box.width * rnd(i + k * 31, 1), box.top + box.height * rnd(i + k * 31, 2));
          final s = (3 + rnd(i, 3) * 4) * u;
          c.drawPath(
            Path()
              ..moveTo(p.dx, p.dy - s)
              ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
              ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
              ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
              ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s),
            fill(const Color(0x88FFFFFF)),
          );
        }
        f.film.line(c, 'SCRATCH', box.center.dx, box.center.dy - 8 * u, 14 * u, weight: FontWeight.w800, color: const Color(0x99000000), align: 0.5);
        c.restore();
        final path = Path();
        var open = false;
        for (final p in f.touch.trail) {
          if (p == null) {
            open = false;
          } else if (!open) {
            path.moveTo(p.dx, p.dy + peel * box.height * 1.4);
            open = true;
          } else {
            path.lineTo(p.dx, p.dy + peel * box.height * 1.4);
          }
        }
        c.drawPath(path, stroke(const Color(0xFF000000), 30 * u, cap: StrokeCap.round)..blendMode = BlendMode.clear);
        c.restore();
      }
      if (win && peel >= 1) {
        // the winning ticket keeps catching the light
        c.save();
        c.clipRRect(rr);
        c.translate(r.left + ((f.t * 0.55) % 1.6 - 0.3) * r.width, 0);
        c.skew(-0.4, 0);
        c.drawRect(Rect.fromLTWH(0, r.top - 20 * u, 34 * u, r.height + 40 * u), fill(const Color(0x40FFFFFF)));
        c.restore();
      }
      c.restore();
    }
    if (guess != null && since > 1.2 || auto > 0.9) {
      final top = f.d.songs.first;
      f.film.kinetic(f, '${nice(top.title)}, ${top.plays} plays', x: 24 * u, y: f.h * 0.84, size: 24 * u, at: guess != null ? f.touch.guessAt + 1.2 : 9.4, color: Tone.cream);
    }
  }
}

// ── Turntable ───────────────────────────────────────────────────────────────

/// A deck seen from above: the arm swings over, the needle drops, the cover is the record's label and the grooves pulse
/// to the song's own tempo. Scratch it.
class TurntableScene extends FilmScene {
  @override
  String get id => 'number-one';
  @override
  String get technique => 'turntable, needle drop, grooves on the beat';
  @override
  double get length => 9;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) =>
      'The song your server counted the most plays for in ${d.year}: ${d.songs.first.plays}.${d.story.bpm == null ? '' : ' The grooves pulse at its tempo, ${d.story.bpm!.round()} beats a minute.'}';
  @override
  String share(WrappedData d) => 'My song of ${d.year}: ${nice(d.songs.first.title)}.';
  @override
  String speech(WrappedData d) => 'Your song of the year: ${nice(d.songs.first.title)} by ${d.songs.first.artist}, ${d.songs.first.plays} plays.';
  @override
  String? get hint => 'Scratch the record';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, s = f.d.songs.first;
    final tone = f.tone(s.coverKey, Tone.violet);
    f.sky(tone.deep, const Color(0xFF000000));
    final mid = Offset(f.w * 0.46, f.h * 0.35);
    f.glow(mid, 220 * u, tone.vivid.withValues(alpha: 0.3));
    final drop = ramp(f.t, 1.4, 2.6, Curves.easeInOutCubic);
    final r = 138 * u * ramp(f.t, 0.1, 1.0, Curves.easeOutBack);
    final run = math.max(0.0, f.t - 0.6);
    final spin = (run < 1 ? run * run * 1.2 : 1.2 + (run - 1) * 3.49) + f.touch.spin * 2;
    // the beat, from the song's own tempo when known
    final bpm = f.d.story.bpm ?? 100;
    final playing = ramp(f.t, 2.5, 3.0);
    final beat = f.t * bpm / 60;
    final pulse = math.pow(1 - beat % 1, 4).toDouble() * playing;
    // platter
    c.drawCircle(mid, r + 12 * u, fill(const Color(0xFF1A1A1E)));
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * kTau + spin;
      c.drawCircle(mid + Offset.fromDirection(a, r + 7 * u), 1.4 * u, fill(i.isEven ? white(0.7) : white(0.25)));
    }
    // the record: black, its grooves lit outward by the beat
    c.drawCircle(mid, r, fill(const Color(0xFF0B0B0C)));
    for (var i = 0; i < 26; i++) {
      final q = i / 26;
      final wave = math.pow(math.max(0, 1 - ((q - (beat % 1)) * 3).abs()), 2).toDouble() * playing;
      c.drawCircle(mid, r * (0.46 + q * 0.52), stroke(Color.lerp(const Color(0xFF26262A), tone.vivid, wave * 0.9)!, (1 + wave * 1.6) * u));
    }
    for (final a in [-0.8, 2.34]) {
      final path = Path()
        ..moveTo(mid.dx, mid.dy)
        ..arcTo(Rect.fromCircle(center: mid, radius: r), a, 0.34, false)
        ..close();
      c.drawPath(path, fill(const Color(0x18FFFFFF)));
    }
    // the label is the cover
    final label = r * 0.42 * (1 + 0.04 * pulse);
    f.film.picture(c, f.assets.covers[s.coverKey], Rect.fromCircle(center: mid, radius: label), radius: label, angle: spin, tile: true);
    c.drawCircle(mid, label, stroke(tone.vivid, 2 * u));
    c.drawCircle(mid, 5 * u, fill(const Color(0xFF000000)));
    c.drawCircle(mid, 2 * u, fill(kInk));
    // the arm
    final pivot = Offset(f.w * 0.9, f.h * 0.35 - 150 * u);
    final swing = mix(1.55, 2.02, drop) + math.sin(f.t * 3.4) * 0.006 * drop + pulse * 0.004;
    final elbow = pivot + Offset.fromDirection(swing, 150 * u);
    final head = elbow + Offset.fromDirection(swing + 0.38, 42 * u);
    c.drawLine(pivot, elbow, stroke(const Color(0xFFD8D8DE), 5 * u, cap: StrokeCap.round));
    c.drawLine(elbow, head, stroke(tone.light, 11 * u, cap: StrokeCap.round));
    c.drawCircle(pivot, 17 * u, fill(const Color(0xFF2C2C2E)));
    c.drawCircle(pivot, 17 * u, stroke(tone.light, 2 * u));
    // what the needle reads
    final y0 = f.h * 0.625;
    final loud = playing * (0.5 + 0.8 * pulse) * (1 + f.touch.punch());
    final path = Path()..moveTo(0, y0);
    for (var i = 0; i <= 90; i++) {
      final x = i / 90;
      final v = math.sin(x * 46 - f.t * 13) * math.sin(x * 9 + f.t * 2) * 18 + math.sin(x * 110 + f.t * 21) * 4;
      path.lineTo(x * f.w, y0 + v * math.sin(x * math.pi) * loud * u);
    }
    c.drawPath(path, stroke(tone.vivid, 2 * u));
    final h = f.film.kinetic(f, nice(s.title), x: 24 * u, y: f.h * 0.685, size: 50 * u, at: 2.6);
    final h2 = f.film.kinetic(f, s.artist, x: 24 * u, y: f.h * 0.685 + h + 2 * u, size: 19 * u, at: 3.1, weight: FontWeight.w500, color: tone.light, lines: 1);
    f.film.counter(f, s.plays, (v) => '$v plays', x: 24 * u, y: f.h * 0.685 + h + h2 + 12 * u, size: 26 * u, from: 3.3, to: 5, color: tone.light);
  }
}

// ── Split flap ──────────────────────────────────────────────────────────────

/// An airport departures board clatters round to your top five. Tap to send it round again.
class FlapScene extends FilmScene {
  static const _alphabet = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final List<List<String>> _rows;
  final int _cols;
  FlapScene(WrappedData d) : _cols = _width(d), _rows = [];

  static int _width(WrappedData d) {
    var most = 0;
    for (final (i, s) in d.songs.indexed) {
      most = math.max(most, '${i + 1} ${nice(s.title)}'.runes.length);
    }
    return most.clamp(14, 20);
  }

  List<List<String>> _letters(WrappedData d) {
    if (_rows.isEmpty) {
      for (final (i, s) in d.songs.indexed) {
        final all = [for (final r in '${i + 1} ${nice(s.title)}'.toUpperCase().runes) String.fromCharCode(r)];
        if (all.length > _cols) all[_cols - 1] = '…';
        _rows.add([for (var k = 0; k < _cols; k++) k < all.length ? all[k] : ' ']);
      }
    }
    return _rows;
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
    final c = f.canvas, u = f.u, rows = _letters(f.d);
    f.sky(const Color(0xFF1B1A16), const Color(0xFF050505));
    f.glow(Offset(f.w / 2, f.h * 0.3), f.w, Tone.gold.withValues(alpha: 0.09));
    f.film.kinetic(f, 'Now departing: your top ${rows.length}', x: 24 * u, y: f.h * 0.11, size: 31 * u, at: 0.1, color: const Color(0xFFFFD27A));
    final cell = (f.w - 24 * u) / _cols, ch = cell * 1.62;
    final top = f.h * 0.26;
    final gap = math.min(94 * u, (f.h * 0.6) / rows.length);
    for (var r = 0; r < rows.length; r++) {
      final y = top + r * gap;
      for (var k = 0; k < _cols; k++) {
        final land = 1.6 + (rows.length - 1 - r) * 1.05 + k * 0.05;
        final left = land - f.t;
        var letter = rows[r][k];
        var flip = 1.0;
        if (left > 0) {
          final step = (left / 0.085).floor();
          letter = _alphabet[(step * 7 + k * 5 + r * 11) % _alphabet.length];
          flip = 1 - (left / 0.085 - step);
        } else if (left > -0.12) {
          flip = -left / 0.12;
        }
        final ripple = f.t - 8.0 - k * 0.04;
        if (r == 0 && ripple > 0 && ripple % 2 < 0.16) flip = (ripple % 2 / 0.16).clamp(0.1, 1).toDouble();
        final x = 12 * u + k * cell;
        final box = RRect.fromRectAndRadius(Rect.fromLTWH(x + 0.8 * u, y, cell - 1.6 * u, ch), Radius.circular(2.5 * u));
        final lit = r == 0 && left <= 0;
        c.drawRRect(box, fill(lit ? Tone.gold : const Color(0xFF232220)));
        if (letter != ' ') {
          final tp = f.film.words(letter, cell * 0.98, weight: FontWeight.w700, color: lit ? const Color(0xFF1A1206) : const Color(0xFFFFD27A));
          c.save();
          c.translate(x + cell / 2, y + ch / 2);
          c.scale(math.min(1, (cell - 2 * u) / tp.width), flip.clamp(0.08, 1).toDouble());
          tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
          c.restore();
        }
        c.drawRect(Rect.fromLTWH(x + 0.8 * u, y + ch / 2 - 0.5 * u, cell - 1.6 * u, 1 * u), fill(const Color(0xFF000000)));
      }
      final s = f.d.songs[r];
      if (f.t > 1.6 + (rows.length - 1 - r) * 1.05 + 1.0) {
        f.film.line(c, s.artist, 13 * u, y + ch + 5 * u, 13 * u, weight: FontWeight.w500, color: const Color(0xFFD9C9A6), width: f.w * 0.62);
        f.film.line(c, '${s.plays} plays', f.w - 13 * u, y + ch + 5 * u, 13 * u, weight: FontWeight.w700, align: 1, color: const Color(0xFFFFD27A));
      }
    }
  }
}

// ── Pinboard ────────────────────────────────────────────────────────────────

/// A corkboard: your artists pinned as photos, red string from your number one to each of the others. Drag to set them swinging.
class PinboardScene extends FilmScene {
  @override
  String get id => 'artists';
  @override
  String get technique => 'corkboard, photos and red string';
  @override
  double get length => 9;
  @override
  double get still => 6.5;
  @override
  String why(WrappedData d) => 'Artists by plays across all their songs. The string runs from your number one to the rest.';
  @override
  String share(WrappedData d) => 'My artist of ${d.year}: ${d.artists.first.name}.';
  @override
  String speech(WrappedData d) => 'Your top artists: ${[for (final a in d.artists) a.name].join(', ')}.';
  @override
  String? get hint => 'Drag to swing them';

  static const _spots = [Offset(0.5, 0.2), Offset(0.2, 0.43), Offset(0.79, 0.4), Offset(0.27, 0.66), Offset(0.74, 0.65), Offset(0.5, 0.52)];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, list = f.d.artists.take(6).toList();
    final board = Rect.fromLTWH(0, 0, f.w, f.h * 0.7);
    // cork: warm, with a fixed scatter of grain
    c.drawRect(board, Paint()..shader = ui.Gradient.radial(board.center, board.longestSide * 0.7, const [Color(0xFFC08A55), Color(0xFF7E4E26)]));
    final grain = Float32List(900);
    for (var i = 0; i < 450; i++) {
      grain[i * 2] = rnd(i, 1) * f.w;
      grain[i * 2 + 1] = rnd(i, 2) * board.height;
    }
    c.drawRawPoints(ui.PointMode.points, grain, stroke(const Color(0x40311806), 2.2 * u, cap: StrokeCap.round));
    c.drawRect(Rect.fromLTWH(0, board.bottom - 10 * u, f.w, 10 * u), fill(const Color(0xFF4A2A10)));
    final swing = f.touch.tiltX * 0.5 + f.touch.punch() * 0.3;
    Offset pin(int i) => Offset(_spots[i].dx * f.w, _spots[i].dy * f.h);
    // the string, drawn on from number one
    for (var i = 1; i < list.length; i++) {
      final k = ramp(f.t, 2.0 + i * 0.25, 2.8 + i * 0.25);
      if (k <= 0) continue;
      final a = pin(0), b = pin(i);
      final sag = Offset((a.dx + b.dx) / 2, math.max(a.dy, b.dy) + 30 * u);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(sag.dx, sag.dy, b.dx, b.dy);
      for (final m in path.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * k), stroke(const Color(0xFFE5383B), 2.4 * u, cap: StrokeCap.round));
      }
    }
    for (var i = list.length - 1; i >= 0; i--) {
      final drop = ramp(f.t, 0.2 + i * 0.22, 0.9 + i * 0.22, Curves.easeOutBack);
      if (drop <= 0) continue;
      final p = pin(i);
      final size = (i == 0 ? 130 : 92 - i * 5) * u;
      final angle = (rnd(i, 4) - 0.5) * 0.2 + math.sin(f.t * 1.7 + i * 1.3) * 0.035 * (1 + 4 * swing.abs()) + swing * 0.2 * (i.isEven ? 1 : -1);
      c.save();
      c.translate(p.dx, p.dy - (1 - drop) * 300 * u);
      c.rotate(angle);
      // a photo hung from its pin: white border, the portrait, the name written under it
      final photo = Rect.fromLTWH(-size / 2, 6 * u, size, size * 1.18);
      c.drawRect(photo.shift(Offset(3 * u, 5 * u)), fill(const Color(0x55000000)));
      c.drawRect(photo, fill(const Color(0xFFF7F3EA)));
      f.film.picture(c, f.assets.people[list[i].name], Rect.fromLTWH(photo.left + size * 0.07, photo.top + size * 0.07, size * 0.86, size * 0.86), tile: true);
      f.film.line(c, list[i].name, 0, photo.top + size * 0.95, (i == 0 ? 15 : 12) * u, weight: FontWeight.w700, color: const Color(0xFF2B2B2B), align: 0.5, width: size * 0.9);
      c.drawCircle(Offset.zero, 6 * u, fill(i == 0 ? Tone.coral : Tone.azure));
      c.drawCircle(const Offset(-1.6, -1.6) * u, 2 * u, fill(white(0.7)));
      c.restore();
    }
    c.drawRect(Rect.fromLTWH(0, board.bottom, f.w, f.h - board.bottom), fill(const Color(0xFF140A04)));
    final y = f.h * 0.74;
    f.film.kinetic(f, 'It all led back to', x: 24 * u, y: y, size: 18 * u, at: 1.0, weight: FontWeight.w600, color: const Color(0xFFF0C9A0), lines: 1);
    final h = f.film.kinetic(f, list.first.name, x: 24 * u, y: y + 26 * u, size: 44 * u, at: 1.3);
    f.film.kinetic(f, '${list.first.plays} plays · ${list.first.songs} songs', x: 24 * u, y: y + 32 * u + h, size: 16 * u, at: 2.0, weight: FontWeight.w500, color: const Color(0xFFF0C9A0), lines: 1);
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
    final c = f.canvas, u = f.u, race = f.d.story.race;
    f.sky(const Color(0xFF0B1150), const Color(0xFF02030F));
    f.glow(Offset(0, f.h * 0.4), f.w, Tone.indigo.withValues(alpha: 0.35));
    var lastMonth = 11;
    for (var m = 0; m < 12; m++) {
      if (f.d.months[m].minutes > 0) lastMonth = m;
    }
    final at = f.touch.scrubX != null ? f.touch.scrubX! * lastMonth : ramp(f.t, 0.8, 7.6, Curves.easeInOutSine) * lastMonth;
    final lo = at.floor(), hi = math.min(lastMonth, lo + 1), k = at - lo;
    double value(String n, int m) => race[n]![m].toDouble();
    List<String> order(int m) => [..._names]..sort((a, b) {
      final d = value(b, m).compareTo(value(a, m));
      return d != 0 ? d : a.compareTo(b);
    });
    final a = order(lo), b = order(hi);
    final big = f.film.words(monthNames[at.round()].substring(0, 3), 150 * u, color: const Color(0x2E5F7BFF));
    big.paint(c, Offset(f.w - big.width - 14 * u, f.h * 0.72));
    f.film.kinetic(f, 'The race for your ears', x: 24 * u, y: f.h * 0.12, size: 32 * u, at: 0.1);
    final top = f.h * 0.235, rowH = math.min(66 * u, f.h * 0.54 / _names.length);
    var most = 1.0;
    for (final n in _names) {
      most = math.max(most, mix(value(n, lo), value(n, hi), k));
    }
    final pr = (rowH - 12 * u) / 2;
    final full = f.w - 24 * u - pr * 2 - 120 * u;
    for (final n in [..._names]..sort((x, y) => a.indexOf(y).compareTo(a.indexOf(x)))) {
      final pos = mix(a.indexOf(n).toDouble(), b.indexOf(n).toDouble(), Curves.easeInOutCubic.transform(k));
      final v = mix(value(n, lo), value(n, hi), k);
      final y = top + pos * rowH;
      final bw = math.max(4 * u, full * v / most * ramp(f.t, 0.2, 0.9, Curves.easeOutCubic));
      final lead = pos < 0.5;
      final bar = Rect.fromLTWH(0, y, 24 * u + bw, rowH - 12 * u);
      c.drawRRect(
        RRect.fromRectAndCorners(bar, topRight: Radius.circular(8 * u), bottomRight: Radius.circular(8 * u)),
        Paint()..shader = ui.Gradient.linear(bar.centerLeft, bar.centerRight, lead ? const [Tone.gold, Tone.ember] : [Color.lerp(Tone.indigo, Tone.azure, pos / 6)!, Color.lerp(Tone.violet, Tone.azure, pos / 6)!]),
      );
      final pc = Offset(bar.right + pr + 6 * u + math.sin(f.t * 7 + pos * 1.3) * 2 * u, bar.center.dy - math.sin(f.t * 14 + pos * 2).abs() * 2.5 * u);
      c.drawCircle(pc, pr + 2 * u, fill(lead ? Tone.gold : const Color(0xFFDCE3FF)));
      f.film.picture(c, f.assets.people[n], Rect.fromCircle(center: pc, radius: pr), radius: pr, tile: true);
      final nameX = pc.dx + pr + 10 * u;
      f.film.line(c, n, nameX, bar.center.dy - 17 * u, 15 * u, width: f.w - nameX - 8 * u);
      f.film.line(c, '${v.round()} plays', nameX, bar.center.dy + 2 * u, 12 * u, weight: FontWeight.w600, color: const Color(0xFFB9C4FF), width: f.w - nameX - 8 * u);
    }
  }
}

// ── Crate ───────────────────────────────────────────────────────────────────

/// A crate of records: the albums you kept coming back to, flipped forward one by one. Tap to flip.
class CrateScene extends FilmScene {
  @override
  String get id => 'albums';
  @override
  String get technique => 'record crate, sleeves flipped forward';
  @override
  double get length => 10;
  @override
  double get still => 9.2;
  @override
  String why(WrappedData d) => 'Albums of your most played songs, by their plays added together.';
  @override
  String share(WrappedData d) => 'The album I wore out in ${d.year}: ${d.story.albums.first.name}.';
  @override
  String speech(WrappedData d) => 'Your albums: ${[for (final a in d.story.albums.take(5)) a.name].join(', ')}.';
  @override
  String? get hint => 'Tap to flip';
  @override
  double? tap(FilmFrame f, Offset p) {
    final n = math.min(5, f.d.story.albums.length);
    final at = ((f.t - 1.2) / 1.5).floor() + 1;
    return at >= n ? null : 1.2 + at * 1.5 + 0.01;
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final albums = f.d.story.albums.take(5).toList().reversed.toList(); // the best is at the back, flipped to last
    final n = albums.length;
    final shown = albums[(((f.t - 1.2) / 1.5).floor().clamp(-1, n - 1) + 1).clamp(0, n - 1)];
    final tone = f.tone(shown.cover, Tone.ember);
    f.sky(Color.lerp(const Color(0xFF2B0D06), tone.deep, 0.6)!, const Color(0xFF050201));
    f.glow(Offset(f.w / 2, f.h * 0.38), 230 * u, tone.vivid.withValues(alpha: 0.25));
    final base = Offset(f.w / 2, f.h * 0.58);
    final side = 214 * u;
    for (var i = 0; i < n; i++) {
      // each sleeve stands in the crate, leans back a little, and falls forward when its turn has passed
      final flip = ramp(f.t, 1.2 + i * 1.5, 1.2 + i * 1.5 + 0.7, Curves.easeInOutCubic);
      final depth = (n - 1 - i) * 10 * u;
      final m = Matrix4.identity()
        ..setEntry(3, 2, 0.0016 / u)
        ..rotateX(-0.18 - flip * 1.25 + math.sin(f.t * 1.3 + i) * 0.035);
      c.save();
      c.translate(base.dx, base.dy - depth);
      c.transform(m.storage);
      final rect = Rect.fromLTWH(-side / 2, -side, side, side);
      c.drawRect(rect.shift(Offset(0, 6 * u)), fill(const Color(0x66000000)));
      f.film.picture(c, f.assets.covers[albums[i].cover], rect, tile: true);
      c.drawRect(rect, stroke(const Color(0x40000000), 1 * u));
      c.restore();
    }
    // the crate front
    final crate = Rect.fromLTWH(f.w / 2 - 140 * u, base.dy - 40 * u, 280 * u, 92 * u);
    c.drawRRect(RRect.fromRectAndRadius(crate, Radius.circular(6 * u)), Paint()..shader = ui.Gradient.linear(crate.topLeft, crate.bottomLeft, const [Color(0xFF9A5B2C), Color(0xFF5C3215)]));
    for (var i = 1; i < 3; i++) {
      c.drawLine(Offset(crate.left, crate.top + i * 30 * u), Offset(crate.right, crate.top + i * 30 * u), stroke(const Color(0x664A2408), 2 * u));
    }
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: crate.center, width: 70 * u, height: 18 * u), Radius.circular(9 * u)), fill(const Color(0xFF2E1608)));
    final y = f.h * 0.715;
    final idx = n - 1 - albums.indexOf(shown);
    f.film.line(c, idx == 0 ? 'The album you wore out' : 'No. ${idx + 1}', 24 * u, y, 16 * u, weight: FontWeight.w600, color: tone.light);
    f.film.line(c, shown.name, 24 * u, y + 24 * u, 36 * u, weight: FontWeight.w800, width: f.w - 48 * u);
    f.film.line(c, '${shown.artist} · ${shown.plays} plays from ${shown.songs} ${shown.songs == 1 ? 'song' : 'songs'}', 24 * u, y + 70 * u, 15 * u, weight: FontWeight.w500, color: tone.light, width: f.w - 48 * u);
  }
}
