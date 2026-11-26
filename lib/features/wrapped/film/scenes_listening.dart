import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// When, how much and in what mood.

// ── Tunnel ──────────────────────────────────────────────────────────────────

/// A tunnel of the year in outline, rushing at you; the last one lands solid.
class TunnelScene extends FilmScene {
  @override
  String get id => 'intro';
  @override
  String get technique => 'tunnel of outlined type';
  @override
  double get length => 6.5;
  @override
  String why(WrappedData d) => 'Your year, from your own server’s play log.';
  @override
  String share(WrappedData d) => 'My ${d.year} in music.';
  @override
  String speech(WrappedData d) => 'Your ${d.year} in music. Wrapped.';
  @override
  String? get hint => 'Drag to look around';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, year = '${f.d.year}';
    final mid = Offset(f.w / 2, f.h * 0.42);
    final land = ramp(f.t, 2.7, 3.3, Curves.easeInQuart);
    final run = f.t * 1.1 + 1.6 * ramp(f.t, 0.4, 3.0, Curves.easeInCubic);
    final sway = Offset(math.sin(f.t * 0.9) * 26 * u + f.touch.tiltX * 70 * u, math.cos(f.t * 0.7) * 22 * u + f.touch.tiltY * 70 * u);
    const n = 15;
    for (var i = 0; i < n; i++) {
      final z = 1 - ((i / n + run * 0.34) % 1); // 1 far .. 0 at the glass
      final scale = 0.2 / (z + 0.055);
      if (scale > 9) continue;
      // few shades, so the outlines are laid out once
      final shade = (clamp01((1 - z) * 1.25) * 5).round() / 5 * (1 - 0.82 * land);
      if (shade <= 0.02) continue;
      final tp = f.film.words(year, 100 * u, outline: 1.1, color: white((shade * 10).round() / 10));
      c.save();
      c.translate(mid.dx + sway.dx * z, mid.dy + sway.dy * z);
      c.rotate(math.sin(f.t * 0.5) * 0.12 * z);
      c.scale(scale);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
    }
    if (f.t > 2.7) {
      final hit = f.t - 3.3;
      final tp = f.film.words(year, 138 * u);
      final s = hit < 0 ? mix(0.05, 1.14, land) : 1 + 0.14 * math.exp(-hit * 7) * math.cos(hit * 22);
      c.save();
      c.translate(mid.dx, mid.dy);
      c.scale(s * math.min(1, (f.w - 36 * u) / tp.width));
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
      if (hit > 0 && hit < 0.5) {
        final k = hit / 0.5;
        c.drawRect(Rect.fromCenter(center: mid, width: f.w * 1.2 * k + 160 * u, height: (f.h * 0.9) * k + 100 * u), stroke(white((1 - k) * 0.8), 14 * u * (1 - k)));
      }
    }
    final who = f.name == null || f.name!.isEmpty ? 'Your year in music' : '${f.name}’s year in music';
    final h = f.film.kinetic(f, who, x: f.w / 2, y: f.h * 0.56, size: 27 * u, at: 3.5, center: true);
    f.film.kinetic(f, 'Wrapped', x: f.w / 2, y: f.h * 0.56 + h + 5 * u, size: 18 * u, at: 4.0, center: true, weight: FontWeight.w600, color: kDim);
  }
}

// ── Sand ────────────────────────────────────────────────────────────────────

