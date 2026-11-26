import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// The closing run: how far you went, who stayed, your biggest day, who you are.

int _rgb(Color c) => c.toARGB32() & 0xFFFFFF;

// ── Warp ────────────────────────────────────────────────────────────────────

/// Hyperspace through everything you played: stars as particles, their trails as three batched line draws. Steer it.
class WarpScene extends FilmScene {
  static const _n = 240;
  static const _hues = [Color(0xFF6FF3FF), Color(0xFFFF7AD9), Color(0xFFFFFFFF)];
  final List<Float32List> _lines = [for (var i = 0; i < 3; i++) Float32List(_n * 4)];

  @override
  String get id => 'discovery';
  @override
  String get technique => 'hyperspace star field';
  @override
  bool get particles => true;
  @override
  double get length => 7;
  @override
  double get still => 4.6;
  @override
  String why(WrappedData d) => 'How many different songs and artists you played in ${d.year}.';
  @override
  String share(WrappedData d) => 'I travelled through ${d.uniqueSongs} songs in ${d.year}.';
  @override
  String speech(WrappedData d) => 'You played ${d.uniqueSongs} different songs by ${d.uniqueArtists} artists.';
  @override
  String? get hint => 'Drag to steer';

  double _run(double t) => t * 0.16 + 1.5 * ramp(t, 0.8, 3.4, Curves.easeInOutCubic);

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    f.sky(const Color(0xFF12052E), const Color(0xFF000006));
    final v = Offset(f.w / 2 + f.touch.tiltX * 90 * u, f.h * 0.42 + f.touch.tiltY * 90 * u);
    f.glow(v, f.w * 0.6, const Color(0x335A3CFF));
    final run = _run(f.t);
    final speed = ramp(f.t, 1.0, 1.8) * (1 - ramp(f.t, 2.8, 3.8));
    final n = f.grains(_n);
    if (speed > 0.01) {
      for (final l in _lines) {
        l.fillRange(0, l.length, 0);
      }
      for (var i = 0; i < n; i++) {
        final z = 1 - ((rnd(i, 80) + run) % 1);
        final a = rnd(i, 81) * kTau + f.t * 0.12;
        final k = (14 + 190 * math.sqrt(rnd(i, 82))) * u * 0.42;
        final r1 = k / (z + 0.06), r2 = k / (z + 0.06 + 0.22 * speed);
        final l = _lines[i % 3];
        final j = (i ~/ 3) * 4;
        l[j] = v.dx + math.cos(a) * r1;
        l[j + 1] = v.dy + math.sin(a) * r1;
        l[j + 2] = v.dx + math.cos(a) * r2;
        l[j + 3] = v.dy + math.sin(a) * r2;
      }
      for (var k = 0; k < 3; k++) {
        c.drawRawPoints(ui.PointMode.lines, _lines[k], stroke(_hues[k].withValues(alpha: 0.55 * speed), 1.4 * u, cap: StrokeCap.round));
      }
    }
    f.film.dots(c, n, (i, o) {
      final z = 1 - ((rnd(i, 80) + run) % 1);
      final a = rnd(i, 81) * kTau + f.t * 0.12;
      final r = (14 + 190 * math.sqrt(rnd(i, 82))) * u / (z + 0.06) * 0.42;
      final x = v.dx + math.cos(a) * r, y = v.dy + math.sin(a) * r;
      final words = (y - (f.h * 0.42 + 34 * u)).abs() < 104 * u && (x - f.w / 2).abs() < 170 * u;
      o.set(x, y, (0.6 + (1 - z) * 2.6) * u, math.min(1, (1 - z) * 1.5) * (words ? 1 - 0.85 * ramp(f.t, 2.8, 3.8) : 1), _rgb(_hues[i % 3]));
    });
    final k = ramp(f.t, 1.6, 3.6, Curves.easeOutExpo);
    if (k > 0.01) {
      c.save();
      final mid = Offset(f.w / 2, f.h * 0.42);
      c.translate(mid.dx, mid.dy);
      c.scale(0.05 + 0.95 * k);
      c.translate(-mid.dx, -mid.dy);
      f.film.counter(f, f.d.uniqueSongs, grouped, x: f.w / 2, y: f.h * 0.42 - 62 * u, size: 112 * u, from: 1.6, to: 3.6, align: 0.5);
      c.restore();
    }
    f.film.kinetic(f, 'different songs', x: f.w / 2, y: f.h * 0.42 + 64 * u, size: 30 * u, at: 3.0, center: true, lines: 1, color: const Color(0xFF8CF6FF));
    f.film.kinetic(f, 'from ${grouped(f.d.uniqueArtists)} artists', x: f.w / 2, y: f.h * 0.42 + 104 * u, size: 20 * u, at: 3.7, weight: FontWeight.w500, color: const Color(0xFFFFA8E6), center: true, lines: 1);
  }
}