/// The year drains through an hourglass while the minutes race. Sand is grains, so this one is particles.
class SandScene extends FilmScene {
  @override
  String get id => 'minutes';
  @override
  String get technique => 'hourglass of sand';
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
    final c = f.canvas, u = f.u, n = f.film.grains;
    final done = ramp(f.t, 1.6, 6.6, Curves.easeInOut);
    final shake = f.touch.punch();
    final ang = math.pi * ramp(f.t, 0.3, 1.5, Curves.easeInOutBack) - math.pi + math.sin(f.t * 1.1) * 0.03 + math.sin(f.touch.kick * 30) * 0.12 * shake;
    final mid = Offset(f.w / 2, f.h * 0.35);
    c.save();
    c.translate(mid.dx, mid.dy);
    c.rotate(ang);
    final gh = 132 * u, gw = 88 * u;
    final glass = Path()
      ..moveTo(-gw, -gh)
      ..quadraticBezierTo(-gw * 0.9, -gh * 0.5, -4 * u, 0)
      ..quadraticBezierTo(-gw * 0.9, gh * 0.5, -gw, gh)
      ..moveTo(gw, gh)
      ..quadraticBezierTo(gw * 0.9, gh * 0.5, 4 * u, 0)
      ..quadraticBezierTo(gw * 0.9, -gh * 0.5, gw, -gh);
    c.drawPath(glass, stroke(white(0.55), 2 * u));
    for (final y in [-gh, gh]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, y), width: gw * 2.25, height: 11 * u), Radius.circular(5 * u)), fill(kInk));
    }
    final hh = 120 * u, hw = 76 * u;
    f.film.dots(c, n, (i, o) {
      final rank = i / n;
      double x, y;
      if (rank > done + 0.045) {
        final left = math.max(0.02, 1 - done);
        final q = clamp01((rank - done - 0.045) / math.max(0.01, left - 0.045));
        y = -hh * math.sqrt(left) * math.sqrt(q) - 2 * u;
        x = (rnd(i, 1) * 2 - 1) * hw * (-y / hh);
      } else if (rank > done) {
        final k = 1 - (rank - done) / 0.045;
        y = k * k * hh * (1 - 0.6 * done);
        x = math.sin((rnd(i, 2) + f.t) * kTau) * 1.5 * u;
      } else {
        final pile = hh * (1 - math.sqrt(math.max(0, 1 - done)));
        y = hh - pile * (1 - math.sqrt(rnd(i, 3)));
        x = (rnd(i, 1) * 2 - 1) * hw * (y / hh);
      }
      if (shake > 0) {
        x += (rnd(i, 8) - 0.5) * 34 * u * shake;
        y += (rnd(i, 9) - 0.5) * 34 * u * shake;
      }
      o.set(x, y, (1.9 + rnd(i, 4) * 1.5) * u, 0.6 + 0.4 * rnd(i, 5));
    });
    c.restore();
    final x = 24 * u, y = f.h * 0.62;
    f.film.kinetic(f, 'You listened for', x: x, y: y, size: 20 * u, at: 1.2, weight: FontWeight.w600, color: kDim);
    f.film.counter(f, f.d.totalMinutes, grouped, x: x, y: y + 28 * u, size: 86 * u, from: 1.4, to: 5.4);
    f.film.kinetic(f, 'minutes', x: x, y: y + 124 * u, size: 30 * u, at: 2.2);
    final days = f.d.totalMinutes / 1440;
    if (days >= 1) {
      f.film.kinetic(f, '${days.toStringAsFixed(days >= 10 ? 0 : 1)} whole days, back to back', x: x, y: y + 164 * u, size: 17 * u, at: 4.9, weight: FontWeight.w500, color: kDim);
    }
  }
}

// ── Ribbons ─────────────────────────────────────────────────────────────────

/// Your sound as one woven ribbon, a strand for each genre as thick as its share. Pull it.
class RibbonScene extends FilmScene {
  @override
  String get id => 'genres';
  @override
  String get technique => 'woven ribbons';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'A strand for each of your biggest genres, as thick as its share of your plays.';
  @override
  String share(WrappedData d) => 'My sound of ${d.year}: ${d.genres.first.name}.';
  @override
  String speech(WrappedData d) => 'Your genres: ${[for (final g in d.genres) '${g.name} ${g.pct.round()} percent'].join(', ')}.';
  @override
  String? get hint => 'Pull the ribbon';

  static const _shades = [255, 120, 190, 70, 150];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final g = f.d.genres.take(5).toList();
    final total = math.max(1.0, g.fold<double>(0, (a, b) => a + b.pct));
    final draw = ramp(f.t, 0.2, 2.4, Curves.easeInOutCubic);
    final mid = f.h * 0.36;
    const steps = 48;
    double y(int k, double x) {
      final phase = k * kTau / g.length;
      return mid + math.sin(x * 5.2 + f.t * 0.9 + phase + f.touch.spin * 0.5) * 92 * u * (0.75 + 0.25 * math.sin(x * 2 + f.t * 0.6)) + math.sin(x * 11 - f.t * 0.7 + k) * 14 * u + f.touch.tiltY * 50 * u * math.sin(x * math.pi);
    }

    // woven: each strand is drawn in slices, the deeper slice first
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, f.w * draw, f.h));
    const slices = 8;
    for (var s = 0; s < slices; s++) {
      final xm = (s + 0.5) / slices;
      final order = [for (var k = 0; k < g.length; k++) k]
        ..sort((a, b) => math.cos(xm * 5.2 + f.t * 0.9 + a * kTau / g.length).compareTo(math.cos(xm * 5.2 + f.t * 0.9 + b * kTau / g.length)));
      for (final k in order) {
        final w = math.max(5 * u, g[k].pct / total * 150 * u);
        final path = Path();
        final a = s * steps ~/ slices, b = (s + 1) * steps ~/ slices;
        for (var i = a; i <= b; i++) {
          final x = i / steps;
          final p = Offset(x * f.w, y(k, x));
          i == a ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        c.drawPath(path, stroke(kBlack, w + 5 * u));
        c.drawPath(path, stroke(grey(_shades[k]), w, cap: StrokeCap.round));
      }
    }
    c.restore();
    f.film.kinetic(f, 'You are woven from', x: 24 * u, y: f.h * 0.625, size: 18 * u, at: 1.2, weight: FontWeight.w600, color: kDim);
    final h = f.film.kinetic(f, g.first.name, x: 24 * u, y: f.h * 0.625 + 25 * u, size: 46 * u, at: 1.5, lines: 1);
    var ty = f.h * 0.625 + 36 * u + h;
    for (var k = 0; k < g.length; k++) {
      final at = 2.0 + k * 0.16;
      if (f.t > at) {
        c.drawLine(Offset(24 * u, ty + 10 * u), Offset(24 * u + 34 * u * ramp(f.t, at, at + 0.5), ty + 10 * u), stroke(grey(_shades[k]), math.max(3 * u, g[k].pct / total * 16 * u), cap: StrokeCap.round));
      }
      f.film.kinetic(f, g[k].name, x: 72 * u, y: ty, size: 16 * u, at: at, width: f.w - 160 * u, lines: 1, weight: FontWeight.w600);
      if (f.t > at + 0.2) f.film.line(c, '${g[k].pct.round()}%', f.w - 24 * u, ty, 16 * u, align: 1, color: kDim);
      ty += 25 * u;
    }
  }
}