// ── Scoreboard ──────────────────────────────────────────────────────────────

/// A stadium scoreboard of bulbs: the months one artist stayed, and who came back.
class ScoreboardScene extends FilmScene {
  @override
  String get id => 'loyalty';
  @override
  String get technique => 'stadium bulb scoreboard and a boomerang';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'The artist who was in your top artists in the most months. A comeback left those lists for at least two months and returned.';
  @override
  String share(WrappedData d) => '${d.story.loyal!.name} stayed with me for ${d.story.loyal!.months.length} months of ${d.year}.';
  @override
  String speech(WrappedData d) {
    final l = d.story.loyal!, c = d.story.comeback;
    return '${l.name} was with you in ${l.months.length} months.${c == null ? '' : ' ${c.name} left for ${c.gap} months and came back in ${monthNames[c.month - 1]}.'}';
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, l = f.d.story.loyal!, back = f.d.story.comeback;
    f.sky(const Color(0xFF071A3A), const Color(0xFF01040C));
    for (final x in [0.15, 0.85]) {
      f.glow(Offset(f.w * x, 0), f.h * 0.5, const Color(0x40FFE9A8));
    }
    f.film.kinetic(f, 'They never left', x: 24 * u, y: f.h * 0.115, size: 36 * u, at: 0.1, lines: 1);
    final board = Rect.fromLTWH(16 * u, f.h * 0.195, f.w - 32 * u, f.h * 0.33);
    c.drawRRect(RRect.fromRectAndRadius(board, Radius.circular(12 * u)), fill(const Color(0xFF0A0E18)));
    final path = Path()..addRRect(RRect.fromRectAndRadius(board.deflate(7 * u), Radius.circular(8 * u)));
    for (final m in path.computeMetrics()) {
      final n = (m.length / (15 * u)).floor();
      for (var i = 0; i < n; i++) {
        final p = m.getTangentForOffset(m.length * i / n)!.position;
        c.drawCircle(p, 2.6 * u, fill((i + (f.t * 9).floor()) % 3 == 0 ? const Color(0xFFFFE9A8) : const Color(0xFF2A3348)));
      }
    }
    final lit = ramp(f.t, 1.0, 4.0, Curves.linear) * 12;
    var score = 0;
    final w = (board.width - 48 * u) / 6;
    for (var m = 1; m <= 12; m++) {
      final here = l.months.contains(m) && m <= lit;
      if (here) score++;
      final p = Offset(board.left + 24 * u + ((m - 1) % 6 + 0.5) * w, board.top + (m <= 6 ? 0.36 : 0.74) * board.height);
      final pop = here ? 1 + 0.35 * clamp01(1 - (lit - m)) + 0.05 * math.sin(f.t * 4 + m) : 1.0;
      if (here) f.glow(p, 34 * u, const Color(0x66FFB627));
      c.drawCircle(p, 17 * u * pop, fill(here ? Tone.gold : const Color(0xFF1A2236)));
      f.film.line(c, monthNames[m - 1].substring(0, 3), p.dx, p.dy - 6.5 * u, 11 * u, weight: FontWeight.w800, align: 0.5, color: here ? const Color(0xFF2A1A00) : const Color(0xFF7F8BA8));
    }
    final y = f.h * 0.555;
    c.drawCircle(Offset(70 * u, y + 46 * u), 48 * u, fill(Tone.gold));
    f.film.picture(c, f.assets.people[l.name], Rect.fromCircle(center: Offset(70 * u, y + 46 * u), radius: 45 * u), radius: 45 * u, tile: true);
    f.film.kinetic(f, l.name, x: 132 * u, y: y + 2 * u, size: 31 * u, at: 1.0, width: f.w - 156 * u);
    if (f.t > 1.2) f.film.line(c, '$score of 12 months', 132 * u, y + 70 * u, 18 * u, color: const Color(0xFFFFD27A));
    if (back != null) {
      final k = ramp(f.t, 4.2, 6.2, Curves.easeInOutCubic);
      final by = f.h * 0.755;
      final arc = Path();
      for (var i = 0; i <= 40; i++) {
        final a = math.pi * (0.5 + 2 * i / 40);
        final p = Offset(f.w / 2 + math.cos(a) * (f.w / 2 - 36 * u), by + 8 * u + math.sin(a) * 17 * u);
        i == 0 ? arc.moveTo(p.dx, p.dy) : arc.lineTo(p.dx, p.dy);
      }
      for (final m in arc.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * k), stroke(const Color(0x66FF5470), 1.6 * u));
        final at = m.getTangentForOffset(m.length * k);
        if (at != null && k > 0) {
          c.save();
          c.translate(at.position.dx, at.position.dy);
          c.rotate(f.t * 16 * (1 - k) + 0.6);
          c.drawPath(
            Path()
              ..moveTo(-12 * u, 9 * u)
              ..lineTo(0, -7 * u)
              ..lineTo(12 * u, 9 * u),
            stroke(Tone.coral, 6 * u, cap: StrokeCap.round),
          );
          c.restore();
        }
      }
      f.film.kinetic(f, '${back.name} went away for ${back.gap} months and came back in ${monthNames[back.month - 1]}', x: 24 * u, y: by + 36 * u, size: 19 * u, at: 5.2, weight: FontWeight.w600, lines: 3, stagger: 0.05, color: const Color(0xFFFFB3C0));
    }
  }
}