// ── Astrolabe ───────────────────────────────────────────────────────────────

/// Brass rings turn against each other and line up on your hour. Drag through the day.
class AstrolabeScene extends FilmScene {
  @override
  String get id => 'clock';
  @override
  String get technique => 'turning astrolabe rings';
  @override
  double get length => 8;
  @override
  int get scrubSteps => 24;
  @override
  String why(WrappedData d) => 'Plays for each hour of the day as your server recorded them, midnight at the top. Longer is busier.';
  @override
  String share(WrappedData d) => 'My music hour of ${d.year}: ${sayHour(d.peakHour)}.';
  @override
  String speech(WrappedData d) => 'Your busiest hour is ${sayHour(d.peakHour)}.';
  @override
  String? get hint => 'Drag through the day';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final mid = Offset(f.w / 2, f.h * 0.4);
    final scrub = f.touch.scrubX;
    final at = scrub != null ? scrub * 23.99 : f.d.peakHour * ramp(f.t, 0.8, 3.4, Curves.easeInOutQuart) + 0.5;
    final hour = at.floor().clamp(0, 23);
    final peak = f.d.hourly.fold<int>(1, math.max);
    final open = ramp(f.t, 0.1, 1.2, Curves.easeOutBack);
    final settle = 1 - ramp(f.t, 0.4, 3.6, Curves.easeInOutCubic);
    final outer = 158 * u * open;
    // the outer ring: hours, turning home
    c.save();
    c.translate(mid.dx, mid.dy);
    c.rotate(settle * 2.2);
    c.drawCircle(Offset.zero, outer, stroke(kInk, 1.5 * u));
    c.drawCircle(Offset.zero, outer - 18 * u, stroke(white(0.5), 1 * u));
    for (var i = 0; i < 96; i++) {
      final a = i / 96 * kTau;
      c.drawLine(Offset.fromDirection(a, outer), Offset.fromDirection(a, outer - (i % 4 == 0 ? 9 : 4) * u), stroke(white(0.8), 1 * u));
    }
    for (final (h, label) in [(0, '12 am'), (6, '6 am'), (12, '12 pm'), (18, '6 pm')]) {
      c.save();
      c.rotate(h / 24 * kTau);
      final tp = f.film.words(label, 11 * u, weight: FontWeight.w600);
      c.drawRect(Rect.fromCenter(center: Offset(0, -outer + 9 * u), width: tp.width + 8 * u, height: 15 * u), fill(kBlack));
      tp.paint(c, Offset(-tp.width / 2, -outer + 2 * u));
      c.restore();
    }
    c.restore();
    // the day itself, one closed shape
    final body = Path();
    for (var i = 0; i <= 96; i++) {
      final x = i / 4 - 0.5;
      final a0 = (x.floor() % 24 + 24) % 24, b0 = (a0 + 1) % 24;
      final k = x - x.floor();
      final v = mix(f.d.hourly[a0].toDouble(), f.d.hourly[b0].toDouble(), k * k * (3 - 2 * k)) / peak;
      final grow = ramp(f.t, 0.6 + i / 96 * 1.6, 1.4 + i / 96 * 1.6, Curves.easeOutBack);
      final p = mid + Offset.fromDirection(i / 96 * kTau - math.pi / 2, (46 + 88 * v * grow) * u);
      i == 0 ? body.moveTo(p.dx, p.dy) : body.lineTo(p.dx, p.dy);
    }
    body.close();
    c.drawPath(body, fill(const Color(0xFF2C2C2E)));
    // the hour under the rule, lit
    final from = hour / 24 * kTau - math.pi / 2;
    final wedge = Path()
      ..moveTo(mid.dx, mid.dy)
      ..arcTo(Rect.fromCircle(center: mid, radius: outer), from, kTau / 24, false)
      ..close();
    c.save();
    c.clipPath(wedge);
    c.drawPath(body, fill(kInk));
    c.restore();
    c.drawPath(body, stroke(white(0.8), 1.4 * u));
    // the eccentric rings
    for (final (r, off, speed) in [(92.0, 26.0, 1.4), (70.0, 40.0, -1.9)]) {
      final a = settle * 4 * speed + from + 0.13 + f.t * 0.06 * speed;
      c.drawCircle(mid + Offset.fromDirection(a, off * u * open), r * u * open, stroke(white(0.28), 1.2 * u));
    }
    c.drawCircle(mid, 46 * u * open, fill(kBlack));
    c.drawCircle(mid, 46 * u * open, stroke(kInk, 1.5 * u));
    // the rule
    final ra = (at / 24) * kTau - math.pi / 2;
    c.drawLine(mid + Offset.fromDirection(ra, 46 * u), mid + Offset.fromDirection(ra, outer + 8 * u), stroke(kInk, 3 * u, cap: StrokeCap.round));
    c.drawLine(mid + Offset.fromDirection(ra + math.pi, 46 * u), mid + Offset.fromDirection(ra + math.pi, outer), stroke(white(0.35), 1.4 * u));
    if (f.t > 0.8) {
      f.film.line(c, sayHour(hour), mid.dx, mid.dy - 17 * u, 24 * u, weight: FontWeight.w800, align: 0.5, width: 80 * u);
      f.film.line(c, compactCount(f.d.hourly[hour]), mid.dx, mid.dy + 12 * u, 12 * u, color: kDim, align: 0.5, width: 70 * u);
    }
    final p = f.d.peakHour;
    final line = p >= 22 || p < 5
        ? 'You come alive after dark.'
        : p < 12
        ? 'You start the day loud.'
        : p < 17
        ? 'Afternoons had a soundtrack.'
        : 'Evenings were yours.';
    f.film.kinetic(f, line, x: 24 * u, y: f.h * 0.72, size: 42 * u, at: 3.3);
  }
}