// ── Shore ───────────────────────────────────────────────────────────────────

/// A beach at your biggest day: waves wash up the sand to where a usual day reaches, then one comes in far past it.
/// Foam is the only particle; the sea is drawn. Tip it with your finger.
class ShoreScene extends FilmScene {
  final double usual;
  ShoreScene(WrappedData d)
    : usual = d.days.isEmpty || d.bestDay!.minutes == 0 ? 0 : clamp01(d.days.fold<int>(0, (a, b) => a + b.minutes) / d.days.length / d.bestDay!.minutes);
  @override
  String get id => 'best-day';
  @override
  String get technique => 'shore and waves, the tide to your record';
  @override
  bool get particles => true; // the foam
  @override
  double get length => 9;
  @override
  double get still => 7.4;
  @override
  String why(WrappedData d) => 'Your day with the most minutes. The stick in the sand is your average over the days you listened.';
  @override
  String share(WrappedData d) => 'My biggest music day of ${d.year}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String speech(WrappedData d) => 'Your biggest day was ${sayDate(d.bestDay!.date)}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String? get hint => 'Tip the sea';

  /// How far up the beach the water comes at [t], 0 the waterline, 1 the record.
  double _level(double t) => mix(usual * ramp(t, 0.4, 2.2, Curves.easeOutCubic), 1, ramp(t, 3.0, 5.2, Curves.easeInOutBack));

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, best = f.d.bestDay!;
    final horizon = f.h * 0.4;
    final level = _level(f.t);
    // sky, a low sun, the sea to the horizon
    f.sky(const Color(0xFF0B2F66), const Color(0xFF3E9FD6));
    c.drawRect(Rect.fromLTWH(0, horizon, f.w, f.h), Paint()..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, f.h), const [Color(0xFFF2D7A8), Color(0xFFD9B27A)]));
    f.glow(Offset(f.w * 0.78, horizon - 30 * u), 120 * u, const Color(0x88FFE3A8));
    c.drawCircle(Offset(f.w * 0.78, horizon - 22 * u), 22 * u, fill(const Color(0xFFFFF1C9)));
    // where the water reaches on the sand: from just below the horizon (none) to near the bottom (the record)
    double reach(double v) => mix(horizon + 26 * u, f.h * 0.94, v);
    final tip = f.touch.tiltX * 60 * u;
    double edge(double x, double phase, double amp) =>
        math.sin(x / f.w * 7 + f.t * 1.3 + phase) * 9 * u * amp + math.sin(x / f.w * 17 - f.t * 2 + phase) * 4 * u * amp + (x / f.w - 0.5) * tip;
    // waves breathe in and out around the reach
    final wash = math.sin(f.t * 1.6) * 10 * u + f.touch.punch() * 30 * u;
    final front = reach(level) + wash;
    // the usual-day stick
    final stick = reach(usual);
    c.drawLine(Offset(f.w * 0.18, stick - 34 * u), Offset(f.w * 0.18, stick + 4 * u), stroke(const Color(0xFF6B4423), 4 * u, cap: StrokeCap.round));
    c.drawRect(Rect.fromLTWH(f.w * 0.18 - 2 * u, stick - 34 * u, 58 * u, 18 * u), fill(const Color(0xFF6B4423)));
    f.film.line(c, 'a usual day', f.w * 0.18 + 2 * u, stick - 32 * u, 11 * u, weight: FontWeight.w700, color: const Color(0xFFFFF1C9));
    // wet sand behind the water's edge
    final wet = Path()..moveTo(0, horizon);
    for (var i = 0; i <= 40; i++) {
      final x = i / 40 * f.w;
      wet.lineTo(x, front + 14 * u + edge(x, 1.3, 1));
    }
    wet
      ..lineTo(f.w, horizon)
      ..close();
    c.drawPath(wet, fill(const Color(0xFFB99062)));
    // three bands of sea, deep to shallow
    const bands = [(Color(0xFF0A3E7A), 0.0), (Color(0xFF137FB0), 0.45), (Color(0xFF2FD1C5), 0.85)];
    for (final (col, k) in bands) {
      final sea = Path()..moveTo(0, horizon);
      for (var i = 0; i <= 40; i++) {
        final x = i / 40 * f.w;
        sea.lineTo(x, mix(horizon, front, k) + edge(x, k * 3, 1 + k));
      }
      sea
        ..lineTo(f.w, horizon)
        ..close();
      if (k == 0.0) {
        c.drawRect(Rect.fromLTWH(0, horizon, f.w, front - horizon + 30 * u), Paint()..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, front), const [Color(0xFF0A2E5E), Color(0xFF1A8FC4)]));
      }
      c.drawPath(sea, fill(col.withValues(alpha: k == 0.0 ? 0 : 0.85)));
    }
    final foam = Path();
    for (var i = 0; i <= 40; i++) {
      final x = i / 40 * f.w;
      final y = front + edge(x, 2.55, 1.85);
      i == 0 ? foam.moveTo(x, y) : foam.lineTo(x, y);
    }
    c.drawPath(foam, stroke(const Color(0xFFF4FFFD), 5 * u, cap: StrokeCap.round));
    // foam: little bubbles riding the edge, left as the wave draws back
    final n = f.grains(260);
    f.film.dots(c, n, (i, o) {
      final x = rnd(i, 120) * f.w;
      final life = (f.t * (0.3 + rnd(i, 121) * 0.4) + rnd(i, 122)) % 1;
      final y = front + edge(x, 2.55, 1.85) - life * 16 * u * rnd(i, 123) + rnd(i, 124) * 10 * u;
      o.set(x + math.sin(f.t + i) * 3 * u, y, (1 + rnd(i, 125) * 2) * u, (1 - life) * 0.9, 0xFFFFFF);
    });
    // the words, in the sky
    f.film.kinetic(f, sayDate(best.date), x: 24 * u, y: f.h * 0.09, size: 44 * u, at: 2.8, lines: 1);
    f.film.kinetic(f, 'The day the music came all the way in.', x: 24 * u, y: f.h * 0.09 + 54 * u, size: 17 * u, at: 3.3, weight: FontWeight.w500, color: const Color(0xFFCDEBFF));
    f.film.counter(f, best.minutes, listeningTime, x: 24 * u, y: f.h * 0.09 + 84 * u, size: 66 * u, from: 3.0, to: 5.2);
    if (usual > 0) {
      final times = best.minutes / (usual * best.minutes);
      if (times >= 1.5) f.film.kinetic(f, '${times.toStringAsFixed(times >= 10 ? 0 : 1)} times a usual day', x: 24 * u, y: f.h * 0.87, size: 22 * u, at: 5.4, lines: 1);
    }
  }
}

// ── Receipt ─────────────────────────────────────────────────────────────────

/// The till prints your year, line by line, and tears it off.
class ReceiptScene extends FilmScene {
  @override
  String get id => 'totals';
  @override
  String get technique => 'printing receipt';
  @override
  double get length => 8;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) => 'Your year’s totals as your server counted them. Skipped is the share of plays your server marked as skips.';
  @override
  String share(WrappedData d) => 'My ${d.year} receipt: ${grouped(d.totalMinutes)} minutes.';
  @override
  String speech(WrappedData d) => '${d.totalPlays} plays, ${d.uniqueSongs} different songs, ${d.uniqueArtists} artists, ${d.listeningDays} days with music.';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, d = f.d;
    f.sky(const Color(0xFF6A0F2A), const Color(0xFF1A0309));
    f.glow(Offset(f.w / 2, f.h * 0.45), f.w * 0.7, const Color(0x40FF7A9A));
    final lines = [
      ('Plays', grouped(d.totalPlays)),
      ('Different songs', grouped(d.uniqueSongs)),
      ('Different artists', grouped(d.uniqueArtists)),
      ('Days with music', '${d.listeningDays}'),
      if (d.listeningDays > 0) ('Songs a day', (d.totalPlays / d.listeningDays).toStringAsFixed(1)),
      if (d.longestStreak > 1) ('Longest streak', '${d.longestStreak} days'),
      ('Skipped', '${(d.skipRate * 100).round()}%'),
    ];
    final w = 278 * u, rowH = 33 * u;
    final full = 100 * u + lines.length * rowH + 128 * u;
    final raw = ramp(f.t, 0.5, 5.4, Curves.linear) * (lines.length + 4);
    final step = raw.floor() + Curves.easeOutCubic.transform(raw - raw.floor());
    final out = full * clamp01(step / (lines.length + 4));
    final cutK = ramp(f.t, 5.6, 6.1, Curves.easeOutBack);
    final slot = f.h * 0.15;
    c.save();
    c.clipRect(Rect.fromLTWH(0, slot, f.w, f.h));
    c.translate(f.w / 2, slot - full + out + cutK * 26 * u);
    c.rotate(cutK * (-0.035 + math.sin(f.t * 1.5) * 0.02));
    final paper = Path()..moveTo(-w / 2, cutK > 0 ? 6 * u : -200 * u);
    if (cutK > 0) {
      for (var x = -w / 2; x < w / 2 - 1; x += w / 22) {
        paper.lineTo(x + w / 44, 0);
        paper.lineTo(x + w / 22, 6 * u);
      }
    } else {
      paper.lineTo(w / 2, -200 * u);
    }
    paper.lineTo(w / 2, full);
    for (var x = w / 2; x > -w / 2 + 1; x -= w / 22) {
      paper.lineTo(x - w / 44, full - 6 * u);
      paper.lineTo(x - w / 22, full);
    }
    c.drawPath(paper..close(), fill(const Color(0xFFFFFBF2)));
    final l = -w / 2 + 18 * u, r = w / 2 - 18 * u;
    const ink = Color(0xFF1A1A1A), soft = Color(0xFF5A5A5A);
    f.film.line(c, 'NaviVibe', 0, 20 * u, 25 * u, weight: FontWeight.w800, color: ink, align: 0.5);
    f.film.line(c, 'Your ${d.year} in full', 0, 52 * u, 14 * u, weight: FontWeight.w500, color: soft, align: 0.5);
    void dash(double y) {
      for (var x = l; x < r; x += 8 * u) {
        c.drawLine(Offset(x, y), Offset(math.min(r, x + 4.5 * u), y), stroke(ink, 1.3 * u));
      }
    }

    dash(84 * u);
    var y = 98 * u;
    for (final (k, v) in lines) {
      f.film.line(c, k, l, y, 16 * u, weight: FontWeight.w500, color: ink, width: 160 * u);
      f.film.line(c, v, r, y, 16 * u, color: ink, align: 1);
      y += rowH;
    }
    dash(y + 2 * u);
    f.film.line(c, 'Total', l, y + 16 * u, 26 * u, weight: FontWeight.w800, color: ink);
    f.film.line(c, '${grouped(d.totalMinutes)} min', r, y + 16 * u, 26 * u, weight: FontWeight.w800, color: const Color(0xFFC2185B), align: 1, width: 180 * u);
    var bx = l;
    for (var i = 0; bx < r - 3 * u; i++) {
      final bw = (1 + (rnd(i, 13) * 3).floor()) * 1.3 * u;
      c.drawRect(Rect.fromLTWH(bx, y + 62 * u, bw, 36 * u), fill(ink));
      bx += bw + (1 + (rnd(i, 14) * 3).floor()) * 1.3 * u;
    }
    c.restore();
    final jig = raw > 0 && f.t < 5.4 ? math.sin(f.t * 70) * 0.8 * u : 0.0;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(16 * u, slot - 30 * u + jig, f.w - 32 * u, 36 * u), Radius.circular(10 * u)), fill(const Color(0xFF2A0A14)));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(30 * u, slot - 6 * u + jig, f.w - 60 * u, 7 * u), Radius.circular(3 * u)), fill(const Color(0xFF000000)));
    f.film.kinetic(f, 'Paid in full: ${grouped(d.totalMinutes)} minutes', x: 24 * u, y: f.h * 0.84, size: 30 * u, at: 6.1);
  }
}