// ── Ridges ──────────────────────────────────────────────────────────────────

/// Twelve ridgelines under a setting sun, nearest is now. Drag across to climb a month.
class RidgeScene extends FilmScene {
  @override
  String get id => 'journey';
  @override
  String get technique => 'ridgelines and a sliced sunset';
  @override
  double get length => 9;
  @override
  int get scrubSteps => 12;
  @override
  String why(WrappedData d) => 'Minutes listened in each month. One ridge a month, January furthest away; taller is more.';
  @override
  String share(WrappedData d) => '${monthNames[d.busiestMonth!.month - 1]} was my month of ${d.year}.';
  @override
  String speech(WrappedData d) => '${monthNames[d.busiestMonth!.month - 1]} was your biggest month, ${listeningTime(d.busiestMonth!.minutes)}.';
  @override
  String? get hint => 'Drag across the year';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, months = f.d.months;
    final peak = months.fold<int>(1, (a, b) => math.max(a, b.minutes));
    final busiest = f.d.busiestMonth!.month - 1;
    final scrub = f.touch.scrubX;
    final sel = scrub != null ? (scrub * 12).floor().clamp(0, 11) : (f.t > 5 ? busiest : (ramp(f.t, 1.4, 4.8, Curves.easeInOutSine) * 11.99).floor());
    // the sun, going down behind the year
    final sun = Offset(f.w * 0.5, mix(f.h * 0.28, f.h * 0.36, ramp(f.t, 0, 8, Curves.linear)));
    final r = 104 * u * ramp(f.t, 0, 0.9, Curves.easeOutBack);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: sun, radius: r)));
    c.drawRect(Rect.fromCircle(center: sun, radius: r), fill(kInk));
    for (var i = 0; i < 9; i++) {
      final q = ((i / 9) + f.t * 0.05) % 1;
      c.drawRect(Rect.fromLTWH(sun.dx - r, sun.dy - r * 0.1 + q * r * 1.1, r * 2, 1.5 * u + q * 9 * u), fill(kBlack));
    }
    c.restore();
    const steps = 56;
    for (var m = 0; m < 12; m++) {
      final depth = m / 11;
      final base = f.h * 0.39 + depth * f.h * 0.30;
      final rise = ramp(f.t, 0.3 + m * 0.13, 1.4 + m * 0.13, Curves.easeOutBack);
      final high = months[m].minutes / peak * (74 + 34 * depth) * u * rise;
      final peakAt = 0.5 + (rnd(m, 3) - 0.5) * 0.7;
      final path = Path()..moveTo(0, base);
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final bell = math.exp(-math.pow((x - peakAt) * 4.6, 2)) + 0.36 * math.exp(-math.pow((x - peakAt - 0.24) * 8, 2)) + 0.28 * math.exp(-math.pow((x - peakAt + 0.27) * 9, 2));
        final crag = (math.sin(x * 47 + m * 5) + math.sin(x * 83 + m * 11)) * 0.045 * bell;
        path.lineTo(x * f.w, base - high * (bell + crag) - math.sin(x * 6 + m + f.t * 0.8) * 2.4 * u);
      }
      path
        ..lineTo(f.w, base + 60 * u)
        ..lineTo(0, base + 60 * u)
        ..close();
      final hot = m == sel;
      c.drawPath(path, fill(hot ? kInk : Color.lerp(const Color(0xFF000000), const Color(0xFF161618), depth)!));
      c.drawPath(path, stroke(hot ? kInk : white(0.35 + 0.45 * depth), (hot ? 2 : 1.2) * u));
    }
    c.drawRect(Rect.fromLTWH(0, f.h * 0.715, f.w, f.h), fill(kBlack));
    f.film.kinetic(f, '${monthNames[busiest]} was your summit', x: 24 * u, y: f.h * 0.115, size: 34 * u, at: 5.0, lines: 1);
    if (f.t > 1.2) {
      final m = months[sel];
      f.film.line(c, monthNames[sel], 24 * u, f.h * 0.75, 52 * u, weight: FontWeight.w800, width: f.w - 48 * u);
      final text = m.minutes == 0 ? 'Quiet.' : [listeningTime(m.minutes), ?m.topGenre, if (m.topSong != null) nice(m.topSong!)].join(' · ');
      final (s, rows) = f.film.fit(text, 17 * u, f.w - 48 * u, 2, FontWeight.w500);
      for (var i = 0; i < rows.length; i++) {
        f.film.line(c, rows[i], 24 * u, f.h * 0.75 + 64 * u + i * s * 1.25, s, weight: FontWeight.w500, color: kDim);
      }
    }
  }
}