// ── Spirit ──────────────────────────────────────────────────────────────────

/// Your personality takes a body made of light: a moon, a compass, a heart, an endless loop or a wave, turning in space.
class SpiritScene extends FilmScene {
  final WrappedPersonality me;
  SpiritScene(WrappedData d) : me = d.personality;
  @override
  String get id => 'personality';
  @override
  String get technique => 'a body of light in your personality’s shape';
  @override
  bool get particles => true;
  @override
  double get length => 8;
  @override
  String why(WrappedData d) =>
      'Four measures from your year: how many different songs for your plays, how much was one artist, how much came between 10 pm and 5 am, and how big your biggest day was next to a usual one. The strongest names you.';
  @override
  String share(WrappedData d) => 'I am ${d.personality.name}.';
  @override
  String speech(WrappedData d) => 'Your listening personality: ${d.personality.name}. ${d.personality.line}';
  @override
  String? get hint => 'Turn it around';

  (Color, Color, Color) get _hues => switch (me.id) {
    'night' => (const Color(0xFF070B2E), Tone.azure, const Color(0xFFBFD4FF)),
    'explorer' => (const Color(0xFF032A2A), Tone.teal, Tone.lime),
    'devotee' => (const Color(0xFF2E0618), Tone.magenta, Tone.coral),
    'marathon' => (const Color(0xFF2E1004), Tone.ember, Tone.gold),
    _ => (const Color(0xFF0B1A36), Tone.azure, Tone.cream),
  };