// ── Weather ─────────────────────────────────────────────────────────────────

/// The forecast of your moods. The main one is the sky; the rest is the week ahead.
class WeatherScene extends FilmScene {
  @override
  String get id => 'moods';
  @override
  String get technique => 'drawn weather report';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'The server’s mood labels on your most played songs, by plays. Songs without a label are not counted.';
  @override
  String share(WrappedData d) => 'My ${d.year} forecast: mostly ${d.story.moods.first.name}.';
  @override
  String speech(WrappedData d) => 'Your moods: ${[for (final m in d.story.moods.take(4)) '${m.name} ${m.pct.round()} percent'].join(', ')}.';

  static int _sky(String mood) {
    final m = mood.toLowerCase();
    if (RegExp('sad|melanch|heart|lonely|emotional').hasMatch(m)) return 1; // rain
    if (RegExp('party|energ|hype|mass|angry|power|dance|work').hasMatch(m)) return 2; // storm
    if (RegExp('chill|calm|relax|sleep|peace|night|focus|devot|spirit').hasMatch(m)) return 3; // moon
    if (RegExp('roman|love').hasMatch(m)) return 4; // warm wind
    return 0; // sun
  }

  void _draw(FilmFrame f, int sky, Offset at, double r, double t) {
    final c = f.canvas;
    final pen = stroke(kInk, math.max(1.2, r * 0.05), cap: StrokeCap.round);
    void cloud(Offset o, double s) {
      final p = Path()
        ..addOval(Rect.fromCircle(center: o + Offset(-s * 0.55, 0), radius: s * 0.45))
        ..addOval(Rect.fromCircle(center: o + Offset(0, -s * 0.3), radius: s * 0.62))
        ..addOval(Rect.fromCircle(center: o + Offset(s * 0.6, 0), radius: s * 0.42))
        ..addRect(Rect.fromLTRB(o.dx - s * 0.55, o.dy, o.dx + s * 0.6, o.dy + s * 0.43));
      c.drawPath(p, fill(kInk));
    }

    switch (sky) {
      case 0:
        c.drawCircle(at, r * 0.46, fill(kInk));
        for (var i = 0; i < 14; i++) {
          final a = i / 14 * kTau + t * 0.3;
          final l = r * (0.78 + 0.16 * math.sin(t * 3 + i * 2.2));
          c.drawLine(at + Offset.fromDirection(a, r * 0.6), at + Offset.fromDirection(a, l), pen);
        }
      case 1:
        for (var i = 0; i < 13; i++) {
          final q = (t * 1.2 + rnd(i, 4)) % 1;
          final p = at + Offset((rnd(i, 5) - 0.5) * r * 1.5 - q * r * 0.14, r * 0.2 + q * r * 0.85);
          c.drawLine(p, p + Offset(-r * 0.04, r * 0.17), stroke(white(1 - q * 0.6), pen.strokeWidth, cap: StrokeCap.round));
        }
        cloud(at + Offset(math.sin(t * 0.8) * r * 0.06, -r * 0.15), r * 0.8);
      case 2:
        final flash = math.sin(t * 2.6) > 0.86 || math.sin(t * 4.1) > 0.95;
        cloud(at + Offset(0, -r * 0.25), r * 0.8);
        final bolt = Path()
          ..moveTo(at.dx + r * 0.12, at.dy + r * 0.12)
          ..lineTo(at.dx - r * 0.22, at.dy + r * 0.52)
          ..lineTo(at.dx + r * 0.02, at.dy + r * 0.52)
          ..lineTo(at.dx - r * 0.1, at.dy + r * 0.95)
          ..lineTo(at.dx + r * 0.3, at.dy + r * 0.4)
          ..lineTo(at.dx + r * 0.06, at.dy + r * 0.4)
          ..close();
        c.drawPath(bolt, flash ? fill(kInk) : pen);
      case 3:
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: at, radius: r * 0.68)),
          Path()..addOval(Rect.fromCircle(center: at + Offset(r * 0.34, -r * 0.16), radius: r * 0.58)),
        );
        c.drawPath(moon, fill(kInk));
        for (var i = 0; i < 3; i++) {
          final s = at + Offset((0.45 + 0.22 * i) * r * (i.isEven ? 1 : 0.8), (-0.35 + i * 0.36) * r);
          final l = r * 0.1 * (0.7 + 0.3 * math.sin(t * 3 + i * 2));
          c.drawLine(s + Offset(-l, 0), s + Offset(l, 0), pen);
          c.drawLine(s + Offset(0, -l), s + Offset(0, l), pen);
        }
      default:
        for (var i = 0; i < 5; i++) {
          final y = at.dy + (i - 2) * r * 0.32;
          final p = Path();
          for (var k = 0; k <= 22; k++) {
            final x = at.dx - r * 0.95 + k / 22 * r * 1.9;
            final yy = y + math.sin(k * 0.5 - t * 3 + i) * r * 0.1;
            k == 0 ? p.moveTo(x, yy) : p.lineTo(x, yy);
          }
          c.drawPath(p, pen);
        }
    }
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, moods = f.d.story.moods.take(5).toList();
    final first = moods.first;
    final k = ramp(f.t, 0.2, 1.2, Curves.easeOutBack);
    _draw(f, _sky(first.name), Offset(f.w / 2, f.h * 0.33), 112 * u * math.max(0.01, k), f.t);
    f.film.kinetic(f, 'Mostly', x: 24 * u, y: f.h * 0.545, size: 18 * u, at: 1.0, weight: FontWeight.w600, color: kDim);
    final h = f.film.kinetic(f, first.name, x: 24 * u, y: f.h * 0.545 + 24 * u, size: 62 * u, at: 1.2, lines: 1);
    var y = f.h * 0.545 + 40 * u + h;
    for (var i = 0; i < moods.length; i++) {
      final at = 2.2 + i * 0.22, kk = ramp(f.t, at, at + 0.6, Curves.easeOutCubic);
      if (kk <= 0) continue;
      c.save();
      c.translate((1 - kk) * 60 * u, 0);
      _draw(f, _sky(moods[i].name), Offset(40 * u, y + 11 * u), 14 * u, f.t + i);
      f.film.line(c, moods[i].name, 72 * u, y, 18 * u, weight: FontWeight.w600, width: f.w - 170 * u);
      f.film.line(c, '${moods[i].pct.round()}%', f.w - 24 * u, y, 18 * u, align: 1, color: kDim);
      c.restore();
      y += 37 * u;
    }
  }
}