  (double, double, double) _body(int i, int n) {
    final v = i / n, j = rnd(i, 100), z = (rnd(i, 101) - 0.5) * 0.36;
    switch (me.id) {
      case 'night':
        for (var k = 0; k < 6; k++) {
          final a = rnd(i, 102 + k) * kTau, r = math.sqrt(rnd(i, 110 + k));
          final x = math.cos(a) * r, y = math.sin(a) * r;
          if ((x - 0.42) * (x - 0.42) + (y + 0.12) * (y + 0.12) > 0.68) return (x + 0.2, y, z);
        }
        final a = 0.7 + v * 5.0;
        return (math.cos(a) + 0.2, math.sin(a), z);
      case 'explorer':
        final a = v * kTau * 3 % kTau;
        final r = (0.16 + 0.92 * math.pow(math.cos(a * 2).abs(), 3.2) + math.pow(math.sin(a * 2).abs(), 9) * 0.5) * math.sqrt(j);
        return (math.cos(a) * r, math.sin(a) * r, z * (1 - r * 0.7));
      case 'devotee':
        final a = v * kTau * 5 % kTau, s = math.sqrt(j);
        final x = 16 * math.pow(math.sin(a), 3) / 17;
        final y = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a)) / 17;
        return (x * s, y * s, z * (1.4 - s));
      case 'marathon':
        final a = v * kTau * 3 % kTau, den = 1 + math.sin(a) * math.sin(a), tube = rnd(i, 103) * kTau;
        return (1.15 * math.cos(a) / den + math.cos(tube) * 0.1, 1.15 * math.sin(a) * math.cos(a) / den * 1.35 + math.sin(tube) * 0.1, math.sin(a) * 0.3 + z * 0.4);
      default:
        final x = v * 2 - 1, row = i % 9;
        return (x, math.sin(x * 4 + row * 0.3) * 0.28 + (row - 4) * 0.11, (row - 4) * 0.08);
    }
  }

  @override
  void paint(FilmFrame f) {
    final u = f.u;
    final (ground, a, b) = _hues;
    f.sky(ground, const Color(0xFF000000));
    final mid = Offset(f.w / 2, f.h * 0.37);
    f.glow(mid, 200 * u * ramp(f.t, 0, 1.5), a.withValues(alpha: 0.35));
    final n = f.grains(900);
    final form = ramp(f.t, 0.1, 1.6, Curves.easeOutCubic);
    f.film.dots(f.canvas, n, (i, o) {
      final (x, y, z) = _body(i, n);
      final turn = math.sin(f.t * 0.7) * 0.5 + f.touch.spin;
      final cx = x * math.cos(turn) + z * math.sin(turn), cz = -x * math.sin(turn) + z * math.cos(turn);
      final persp = 1.6 / (1.6 - cz * 0.35);
      final beat = me.id == 'devotee' ? 1 + 0.07 * math.pow(math.max(0, math.sin(f.t * 4.4)), 4) : 1 + 0.015 * math.sin(f.t * 2);
      final flow = me.id == 'marathon' || me.id == 'easy' ? (i / n * 3 - f.t * 0.5) % 1 : rnd(i, 104);
      final glow = 0.45 + 0.55 * math.pow(0.5 + 0.5 * math.cos((flow + f.t * 0.15) * kTau), 2);
      final sx = mid.dx + (rnd(i, 1) - 0.5) * f.w * (1 - form), sy = mid.dy + (rnd(i, 2) - 0.5) * f.h * 0.6 * (1 - form);
      o.set(
        mix(sx, mid.dx + cx * 122 * u * persp * beat, form),
        mix(sy, mid.dy + y * 122 * u * persp * beat, form),
        (1.3 + rnd(i, 105) * 0.9) * u * persp,
        glow * clamp01(0.65 + cz * 0.4),
        _rgb(Color.lerp(a, b, glow)!),
      );
    });
    f.film.kinetic(f, 'You are', x: f.w / 2, y: f.h * 0.655, size: 20 * u, at: 1.5, weight: FontWeight.w600, color: b, center: true);
    final h = f.film.kinetic(f, me.name, x: f.w / 2, y: f.h * 0.655 + 27 * u, size: 55 * u, at: 1.9, center: true, stagger: 0.25);
    f.film.kinetic(f, me.line, x: f.w / 2, y: f.h * 0.655 + 38 * u + h, size: 18 * u, at: 2.8, weight: FontWeight.w500, color: b, center: true, width: f.w - 64 * u, lines: 3, stagger: 0.04);
  }
}