// ── Tuner ───────────────────────────────────────────────────────────────────

/// A radio dial of years. The needle hunts through static and locks on when your music was made. Turn it.
class TunerScene extends FilmScene {
  @override
  String get id => 'era';
  @override
  String get technique => 'radio tuner and static';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'Release years of the ${d.story.known} of your most played songs your library knows. Half of those plays are older than this year, half newer.';
  @override
  String share(WrappedData d) => 'My music was made around ${d.story.era!.middle}.';
  @override
  String speech(WrappedData d) => 'The middle of your music is ${d.story.era!.middle}; oldest ${d.story.era!.oldest}, newest ${d.story.era!.newest}.';
  @override
  String? get hint => 'Turn the dial';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, e = f.d.story.era!;
    final lock = ramp(f.t, 0.6, 4.0, Curves.easeInOutQuart);
    final hunt = math.sin(f.t * 3.1) * 14 * (1 - lock);
    final year = mix(e.oldest - 6.0, e.middle.toDouble(), lock) + hunt - f.touch.spin * 8;
    final off = clamp01((year - e.middle).abs() / 9);
    // static that clears as it locks: torn lines, not dots
    final screen = Rect.fromLTWH(24 * u, f.h * 0.15, f.w - 48 * u, f.h * 0.25);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(screen, Radius.circular(18 * u)));
    c.drawRect(screen, fill(const Color(0xFF0B0B0C)));
    for (var i = 0; i < 22; i++) {
      final tick = (f.t * 14).floor();
      final y = screen.top + screen.height * (i + 0.5) / 22;
      final x = screen.left + rnd(i + tick * 31, 1) * screen.width;
      c.drawRect(Rect.fromLTWH(x, y - 2 * u, screen.width * (0.1 + 0.5 * rnd(i + tick * 17, 2)), 4 * u), fill(white(0.5 * off * rnd(i + tick * 13, 3))));
    }
    final tp = f.film.words('${year.round()}', 118 * u);
    final tear = off * 34 * u;
    for (var i = 0; i < 6; i++) {
      final strip = Rect.fromLTWH(screen.left, screen.top + screen.height * i / 6, screen.width, screen.height / 6 + 0.5);
      c.save();
      c.clipRect(strip);
      tp.paint(c, Offset(screen.center.dx - tp.width / 2 + math.sin(f.t * 19 + i * 2.4) * tear, screen.center.dy - tp.height / 2));
      c.restore();
    }
    c.restore();
    c.drawRRect(RRect.fromRectAndRadius(screen, Radius.circular(18 * u)), stroke(white(0.35), 1.4 * u));
    // the scale slides under a fixed needle
    final y = f.h * 0.485;
    final px = 17 * u;
    for (var k = (year - 13).floor(); k <= (year + 13).ceil(); k++) {
      final x = f.w / 2 + (k - year) * px;
      final ten = k % 10 == 0, five = k % 5 == 0;
      final edge = clamp01(1.15 - (x - f.w / 2).abs() / (f.w / 2));
      c.drawLine(Offset(x, y), Offset(x, y - (ten ? 34 : (five ? 22 : 12)) * u), stroke(white((ten ? 1 : 0.55) * edge), (ten ? 2.4 : 1.3) * u));
      if (ten) f.film.line(c, '$k', x, y + 7 * u, 14 * u, weight: FontWeight.w600, align: 0.5, color: white((edge * 8).round() / 8));
    }
    c.drawLine(Offset(f.w / 2, y - 48 * u), Offset(f.w / 2, y + 4 * u), stroke(kInk, 4 * u, cap: StrokeCap.round));
    // the knob
    final knob = Offset(f.w / 2, f.h * 0.6);
    c.drawCircle(knob, 46 * u, fill(const Color(0xFF1C1C1E)));
    c.drawCircle(knob, 46 * u, stroke(kInk, 2 * u));
    for (var i = 0; i < 28; i++) {
      final a = i / 28 * kTau + year * 0.16;
      c.drawLine(knob + Offset.fromDirection(a, 46 * u), knob + Offset.fromDirection(a, 39 * u), stroke(white(0.5), 1.6 * u));
    }
    c.drawCircle(knob + Offset.fromDirection(year * 0.16 - math.pi / 2, 28 * u), 5 * u, fill(kInk));
    f.film.kinetic(f, 'Your music was made around ${e.middle}', x: 24 * u, y: f.h * 0.715, size: 38 * u, at: 3.6);
    f.film.kinetic(f, 'From ${nice(e.oldestTitle)} (${e.oldest}) to ${nice(e.newestTitle)} (${e.newest})', x: 24 * u, y: f.h * 0.715 + 92 * u, size: 16 * u, at: 4.4, weight: FontWeight.w500, color: kDim, lines: 3, stagger: 0.04);
  }
}