// ── Mixtape ─────────────────────────────────────────────────────────────────

/// The year as a mixtape sleeve: your cover slides together from slats, the track list is written in, and the share button waits.
class MixtapeScene extends FilmScene {
  @override
  String get id => 'finale';
  @override
  String get technique => 'mixtape sleeve, sliced cover';
  @override
  double get length => 9;
  @override
  double get still => 6.4;
  @override
  String why(WrappedData d) => 'Your year on one sleeve. Your name is on what you share only if you turn it on.';
  @override
  String share(WrappedData d) => 'My ${d.year} Wrapped.';
  @override
  String speech(WrappedData d) =>
      '${d.year} Wrapped. ${listeningTime(d.totalMinutes)}${d.songs.isEmpty ? '' : ', number one ${nice(d.songs.first.title)}'}${d.artists.isEmpty ? '' : ', top artist ${d.artists.first.name}'}. ${d.personality.name}.';
  @override
  String? get hint => 'Tilt it';

  Rect _button(FilmFrame f) => Rect.fromLTWH(24 * f.u, f.h - 132 * f.u, f.w - 48 * f.u, 54 * f.u);

  @override
  double? tap(FilmFrame f, Offset p) {
    if (_button(f).inflate(6 * f.u).contains(p)) f.touch.wantsShare = true;
    return null;
  }

  void _sliced(FilmFrame f, Rect box, double from) {
    final c = f.canvas, d = f.d;
    final image = d.songs.isEmpty ? null : f.assets.covers[d.songs.first.coverKey];
    const n = 9;
    for (var i = 0; i < n; i++) {
      final k = ramp(f.t, from + i * 0.09, from + 0.8 + i * 0.09, Curves.easeOutBack);
      if (k <= 0) continue;
      final shift = (1 - k) * (i.isEven ? -1 : 1) * box.height * 1.3;
      c.save();
      c.clipRect(Rect.fromLTWH(box.left + box.width * i / n, box.top + shift, box.width / n + 0.5, box.height));
      c.translate(0, shift);
      // a slow drift across the cover once it is whole
      final drift = 1.04 + 0.03 * math.sin(f.t * 0.7);
      f.film.picture(c, image, Rect.fromCenter(center: box.center + Offset(math.sin(f.t * 0.5) * 6 * f.u, 0), width: box.width * drift, height: box.height * drift), tile: true);
      c.restore();
    }
  }