// ── Faders ──────────────────────────────────────────────────────────────────

/// Seven channels, one a day. The engineer rides them to your week.
class FadersScene extends FilmScene {
  @override
  String get id => 'week';
  @override
  String get technique => 'mixing desk, faders and meters';
  @override
  double get length => 7.5;
  @override
  String why(WrappedData d) => 'Average minutes on each weekday, over the days you listened.';
  @override
  String share(WrappedData d) => '${_days[_top(d)]} is my music day.';
  @override
  String speech(WrappedData d) => '${_days[_top(d)]} was your loudest day, ${listeningTime(d.story.week[_top(d)])} on average.';
  @override
  String? get hint => 'Tap for a drum hit';

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static int _top(WrappedData d) {
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (d.story.week[i] > d.story.week[best]) best = i;
    }
    return best;
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, week = f.d.story.week;
    final top = _top(f.d), peak = math.max(1, week[top]);
    f.film.kinetic(f, '${_days[top]} was turned all the way up', x: 24 * u, y: f.h * 0.115, size: 34 * u, at: 3.0);
    final y0 = f.h * 0.275, h = f.h * 0.47;
    final w = (f.w - 24 * u) / 7;
    for (var i = 0; i < 7; i++) {
      final x = 12 * u + (i + 0.5) * w;
      // pushed about by hand before they settle
      final settle = ramp(f.t, 1.2 + i * 0.14, 2.6 + i * 0.14, Curves.easeOutBack);
      final riding = 0.5 + 0.38 * math.sin(f.t * 3.4 + i * 1.7);
      final v = clamp01(mix(riding, week[i] / peak, settle));
      final hot = i == top && settle > 0.9;
      c.drawLine(Offset(x + 8 * u, y0), Offset(x + 8 * u, y0 + h), stroke(const Color(0xFF3A3A3C), 4 * u, cap: StrokeCap.round));
      // the meter beside it
      final level = clamp01(v * (0.72 + 0.28 * math.sin(f.t * 11 + i * 2.3).abs()) + f.touch.punch() * 0.5);
      for (var k = 0; k < 18; k++) {
        final on = k / 18 < level;
        c.drawRect(Rect.fromLTWH(x - 15 * u, y0 + h - (k + 1) * h / 18 + 1.5 * u, 10 * u, h / 18 - 3 * u), fill(on ? (k > 14 ? kInk : const Color(0xFFAEAEB2)) : const Color(0xFF1C1C1E)));
      }
      final ky = y0 + h * (1 - v);
      final cap = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + 8 * u, ky), width: 24 * u, height: 40 * u), Radius.circular(5 * u));
      c.drawRRect(cap, fill(hot ? kInk : const Color(0xFF636366)));
      c.drawRRect(cap, stroke(kBlack, 2 * u));
      c.drawLine(Offset(x - 3 * u, ky), Offset(x + 19 * u, ky), stroke(hot ? kBlack : kInk, 2 * u));
      f.film.line(c, _days[i].substring(0, 1), x, y0 + h + 22 * u, 17 * u, weight: hot ? FontWeight.w800 : FontWeight.w600, align: 0.5, color: hot ? kInk : kDim);
      if (f.t > 3.2 + i * 0.08) f.film.line(c, week[i] >= 60 ? '${(week[i] / 60).toStringAsFixed(1)}h' : '${week[i]}m', x, y0 + h + 46 * u, 12.5 * u, weight: FontWeight.w600, align: 0.5, color: hot ? kInk : kDim);
    }
    f.film.kinetic(f, '${listeningTime(week[top])} on an average ${_days[top]}', x: 24 * u, y: f.h * 0.865, size: 17 * u, at: 3.8, weight: FontWeight.w500, color: kDim, lines: 1);
  }
}

// ── Calendar ────────────────────────────────────────────────────────────────

/// The year's calendar is marked off day by day, then a pen runs through your longest streak.
class CalendarScene extends FilmScene {
  @override
  String get id => 'streak';
  @override
  String get technique => 'wall calendar marked by hand';
  @override
  double get length => 8;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) => 'Every square is a day with music; brighter had more minutes. The pen line is your longest run of days in a row.';
  @override
  String share(WrappedData d) => 'My longest streak of ${d.year}: ${d.longestStreak} days.';
  @override
  String speech(WrappedData d) => 'Your longest streak was ${d.longestStreak} days, ${sayDate(d.streakStart)} to ${sayDate(d.streakEnd)}.';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, d = f.d;
    final by = <int, int>{};
    var peak = 1;
    for (final x in d.days) {
      final t = x.parsed;
      if (t == null) continue;
      by[t.month * 32 + t.day] = x.minutes;
      peak = math.max(peak, x.minutes);
    }
    final mw = (f.w - 48 * u) / 3, mh = f.h * 0.137;
    final cell = math.min((mw - 14 * u) / 7, (mh - 20 * u) / 6);
    Offset day(int m, int dd) {
      final lead = DateTime.utc(d.year, m).weekday - 1;
      final k = lead + dd - 1;
      return Offset(24 * u + ((m - 1) % 3) * mw + (k % 7 + 0.5) * cell, f.h * 0.115 + ((m - 1) ~/ 3) * mh + 18 * u + (k ~/ 7 + 0.5) * cell);
    }

    final drawn = ramp(f.t, 0.2, 3.0, Curves.easeInOutSine) * 372;
    for (var m = 1; m <= 12; m++) {
      f.film.line(c, monthNames[m - 1].substring(0, 3), 24 * u + ((m - 1) % 3) * mw + 1 * u, f.h * 0.115 + ((m - 1) ~/ 3) * mh, 12.5 * u, weight: FontWeight.w700, color: kDim);
      final last = DateTime.utc(d.year, m + 1, 0).day;
      for (var dd = 1; dd <= last; dd++) {
        final order = (m - 1) * 31 + dd;
        if (order > drawn) break;
        final v = by[m * 32 + dd];
        // a light runs over the finished year
        final pass = f.t < 5.6 ? 99.0 : ((f.t - 5.6) * 190 - order).abs();
        final pop = clamp01(math.min((drawn - order) / 12, pass / 14));
        final s = (cell - 2 * u) * (v == null ? 1 : mix(1.5, 1, pop));
        final shade = v == null ? const Color(0xFF161618) : Color.lerp(const Color(0xFF48484A), const Color(0xFFE5E5EA), math.sqrt(v / peak))!;
        c.drawRect(Rect.fromCenter(center: day(m, dd), width: s, height: s), fill(shade));
      }
    }
    final start = DateTime.tryParse(d.streakStart ?? ''), end = DateTime.tryParse(d.streakEnd ?? '');
    final pen = ramp(f.t, 3.2, 5.4, Curves.easeInOutCubic);
    if (start != null && end != null && pen > 0) {
      final s0 = DateTime.utc(start.year, start.month, start.day);
      final n = DateTime.utc(end.year, end.month, end.day).difference(s0).inDays + 1;
      final upto = (n * pen).ceil();
      Path? path;
      Offset? prev;
      void flush() {
        final line = path;
        if (line == null) return;
        c.drawPath(line, stroke(kBlack, cell * 0.95, cap: StrokeCap.round));
        c.drawPath(line, stroke(kInk, cell * 0.62, cap: StrokeCap.round));
      }

      for (var i = 0; i < upto; i++) {
        final t = s0.add(Duration(days: i));
        final p = day(t.month, t.day) + Offset(0, math.sin(i * 1.7) * 0.8 * u);
        // a new row is a new stroke
        if (prev == null || (p.dx - prev.dx).abs() > cell * 1.5 || p.dx < prev.dx) {
          flush();
          path = Path()
            ..moveTo(p.dx - cell * 0.2, p.dy)
            ..lineTo(p.dx + cell * 0.2, p.dy);
        } else {
          path!.lineTo(p.dx + cell * 0.2, p.dy);
        }
        prev = p;
      }
      flush();
    }
    final y = f.h * 0.685;
    final w = f.film.counter(f, d.longestStreak, (v) => '$v', x: 24 * u, y: y, size: 108 * u, from: 3.2, to: 5.4, width: 200 * u);
    f.film.kinetic(f, d.longestStreak == 1 ? 'day' : 'days in a row', x: 36 * u + w, y: y + 48 * u, size: 26 * u, at: 4.0, width: f.w - 60 * u - w);
    f.film.kinetic(f, '${sayDate(d.streakStart)} to ${sayDate(d.streakEnd)}, not one missed', x: 24 * u, y: y + 126 * u, size: 17 * u, at: 5.2, weight: FontWeight.w500, color: kDim);
  }
}