  @override
  void paint(FilmFrame f) {
    final u = f.u, c = f.canvas, d = f.d;
    final tone = f.tone(d.songs.isEmpty ? null : d.songs.first.coverKey, Tone.violet);
    f.sky(tone.deep, const Color(0xFF000000));
    if (f.h < f.w * 1.2) return _square(f, tone);
    c.save();
    final tilt = Matrix4.identity()
      ..setEntry(3, 2, 0.0011 / u)
      ..rotateY(f.touch.tiltX * 0.35)
      ..rotateX(-f.touch.tiltY * 0.3);
    c.translate(f.w / 2, f.h / 2);
    c.transform(tilt.storage);
    c.translate(-f.w / 2, -f.h / 2);
    final art = Rect.fromLTWH(0, 0, f.w, f.h * 0.44);
    _sliced(f, art, 0.2);
    final x = 24 * u;
    var y = art.bottom + 16 * u;
    final who = f.name == null || f.name!.isEmpty ? 'Wrapped ${d.year}' : '${f.name} · Wrapped ${d.year}';
    f.film.kinetic(f, who, x: x, y: y, size: 17 * u, at: 1.3, weight: FontWeight.w700, lines: 1, color: tone.light);
    y += 25 * u;
    y += f.film.kinetic(f, d.personality.name, x: x, y: y, size: 42 * u, at: 1.5, lines: 1) + 6 * u;
    final col = (f.w - 48 * u - 14 * u) / 2;
    final sideB = [
      (grouped(d.totalMinutes), 'minutes'),
      if (d.artists.isNotEmpty) (d.artists.first.name, 'artist'),
      if (d.genres.isNotEmpty) (d.genres.first.name, 'sound'),
      if (d.longestStreak > 1) ('${d.longestStreak} days', 'streak'),
      if (d.story.era != null) ('${d.story.era!.middle}', 'era') else ('${grouped(d.uniqueSongs)} songs', 'explored'),
    ];
    final rows = math.max(d.songs.length, sideB.length);
    final live = f.touch.live;
    final rowH = live ? 36 * u : 42 * u;
    for (var i = 0; i < rows; i++) {
      final at = 2.2 + i * 0.22, k = ramp(f.t, at, at + 0.5, Curves.easeOutCubic);
      if (k <= 0) break;
      final ry = y + i * rowH;
      c.drawLine(Offset(x, ry), Offset(x + (f.w - 48 * u) * k, ry), stroke(tone.light.withValues(alpha: 0.3), 1 * u));
      if (k < 0.6) continue;
      if (i < d.songs.length) {
        f.film.line(c, '${i + 1}  ${nice(d.songs[i].title)}', x, ry + 5 * u, 15 * u, width: col);
        f.film.line(c, d.songs[i].artist, x + 17 * u, ry + 22 * u, 11.5 * u, weight: FontWeight.w500, color: tone.light, width: col - 17 * u);
      }
      if (i < sideB.length) {
        f.film.line(c, sideB[i].$1, x + col + 14 * u, ry + 5 * u, 15 * u, width: col);
        f.film.line(c, sideB[i].$2, x + col + 14 * u, ry + 22 * u, 11.5 * u, weight: FontWeight.w500, color: tone.light, width: col);
      }
    }
    if (!live) f.film.kinetic(f, 'NaviVibe', x: x, y: f.h * 0.935, size: 15 * u, at: 3.6, weight: FontWeight.w700);
    final s = ramp(f.t % 4, 3.0, 3.9) * 1.6 - 0.3;
    if (s > -0.3 && s < 1.3) {
      c.save();
      c.clipRect(art);
      c.translate(f.w * s, 0);
      c.skew(-0.35, 0);
      c.drawRect(Rect.fromLTWH(0, 0, 46 * u, f.h), fill(const Color(0x24FFFFFF)));
      c.restore();
    }
    c.restore();
    if (live) {
      // the way out of the film: one big button, breathing
      final k = ramp(f.t, 3.2, 3.9, Curves.easeOutBack);
      if (k > 0) {
        final b = _button(f);
        c.save();
        c.translate(b.center.dx, b.center.dy);
        c.scale(k * (1 + 0.02 * math.sin(f.t * 3)));
        final r = Rect.fromCenter(center: Offset.zero, width: b.width, height: b.height);
        c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(b.height / 2)), Paint()..shader = ui.Gradient.linear(r.centerLeft, r.centerRight, [Tone.coral, Tone.gold]));
        f.film.line(c, 'Share your Wrapped', 0, -11 * u, 19 * u, weight: FontWeight.w800, color: const Color(0xFF1A0A06), align: 0.5);
        c.restore();
      }
    }
  }

  void _square(FilmFrame f, Tone tone) {
    final u = f.u, d = f.d, c = f.canvas;
    _sliced(f, Rect.fromLTWH(f.w * 0.46, 0, f.w * 0.54, f.h * 0.54), 0);
    final x = 22 * u;
    f.film.line(c, f.name == null || f.name!.isEmpty ? 'Wrapped ${d.year}' : '${f.name} · ${d.year}', x, 22 * u, 16 * u, color: tone.light, width: 136 * u);
    f.film.kinetic(f, d.personality.name, x: x, y: 62 * u, size: 36 * u, at: 0, lines: 3, width: 136 * u);
    var y = f.h * 0.54 + 16 * u;
    for (final (k, v) in [
      ('Listened', '${grouped(d.totalMinutes)} minutes'),
      if (d.songs.isNotEmpty) ('Song', nice(d.songs.first.title)),
      if (d.artists.isNotEmpty) ('Artist', d.artists.first.name),
      if (d.longestStreak > 1) ('Streak', '${d.longestStreak} days'),
    ]) {
      f.film.line(c, k, x, y + 3 * u, 13 * u, weight: FontWeight.w500, color: tone.light);
      f.film.line(c, v, x + 72 * u, y, 17 * u, width: f.w - 120 * u);
      y += 27 * u;
    }
    f.film.line(c, 'NaviVibe', f.w - 22 * u, f.h - 34 * u, 14 * u, align: 1);
  }
}
