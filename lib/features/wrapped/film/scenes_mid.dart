import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// The middle of the film: when, what kind, and what it meant.

// ── Ribbons ─────────────────────────────────────────────────────────────────

/// Your sound as one woven ribbon, a coloured strand for each genre as thick as its share. Pull it.
class RibbonScene extends FilmScene {
  @override
  String get id => 'genres';
  @override
  String get technique => 'woven coloured ribbons';
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

  static const _strands = [Tone.coral, Tone.gold, Tone.teal, Tone.azure, Tone.violet];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    f.sky(const Color(0xFF240A33), const Color(0xFF07020B));
    f.glow(Offset(f.w * 0.5, f.h * 0.36), f.w * 0.8, Tone.magenta.withValues(alpha: 0.2));
    final g = f.d.genres.take(5).toList();
    final total = math.max(1.0, g.fold<double>(0, (a, b) => a + b.pct));
    final draw = ramp(f.t, 0.2, 2.4, Curves.easeInOutCubic);
    final mid = f.h * 0.36;
    double y(int k, double x) =>
        mid +
        math.sin(x * 5.2 + f.t * 0.9 + k * kTau / g.length + f.touch.spin * 0.5) * 88 * u * (0.75 + 0.25 * math.sin(x * 2 + f.t * 0.6)) +
        math.sin(x * 11 - f.t * 0.7 + k) * 12 * u +
        f.touch.tiltY * 50 * u * math.sin(x * math.pi);
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, f.w * draw, f.h));
    const steps = 64, slices = 16;
    for (var s = 0; s < slices; s++) {
      final xm = (s + 0.5) / slices;
      final order = [for (var k = 0; k < g.length; k++) k]
        ..sort((a, b) => math.cos(xm * 5.2 + f.t * 0.9 + a * kTau / g.length).compareTo(math.cos(xm * 5.2 + f.t * 0.9 + b * kTau / g.length)));
      for (final k in order) {
        final w = math.max(6 * u, g[k].pct / total * 110 * u);
        final path = Path();
        final a = s * steps ~/ slices, b = (s + 1) * steps ~/ slices + 1;
        for (var i = a; i <= b && i <= steps; i++) {
          final p = Offset(i / steps * f.w, y(k, i / steps));
          i == a ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        final front = math.cos(xm * 5.2 + f.t * 0.9 + k * kTau / g.length);
        c.drawPath(path, stroke(Color.lerp(_strands[k], const Color(0xFF000000), 0.45 * (1 - front) / 2)!, w));
        c.drawPath(path, stroke(white(0.22 * (front + 1) / 2), math.max(1.2 * u, w * 0.18)));
      }
    }
    c.restore();
    f.film.kinetic(f, 'You are woven from', x: 24 * u, y: f.h * 0.625, size: 18 * u, at: 1.2, weight: FontWeight.w600, color: const Color(0xFFF2C6FF));
    final h = f.film.kinetic(f, g.first.name, x: 24 * u, y: f.h * 0.625 + 25 * u, size: 46 * u, at: 1.5, lines: 1, color: _strands[0]);
    var ty = f.h * 0.625 + 36 * u + h;
    for (var k = 0; k < g.length; k++) {
      final at = 2.0 + k * 0.16;
      if (f.t > at) {
        c.drawLine(Offset(24 * u, ty + 10 * u), Offset(24 * u + 34 * u * ramp(f.t, at, at + 0.5), ty + 10 * u), stroke(_strands[k], math.max(4 * u, g[k].pct / total * 16 * u), cap: StrokeCap.round));
      }
      f.film.kinetic(f, g[k].name, x: 72 * u, y: ty, size: 16 * u, at: at, width: f.w - 160 * u, lines: 1, weight: FontWeight.w600);
      if (f.t > at + 0.2) f.film.line(c, '${g[k].pct.round()}%', f.w - 24 * u, ty, 16 * u, align: 1, color: _strands[k]);
      ty += 25 * u;
    }
  }
}

// ── Skyline ─────────────────────────────────────────────────────────────────

/// A city of 24 towers, one an hour, its windows lit by your plays. The sky turns from dawn to night as you drag
/// through the day; the sun and moon ride an arc above it.
class SkylineScene extends FilmScene {
  @override
  String get id => 'clock';
  @override
  String get technique => 'city skyline, one tower an hour, sky from dawn to night';
  @override
  double get length => 8;
  @override
  int get scrubSteps => 24;
  @override
  String why(WrappedData d) => 'One tower for each hour of the day, midnight on the left; the more you played in that hour, the taller it stands and the more windows are lit.';
  @override
  String share(WrappedData d) => 'My music hour of ${d.year}: ${sayHour(d.peakHour)}.';
  @override
  String speech(WrappedData d) => 'Your busiest hour is ${sayHour(d.peakHour)}.';
  @override
  String? get hint => 'Drag through the day';

  /// The sky at hour [h] (0..24): top and bottom.
  static (Color, Color) sky(double h) {
    const stops = [
      (0.0, Color(0xFF050A24), Color(0xFF151A45)),
      (5.0, Color(0xFF14143C), Color(0xFF4A2A6A)),
      (6.5, Color(0xFF3A4CA8), Color(0xFFFF8A5B)),
      (9.0, Color(0xFF1F6FD1), Color(0xFF8FD3FF)),
      (15.0, Color(0xFF1A63C8), Color(0xFFA8E1FF)),
      (18.0, Color(0xFF3A2C8A), Color(0xFFFF6A4D)),
      (19.5, Color(0xFF241B5E), Color(0xFFB83E7A)),
      (21.0, Color(0xFF0A1035), Color(0xFF26245E)),
      (24.0, Color(0xFF050A24), Color(0xFF151A45)),
    ];
    for (var i = 1; i < stops.length; i++) {
      if (h <= stops[i].$1) {
        final k = (h - stops[i - 1].$1) / (stops[i].$1 - stops[i - 1].$1);
        return (Color.lerp(stops[i - 1].$2, stops[i].$2, k)!, Color.lerp(stops[i - 1].$3, stops[i].$3, k)!);
      }
    }
    return (stops.last.$2, stops.last.$3);
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, hourly = f.d.hourly;
    final scrub = f.touch.scrubX;
    final at = scrub != null ? scrub * 23.99 : (f.d.peakHour + 0.5) * ramp(f.t, 0.8, 4.0, Curves.easeInOutSine);
    final hour = at.floor().clamp(0, 23);
    final (top, bottom) = sky(at);
    final ground = f.h * 0.62;
    f.sky(top, const Color(0xFF020308), middle: bottom);
    // sun by day, moon by night, on one arc
    final day = at >= 6 && at < 18.5;
    final arcK = day ? (at - 6) / 12.5 : ((at + 5.5) % 24) / 11.5;
    final body = Offset(f.w * (0.1 + 0.8 * arcK), ground - math.sin(arcK * math.pi) * f.h * 0.3 - 30 * u);
    f.glow(body, 90 * u, (day ? Tone.gold : const Color(0xFFBFD4FF)).withValues(alpha: 0.35));
    if (day) {
      c.drawCircle(body, 22 * u, fill(const Color(0xFFFFE08A)));
    } else {
      c.drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: body, radius: 18 * u)),
          Path()..addOval(Rect.fromCircle(center: body + Offset(8 * u, -5 * u), radius: 15 * u)),
        ),
        fill(const Color(0xFFE8EEFF)),
      );
      for (var i = 0; i < 26; i++) {
        final s = Offset(rnd(i, 21) * f.w, rnd(i, 22) * ground * 0.7);
        c.drawCircle(s, (0.8 + rnd(i, 23)) * u, fill(white(0.4 + 0.4 * math.sin(f.t * 2 + i))));
      }
    }
    // the towers
    final peak = hourly.fold<int>(1, math.max);
    final w = f.w / 24;
    for (var h = 0; h < 24; h++) {
      final rise = ramp(f.t, 0.2 + h * 0.04, 1.0 + h * 0.04, Curves.easeOutBack);
      final share = hourly[h] / peak;
      final th = (40 + 200 * share) * u * rise;
      final x = h * w;
      final hot = h == hour;
      final tower = Rect.fromLTWH(x + 1 * u, ground - th, w - 2 * u, th);
      c.drawRect(tower, fill(hot ? const Color(0xFF2A2140) : const Color(0xFF0D0E1C)));
      if (h % 5 == 2) c.drawLine(Offset(tower.center.dx, tower.top), Offset(tower.center.dx, tower.top - 10 * u), stroke(const Color(0xFF0D0E1C), 1.5 * u));
      // windows: lit in proportion to the plays of that hour, in a fixed order
      final rows = (th / (7 * u)).floor();
      for (var r = 0; r < rows; r++) {
        for (var k = 0; k < 2; k++) {
          final lit = rnd(h * 97 + r * 2 + k, 31) < share * 0.95 + 0.04;
          if (!lit) continue;
          final flick = 0.75 + 0.25 * math.sin(f.t * (1 + rnd(h + r, 3)) + r);
          c.drawRect(Rect.fromLTWH(x + w * (0.18 + k * 0.38), ground - th + 5 * u + r * 7 * u, w * 0.26, 3.6 * u), fill((hot ? Tone.gold : const Color(0xFFFFC870)).withValues(alpha: flick)));
        }
      }
      if (hot) c.drawRect(tower, stroke(Tone.gold, 1.4 * u));
    }
    c.drawRect(Rect.fromLTWH(0, ground, f.w, f.h - ground), fill(const Color(0xFF020308)));
    // the hour, read on the street
    final x = (hour + 0.5) * w;
    c.drawLine(Offset(x, ground + 4 * u), Offset(x, ground + 16 * u), stroke(Tone.gold, 2 * u));
    f.film.line(c, sayHour(hour), x.clamp(40 * u, f.w - 40 * u), ground + 18 * u, 15 * u, align: 0.5, color: Tone.gold);
    f.film.line(c, '${compactCount(hourly[hour])} plays', x.clamp(40 * u, f.w - 40 * u), ground + 37 * u, 12 * u, weight: FontWeight.w600, align: 0.5, color: const Color(0xFFB8BEDC));
    final p = f.d.peakHour;
    final line = p >= 22 || p < 5
        ? 'You come alive after dark.'
        : p < 12
        ? 'You start the day loud.'
        : p < 17
        ? 'Afternoons had a soundtrack.'
        : 'Evenings were yours.';
    f.film.kinetic(f, line, x: 24 * u, y: f.h * 0.76, size: 40 * u, at: 4.0);
  }
}

// ── Ridges ──────────────────────────────────────────────────────────────────

/// Twelve ridgelines under a sunset whose sun is your biggest month's song. Fly along the range; each peak carries its month's song.
class RidgeScene extends FilmScene {
  @override
  String get id => 'journey';
  @override
  String get technique => 'sunset mountain range, the cover as the sun';
  @override
  double get length => 10;
  @override
  int get scrubSteps => 12;
  @override
  String why(WrappedData d) => 'Minutes listened in each month, January furthest away; taller is more. The sun is the top song of your biggest month.';
  @override
  String share(WrappedData d) => '${monthNames[d.busiestMonth!.month - 1]} was my month of ${d.year}.';
  @override
  String speech(WrappedData d) => '${monthNames[d.busiestMonth!.month - 1]} was your biggest month, ${listeningTime(d.busiestMonth!.minutes)}.';
  @override
  String? get hint => 'Drag across the year';

  static const _layers = [Color(0xFF6B2A7C), Color(0xFF5A2470), Color(0xFF4A1F63), Color(0xFF3C1A55), Color(0xFF301648), Color(0xFF26123C)];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, months = f.d.months;
    final peak = months.fold<int>(1, (a, b) => math.max(a, b.minutes));
    final busiest = f.d.busiestMonth!.month - 1;
    final scrub = f.touch.scrubX;
    final sel = scrub != null ? (scrub * 12).floor().clamp(0, 11) : (f.t > 5.6 ? busiest : (ramp(f.t, 1.4, 5.4, Curves.easeInOutSine) * 11.99).floor());
    f.sky(const Color(0xFF1A0B3D), const Color(0xFFFF7A45), middle: const Color(0xFFD9447A));
    final m0 = months[busiest];
    final sunKey = m0.topSong == null || m0.topArtist == null ? null : '${m0.topSong}|${m0.topArtist}';
    final sun = Offset(f.w * 0.5, mix(f.h * 0.27, f.h * 0.34, ramp(f.t, 0, 10, Curves.linear)));
    final r = 96 * u * ramp(f.t, 0, 0.9, Curves.easeOutBack);
    f.glow(sun, r * 2.6, const Color(0x66FFB36B));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: sun, radius: r)));
    c.drawCircle(sun, r, fill(const Color(0xFFFFC46B)));
    f.film.picture(c, sunKey == null ? null : f.assets.covers[sunKey], Rect.fromCircle(center: sun, radius: r));
    for (var i = 0; i < 7; i++) {
      final q = ((i / 7) + f.t * 0.05) % 1;
      c.drawRect(Rect.fromLTWH(sun.dx - r, sun.dy + r * 0.15 + q * r * 0.9, r * 2, 1.5 * u + q * 7 * u), fill(const Color(0xFFD9447A)));
    }
    c.restore();
    const steps = 56;
    Offset? selPeak;
    for (var m = 0; m < 12; m++) {
      final depth = m / 11;
      final base = f.h * 0.39 + depth * f.h * 0.30;
      final rise = ramp(f.t, 0.3 + m * 0.13, 1.4 + m * 0.13, Curves.easeOutBack);
      final high = months[m].minutes / peak * (74 + 34 * depth) * u * rise;
      final peakAt = 0.5 + (rnd(m, 3) - 0.5) * 0.7;
      final path = Path()..moveTo(-8, base + 60 * u);
      var top = Offset(0, base);
      for (var i = 0; i <= steps; i++) {
        final x = i / steps;
        final bell = math.exp(-math.pow((x - peakAt) * 4.6, 2)) + 0.36 * math.exp(-math.pow((x - peakAt - 0.24) * 8, 2)) + 0.28 * math.exp(-math.pow((x - peakAt + 0.27) * 9, 2));
        final crag = (math.sin(x * 47 + m * 5) + math.sin(x * 83 + m * 11)) * 0.045 * bell;
        final p = Offset(x * (f.w + 16) - 8, base - high * (bell + crag) - math.sin(x * 6 + m + f.t * 0.8) * 2.4 * u);
        if (p.dy < top.dy || i == 0) top = p;
        path.lineTo(p.dx, p.dy);
      }
      path
        ..lineTo(f.w + 8, base + 60 * u)
        ..close();
      final hot = m == sel;
      final layer = Color.lerp(_layers[(m * 6 ~/ 12)], const Color(0xFF12081E), depth * 0.6)!;
      c.drawPath(path, fill(hot ? const Color(0xFFFF9F6B) : layer));
      c.drawPath(path, stroke(hot ? const Color(0xFFFFE0C2) : const Color(0x55FFB3C8), (hot ? 2 : 1) * u));
      if (hot) selPeak = top;
    }
    if (selPeak != null && f.t > 1.2) {
      final m = months[sel];
      if (m.topSong != null) {
        // a flag on the summit with that month's song
        c.drawLine(selPeak, selPeak - Offset(0, 34 * u), stroke(kInk, 1.6 * u));
        final label = nice(m.topSong!);
        final tp = f.film.words(f.film.fit(label, 13 * u, 160 * u, 1, FontWeight.w700).$2.first, 13 * u, weight: FontWeight.w700, color: const Color(0xFF2A0F2E));
        final box = Rect.fromLTWH((selPeak.dx - 2 * u).clamp(8 * u, f.w - tp.width - 24 * u), selPeak.dy - 52 * u, tp.width + 14 * u, 22 * u);
        c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(6 * u)), fill(const Color(0xFFFFE0C2)));
        tp.paint(c, box.topLeft + Offset(7 * u, 3 * u));
      }
    }
    c.drawRect(Rect.fromLTWH(0, f.h * 0.715, f.w, f.h), fill(const Color(0xFF12081E)));
    f.film.kinetic(f, '${monthNames[busiest]} was your summit', x: 24 * u, y: f.h * 0.1, size: 32 * u, at: 5.6, lines: 1);
    if (f.t > 1.2) {
      final m = months[sel];
      f.film.line(c, monthNames[sel], 24 * u, f.h * 0.745, 50 * u, weight: FontWeight.w800, width: f.w - 48 * u, color: const Color(0xFFFFC2A0));
      final text = m.minutes == 0 ? 'Quiet.' : [listeningTime(m.minutes), ?m.topGenre, if (m.topSong != null) nice(m.topSong!)].join(' · ');
      final (s, rows) = f.film.fit(text, 17 * u, f.w - 48 * u, 2, FontWeight.w500);
      for (var i = 0; i < rows.length; i++) {
        f.film.line(c, rows[i], 24 * u, f.h * 0.745 + 62 * u + i * s * 1.25, s, weight: FontWeight.w500, color: const Color(0xFFE8C7DA));
      }
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
  String speech(WrappedData d) => 'In ${monthNames[d.story.obsession!.month - 1]} you could not stop playing ${nice(d.story.obsession!.title)}: ${d.story.obsession!.plays} times.';

  static (int, int) _spiral(int i) {
    if (i == 0) return (0, 0);
    final r = ((math.sqrt(i) + 1) / 2).floor();
    final p = i - (2 * r - 1) * (2 * r - 1), leg = 2 * r;
    return switch (p ~/ leg) {
      0 => (r, -r + 1 + p % leg),
      1 => (r - 1 - p % leg, r),
      2 => (-r, r - 1 - p % leg),
      _ => (-r + 1 + p % leg, -r),
    };
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, o = f.d.story.obsession!;
    final key = '${o.title}|${o.artist}';
    final tone = f.tone(key, Tone.coral);
    f.sky(tone.deep, const Color(0xFF000000));
    final total = math.min(400, o.plays);
    final image = f.assets.covers[key];
    final k = ramp(f.t, 1.0, 5.0, Curves.easeInOutSine);
    final n = math.exp(math.log(math.max(1, total)) * k);
    final area = Rect.fromLTWH(0, f.h * 0.1, f.w, f.h * 0.52);
    final cell = math.min(area.width, area.height) / math.max(1, math.sqrt(n));
    final shown = k >= 1 ? total : n.ceil().clamp(1, total);
    f.glow(area.center, area.width * 0.7, tone.vivid.withValues(alpha: 0.35));
    c.save();
    c.clipRect(area);
    final cx = area.center.dx, cy = area.center.dy;
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
        c.drawRect(Rect.fromCenter(center: Offset(cx + gx * cell, cy + gy * cell), width: cell - 2 * u, height: cell - 2 * u), fill(Color.lerp(tone.base, tone.vivid, rnd(i, 3))!));
      }
    }
    c.restore();
    final y = f.h * 0.655;
    f.film.kinetic(f, 'In ${monthNames[o.month - 1]} you were obsessed', x: 24 * u, y: y, size: 18 * u, at: 0.6, weight: FontWeight.w600, color: tone.light, lines: 1);
    final h = f.film.kinetic(f, nice(o.title), x: 24 * u, y: y + 26 * u, size: 38 * u, at: 0.9);
    // the count is the tiles on screen, never ahead of them
    final tp = f.film.words('${k >= 1 ? o.plays : shown} times', 56 * u, color: tone.light);
    if (f.t > 1.0) tp.paint(c, Offset(24 * u, y + 32 * u + h));
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
    f.sky(b ? const Color(0xFF0D2E4A) : const Color(0xFF0D3B3E), const Color(0xFF020809));
    f.glow(Offset(f.w / 2, f.h * 0.36), 220 * u, (b ? Tone.azure : Tone.teal).withValues(alpha: 0.3));
    final wind = clamp01(b ? (f.t - 5.4) / 4.6 : (f.t - 0.6) / 4.2);
    c.save();
    c.translate(f.w / 2, f.h * 0.36 - math.sin(flip * math.pi) * 40 * u);
    c.rotate(-0.05 + math.sin(f.t * 1.3) * 0.012);
    final enter = ramp(f.t, 0, 0.8, Curves.easeOutBack);
    c.scale(math.max(0.03, math.cos(flip * math.pi).abs()) * enter, enter);
    final box = Rect.fromCenter(center: Offset.zero, width: 310 * u, height: 196 * u);
    final shell = b ? Tone.azure : Tone.coral;
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(14 * u)), Paint()..shader = ui.Gradient.linear(box.topLeft, box.bottomRight, [shell, Color.lerp(shell, const Color(0xFF000000), 0.35)!]));
    for (final s in [const Offset(-1, -1), const Offset(1, -1), const Offset(-1, 1), const Offset(1, 1)]) {
      c.drawCircle(Offset(s.dx * 144 * u, s.dy * 87 * u), 3.5 * u, fill(const Color(0x66000000)));
    }
    final label = Rect.fromLTRB(-136 * u, -84 * u, 136 * u, 50 * u);
    c.drawRRect(RRect.fromRectAndRadius(label, Radius.circular(7 * u)), fill(Tone.cream));
    for (var i = 0; i < 3; i++) {
      c.drawLine(Offset(label.left + 42 * u, label.top + 56 * u + i * 9 * u), Offset(label.right - 12 * u, label.top + 56 * u + i * 9 * u), stroke(const Color(0x33000000), 1 * u));
    }
    f.film.line(c, b ? 'B' : 'A', label.left + 10 * u, label.top + 5 * u, 30 * u, weight: FontWeight.w800, color: shell);
    f.film.line(c, nice(play.title), label.left + 42 * u, label.top + 9 * u, 21 * u, color: const Color(0xFF111111), width: 222 * u);
    f.film.line(c, play.artist, label.left + 42 * u, label.top + 34 * u, 13 * u, weight: FontWeight.w500, color: const Color(0xFF48484A), width: 222 * u);
    final window = RRect.fromRectAndRadius(Rect.fromLTRB(-100 * u, -22 * u, 100 * u, 38 * u), Radius.circular(30 * u));
    c.drawRRect(window, fill(const Color(0xFF1A1410)));
    c.save();
    c.clipRRect(window);
    for (final left in [true, false]) {
      final hub = Offset((left ? -62 : 62) * u, 8 * u);
      final share = left ? 1 - wind : wind;
      c.drawCircle(hub, (22 + 34 * share) * u, fill(const Color(0xFF4A2E1C)));
      c.drawCircle(hub, 19 * u, fill(Tone.cream));
      c.drawCircle(hub, 11 * u, fill(const Color(0xFF1A1410)));
      final a0 = f.t * 5 / (0.6 + share) + f.touch.spin * 3;
      for (var i = 0; i < 6; i++) {
        final a = a0 + i * kTau / 6;
        c.drawLine(hub + Offset.fromDirection(a, 10 * u), hub + Offset.fromDirection(a, 5.5 * u), stroke(Tone.cream, 3 * u));
      }
    }
    c.restore();
    final foot = Path()
      ..moveTo(-96 * u, 98 * u)
      ..lineTo(-84 * u, 62 * u)
      ..lineTo(84 * u, 62 * u)
      ..lineTo(96 * u, 98 * u);
    c.drawPath(foot, fill(const Color(0x33000000)));
    c.restore();
    final y = f.h * 0.62;
    final local = b ? f.at(f.t - 5.2) : f;
    f.film.kinetic(local, b ? 'And most recently' : 'It all began with', x: 24 * u, y: y, size: 18 * u, at: b ? 0.1 : 0.8, weight: FontWeight.w600, color: b ? const Color(0xFFA9DBFF) : const Color(0xFFA6F0E6));
    final h = f.film.kinetic(local, nice(play.title), x: 24 * u, y: y + 26 * u, size: 44 * u, at: b ? 0.3 : 1.1);
    f.film.kinetic(local, '${play.artist} · ${sayDate(play.at.split(' ').first)}', x: 24 * u, y: y + 34 * u + h, size: 17 * u, at: b ? 0.6 : 1.5, weight: FontWeight.w500, color: b ? const Color(0xFFA9DBFF) : const Color(0xFFA6F0E6));
  }
}

// ── Film reel ───────────────────────────────────────────────────────────────

/// The people who wrote it, on a strip of film in front of a red curtain. It runs and slows to a stop. Pull it.
class ReelScene extends FilmScene {
  @override
  String get id => 'composers';
  @override
  String get technique => 'running film strip before a curtain';
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
    final c = f.canvas, u = f.u, list = f.d.story.composers.take(6).toList();
    // the curtain
    for (var i = 0; i < 12; i++) {
      final x = i / 12 * f.w;
      c.drawRect(
        Rect.fromLTWH(x, 0, f.w / 12 + 1, f.h),
        Paint()..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + f.w / 12, 0), const [Color(0xFF4A0612), Color(0xFF8E1428), Color(0xFF4A0612)], const [0, 0.5, 1]),
      );
    }
    f.glow(Offset(f.w / 2, f.h * 0.35), f.w * 0.75, const Color(0x66FFD27A));
    final fh = 172 * u, fw = 236 * u;
    final travel = (1 - ramp(f.t, 0.2, 4.2, Curves.easeOutQuart)) * list.length * 3 * fh - f.touch.spin * 90 * u;
    final mid = f.h * 0.4, left = f.w / 2 - fw / 2;
    final speed = math.max(0.0, 4.2 - f.t) / 4.2;
    c.save();
    c.translate(math.sin(f.t * 40) * speed * 2 * u, 0);
    c.drawRect(Rect.fromLTWH(left - 30 * u, 0, fw + 60 * u, f.h), fill(const Color(0xFF121012)));
    final hole = 21.5 * u;
    final shift = (travel % hole + hole) % hole;
    for (var y = -hole + shift; y < f.h + hole; y += hole) {
      for (final x in [left - 22 * u, left + fw + 8 * u]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 14 * u, 11 * u), Radius.circular(3 * u)), fill(const Color(0xFFE8D9B8)));
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
      c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(6 * u)), fill(Color.lerp(const Color(0xFF2A2026), const Color(0xFFFFD27A), near)!));
      final ink = near > 0.5 ? const Color(0xFF2A0A10) : const Color(0xFFF6EBD6);
      f.film.line(c, '$rank', box.left + 14 * u, box.top + 8 * u, 40 * u, weight: FontWeight.w800, color: ink);
      final (s, rows) = f.film.fit(who.name, 29 * u, fw - 28 * u, 2, FontWeight.w800);
      for (var r = 0; r < rows.length; r++) {
        f.film.line(c, rows[r], box.left + 14 * u, box.bottom - 34 * u - (rows.length - r) * s * 1.06, s, weight: FontWeight.w800, color: ink, width: fw - 28 * u);
      }
      f.film.line(c, '${who.plays} plays · ${who.songs} ${who.songs == 1 ? 'song' : 'songs'}', box.left + 14 * u, box.bottom - 27 * u, 14 * u, weight: FontWeight.w600, color: ink.withValues(alpha: 0.75), width: fw - 28 * u);
    }
    c.restore();
    c.drawRect(Rect.fromLTWH(0, f.h * 0.735, f.w, f.h), Paint()..shader = ui.Gradient.linear(Offset(0, f.h * 0.735), Offset(0, f.h), const [Color(0xFF2A0309), Color(0xFF0A0003)]));
    f.film.kinetic(f, 'Music by', x: 24 * u, y: f.h * 0.755, size: 18 * u, at: 3.0, weight: FontWeight.w600, color: const Color(0xFFFFD27A));
    f.film.kinetic(f, list.first.name, x: 24 * u, y: f.h * 0.755 + 25 * u, size: 46 * u, at: 3.2);
  }
}

// ── Stamps ──────────────────────────────────────────────────────────────────

/// A blue passport page. Every language you listened in comes down as its own coloured stamp.
class StampsScene extends FilmScene {
  @override
  String get id => 'languages';
  @override
  String get technique => 'passport page and inked stamps';
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
  static const _inks = [Color(0xFFFF6B8B), Color(0xFFFFC14D), Color(0xFF5EE6D0), Color(0xFFB79CFF), Color(0xFFFF9E5E), Color(0xFF7CC4FF)];

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, list = f.d.story.languages.take(6).toList();
    f.sky(const Color(0xFF0E2156), const Color(0xFF060E2A));
    var shake = 0.0;
    for (var i = 0; i < list.length; i++) {
      final since = f.t - (1.0 + i * 0.75);
      if (since > 0 && since < 0.25) shake = (1 - since / 0.25) * math.sin(since * 90) * 5 * u;
    }
    c.save();
    c.translate(shake, shake * 0.6);
    for (var k = 0; k < 13; k++) {
      final path = Path();
      for (var i = 0; i <= 60; i++) {
        final x = i / 60 * f.w;
        final y = f.h * (0.14 + k * 0.047) + math.sin(i * 0.42 + k * 0.8 + f.t * 0.25) * 11 * u;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      c.drawPath(path, stroke(const Color(0xFF2A4590), 1 * u));
    }
    for (var i = 0; i < list.length; i++) {
      final at = 1.0 + i * 0.75;
      if (f.t < at - 0.2) continue;
      final k = ramp(f.t, at - 0.2, at, Curves.easeInQuad);
      final r = (46 + 34 * math.sqrt(list[i].pct / math.max(1, list.first.pct))) * u;
      c.save();
      c.translate(f.w * _spots[i].dx, f.h * _spots[i].dy);
      c.rotate((rnd(i, 7) - 0.5) * 0.7 + (1 - k) * 0.5 + f.touch.tiltX * 0.2);
      c.scale(mix(3.2, 1, k) * (1 + 0.06 * math.sin(math.pi * clamp01((f.t - at) / 0.3))));
      _stamp(f, i, list[i], r, _inks[i].withValues(alpha: k * 0.95));
      c.restore();
    }
    c.restore();
    f.film.kinetic(f, '${list.first.name} ran through it all', x: 24 * u, y: f.h * 0.775, size: 38 * u, at: 1.4 + list.length * 0.6, color: _inks[0]);
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

// ── Weather ─────────────────────────────────────────────────────────────────

/// The forecast of your moods, under the sky of the main one.
class WeatherScene extends FilmScene {
  @override
  String get id => 'moods';
  @override
  String get technique => 'weather report';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'The server’s mood labels on your most played songs, by plays. Songs without a label are not counted.';
  @override
  String share(WrappedData d) => 'My ${d.year} forecast: mostly ${d.story.moods.first.name}.';
  @override
  String speech(WrappedData d) => 'Your moods: ${[for (final m in d.story.moods.take(4)) '${m.name} ${m.pct.round()} percent'].join(', ')}.';

  static int sky(String mood) {
    final m = mood.toLowerCase();
    if (RegExp('sad|melanch|heart|lonely|emotional').hasMatch(m)) return 1;
    if (RegExp('party|energ|hype|mass|angry|power|dance|work').hasMatch(m)) return 2;
    if (RegExp('chill|calm|relax|sleep|peace|night|focus|devot|spirit').hasMatch(m)) return 3;
    if (RegExp('roman|love').hasMatch(m)) return 4;
    return 0;
  }

  static const _skies = [
    (Color(0xFF1E6FD9), Color(0xFFFFB340)), // sun
    (Color(0xFF233249), Color(0xFF5B7390)), // rain
    (Color(0xFF1C0B3A), Color(0xFF5A2A8A)), // storm
    (Color(0xFF070B2A), Color(0xFF1F2A66)), // night
    (Color(0xFF5A1238), Color(0xFFFF7A8A)), // warm wind
  ];

  void _icon(FilmFrame f, int sky, Offset at, double r, double t) {
    final c = f.canvas;
    final pen = stroke(kInk, math.max(1.2, r * 0.05), cap: StrokeCap.round);
    void cloud(Offset o, double s, Color col) {
      final p = Path()
        ..addOval(Rect.fromCircle(center: o + Offset(-s * 0.55, 0), radius: s * 0.45))
        ..addOval(Rect.fromCircle(center: o + Offset(0, -s * 0.3), radius: s * 0.62))
        ..addOval(Rect.fromCircle(center: o + Offset(s * 0.6, 0), radius: s * 0.42))
        ..addRect(Rect.fromLTRB(o.dx - s * 0.55, o.dy, o.dx + s * 0.6, o.dy + s * 0.43));
      c.drawPath(p, fill(col));
    }

    switch (sky) {
      case 0:
        c.drawCircle(at, r * 0.46, fill(const Color(0xFFFFD54A)));
        for (var i = 0; i < 14; i++) {
          final a = i / 14 * kTau + t * 0.3;
          c.drawLine(at + Offset.fromDirection(a, r * 0.6), at + Offset.fromDirection(a, r * (0.78 + 0.16 * math.sin(t * 3 + i * 2.2))), stroke(const Color(0xFFFFD54A), pen.strokeWidth, cap: StrokeCap.round));
        }
      case 1:
        for (var i = 0; i < 13; i++) {
          final q = (t * 1.2 + rnd(i, 4)) % 1;
          final p = at + Offset((rnd(i, 5) - 0.5) * r * 1.5 - q * r * 0.14, r * 0.2 + q * r * 0.85);
          c.drawLine(p, p + Offset(-r * 0.04, r * 0.17), stroke(const Color(0xFF9FD3FF).withValues(alpha: 1 - q * 0.6), pen.strokeWidth, cap: StrokeCap.round));
        }
        cloud(at + Offset(math.sin(t * 0.8) * r * 0.06, -r * 0.15), r * 0.8, const Color(0xFFD5DEEA));
      case 2:
        final flash = math.sin(t * 2.6) > 0.86 || math.sin(t * 4.1) > 0.95;
        cloud(at + Offset(0, -r * 0.25), r * 0.8, const Color(0xFFB8A6D9));
        final bolt = Path()
          ..moveTo(at.dx + r * 0.12, at.dy + r * 0.12)
          ..lineTo(at.dx - r * 0.22, at.dy + r * 0.52)
          ..lineTo(at.dx + r * 0.02, at.dy + r * 0.52)
          ..lineTo(at.dx - r * 0.1, at.dy + r * 0.95)
          ..lineTo(at.dx + r * 0.3, at.dy + r * 0.4)
          ..lineTo(at.dx + r * 0.06, at.dy + r * 0.4)
          ..close();
        c.drawPath(bolt, flash ? fill(const Color(0xFFFFE45C)) : stroke(const Color(0xFFFFE45C), pen.strokeWidth));
      case 3:
        c.drawPath(
          Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: at, radius: r * 0.68)), Path()..addOval(Rect.fromCircle(center: at + Offset(r * 0.34, -r * 0.16), radius: r * 0.58))),
          fill(const Color(0xFFE8EEFF)),
        );
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
          c.drawPath(p, stroke(const Color(0xFFFFC2CC), pen.strokeWidth, cap: StrokeCap.round));
        }
    }
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, moods = f.d.story.moods.take(5).toList(), first = moods.first;
    final s = sky(first.name);
    f.sky(_skies[s].$1, const Color(0xFF05050A), middle: Color.lerp(_skies[s].$2, const Color(0xFF05050A), 0.35));
    final k = ramp(f.t, 0.2, 1.2, Curves.easeOutBack);
    _icon(f, s, Offset(f.w / 2, f.h * 0.3), 112 * u * math.max(0.01, k), f.t);
    f.film.kinetic(f, 'Mostly', x: 24 * u, y: f.h * 0.53, size: 18 * u, at: 1.0, weight: FontWeight.w600, color: const Color(0xFFE6ECFF));
    final h = f.film.kinetic(f, first.name, x: 24 * u, y: f.h * 0.53 + 24 * u, size: 62 * u, at: 1.2, lines: 1);
    var y = f.h * 0.53 + 40 * u + h;
    for (var i = 0; i < moods.length; i++) {
      final at = 2.2 + i * 0.22, kk = ramp(f.t, at, at + 0.6, Curves.easeOutCubic);
      if (kk <= 0) continue;
      c.save();
      c.translate((1 - kk) * 60 * u, 0);
      _icon(f, sky(moods[i].name), Offset(40 * u, y + 11 * u), 14 * u, f.t + i);
      f.film.line(c, moods[i].name, 72 * u, y, 18 * u, weight: FontWeight.w600, width: f.w - 170 * u);
      f.film.line(c, '${moods[i].pct.round()}%', f.w - 24 * u, y, 18 * u, align: 1, color: const Color(0xFFE6ECFF));
      c.restore();
      y += 37 * u;
    }
  }
}

// ── Tuner ───────────────────────────────────────────────────────────────────

/// A valve radio's amber dial of years. The needle hunts through static and locks on when your music was made. Turn it.
class TunerScene extends FilmScene {
  @override
  String get id => 'era';
  @override
  String get technique => 'valve radio dial and static';
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

  static const _amber = Color(0xFFFFB627);

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, e = f.d.story.era!;
    f.sky(const Color(0xFF3A1A08), const Color(0xFF0E0602));
    final lock = ramp(f.t, 0.6, 4.0, Curves.easeInOutQuart);
    final year = mix(e.oldest - 6.0, e.middle.toDouble(), lock) + math.sin(f.t * 3.1) * 14 * (1 - lock) - f.touch.spin * 8;
    final off = clamp01((year - e.middle).abs() / 9);
    // the cabinet
    final cab = RRect.fromRectAndRadius(Rect.fromLTWH(14 * u, f.h * 0.12, f.w - 28 * u, f.h * 0.55), Radius.circular(26 * u));
    c.drawRRect(cab, Paint()..shader = ui.Gradient.linear(cab.outerRect.topLeft, cab.outerRect.bottomLeft, const [Color(0xFF8A4A1C), Color(0xFF4E2408)]));
    c.drawRRect(cab.deflate(8 * u), stroke(const Color(0x40FFD9A0), 1.5 * u));
    final screen = Rect.fromLTWH(34 * u, f.h * 0.15, f.w - 68 * u, f.h * 0.22);
    c.save();
    c.clipRRect(RRect.fromRectAndRadius(screen, Radius.circular(16 * u)));
    c.drawRect(screen, fill(const Color(0xFF1A0E04)));
    f.glow(screen.center, screen.width * 0.6, _amber.withValues(alpha: 0.25 * (1 - off) + 0.08));
    final tick = (f.t * 14).floor();
    for (var i = 0; i < 22; i++) {
      final y = screen.top + screen.height * (i + 0.5) / 22;
      final x = screen.left + rnd(i + tick * 31, 1) * screen.width;
      c.drawRect(Rect.fromLTWH(x, y - 2 * u, screen.width * (0.1 + 0.5 * rnd(i + tick * 17, 2)), 4 * u), fill(_amber.withValues(alpha: 0.5 * off * rnd(i + tick * 13, 3))));
    }
    final tp = f.film.words('${year.round()}', 104 * u, color: Color.lerp(_amber, const Color(0xFFFFE6B0), 1 - off)!);
    for (var i = 0; i < 6; i++) {
      c.save();
      c.clipRect(Rect.fromLTWH(screen.left, screen.top + screen.height * i / 6, screen.width, screen.height / 6 + 0.5));
      tp.paint(c, Offset(screen.center.dx - tp.width / 2 + math.sin(f.t * 19 + i * 2.4) * off * 34 * u, screen.center.dy - tp.height / 2));
      c.restore();
    }
    c.restore();
    c.drawRRect(RRect.fromRectAndRadius(screen, Radius.circular(16 * u)), stroke(const Color(0x66FFD9A0), 1.4 * u));
    // the scale slides under a fixed needle, lit from behind
    final y = f.h * 0.46;
    final band = Rect.fromLTWH(34 * u, y - 46 * u, f.w - 68 * u, 74 * u);
    c.drawRRect(RRect.fromRectAndRadius(band, Radius.circular(10 * u)), fill(const Color(0xFFF2D9A6)));
    c.save();
    c.clipRect(band);
    for (var k = (year - 13).floor(); k <= (year + 13).ceil(); k++) {
      final x = f.w / 2 + (k - year) * 17 * u;
      final ten = k % 10 == 0, five = k % 5 == 0;
      c.drawLine(Offset(x, y), Offset(x, y - (ten ? 30 : (five ? 20 : 11)) * u), stroke(const Color(0xFF3A1A08), (ten ? 2.4 : 1.2) * u));
      if (ten) f.film.line(c, '$k', x, y + 6 * u, 14 * u, weight: FontWeight.w700, align: 0.5, color: const Color(0xFF3A1A08));
    }
    c.restore();
    c.drawLine(Offset(f.w / 2, band.top - 4 * u), Offset(f.w / 2, band.bottom + 4 * u), stroke(const Color(0xFFE5383B), 3 * u, cap: StrokeCap.round));
    // the knobs
    for (final (x, turn) in [(f.w * 0.3, year * 0.16), (f.w * 0.7, -f.t * 0.3)]) {
      final knob = Offset(x, f.h * 0.6);
      c.drawCircle(knob, 30 * u, fill(const Color(0xFFF2E3C4)));
      c.drawCircle(knob, 30 * u, stroke(const Color(0xFF3A1A08), 2 * u));
      for (var i = 0; i < 20; i++) {
        final a = i / 20 * kTau + turn;
        c.drawLine(knob + Offset.fromDirection(a, 30 * u), knob + Offset.fromDirection(a, 25 * u), stroke(const Color(0x993A1A08), 1.4 * u));
      }
      c.drawCircle(knob + Offset.fromDirection(turn - math.pi / 2, 18 * u), 4 * u, fill(const Color(0xFF3A1A08)));
    }
    f.film.kinetic(f, 'Your music was made around ${e.middle}', x: 24 * u, y: f.h * 0.715, size: 38 * u, at: 3.6, color: const Color(0xFFFFE6B0));
    f.film.kinetic(f, 'From ${nice(e.oldestTitle)} (${e.oldest}) to ${nice(e.newestTitle)} (${e.newest})', x: 24 * u, y: f.h * 0.715 + 92 * u, size: 16 * u, at: 4.4, weight: FontWeight.w500, color: const Color(0xFFE8C9A0), lines: 3, stagger: 0.04);
  }
}

// ── Faders ──────────────────────────────────────────────────────────────────

/// A mixing desk under neon: seven channels, one a day, ridden up to your week.
class FadersScene extends FilmScene {
  @override
  String get id => 'week';
  @override
  String get technique => 'mixing desk, faders and neon meters';
  @override
  double get length => 7.5;
  @override
  String why(WrappedData d) => 'Average minutes on each weekday, over the days you listened.';
  @override
  String share(WrappedData d) => '${_days[top(d)]} is my music day.';
  @override
  String speech(WrappedData d) => '${_days[top(d)]} was your loudest day, ${listeningTime(d.story.week[top(d)])} on average.';
  @override
  String? get hint => 'Tap for a drum hit';

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static int top(WrappedData d) {
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (d.story.week[i] > d.story.week[best]) best = i;
    }
    return best;
  }

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, week = f.d.story.week;
    final best = top(f.d), peak = math.max(1, week[best]);
    f.sky(const Color(0xFF0E0A22), const Color(0xFF040309));
    f.glow(Offset(f.w / 2, f.h * 0.5), f.w * 0.8, Tone.magenta.withValues(alpha: 0.12));
    f.film.kinetic(f, '${_days[best]} was turned all the way up', x: 24 * u, y: f.h * 0.115, size: 34 * u, at: 3.0);
    final y0 = f.h * 0.275, h = f.h * 0.47, w = (f.w - 24 * u) / 7;
    for (var i = 0; i < 7; i++) {
      final x = 12 * u + (i + 0.5) * w;
      final settle = ramp(f.t, 1.2 + i * 0.14, 2.6 + i * 0.14, Curves.easeOutBack);
      final v = clamp01(mix(0.5 + 0.38 * math.sin(f.t * 3.4 + i * 1.7), week[i] / peak, settle));
      final hot = i == best && settle > 0.9;
      c.drawLine(Offset(x + 8 * u, y0), Offset(x + 8 * u, y0 + h), stroke(const Color(0xFF2A2640), 4 * u, cap: StrokeCap.round));
      final level = clamp01(v * (0.72 + 0.28 * math.sin(f.t * 11 + i * 2.3).abs()) + f.touch.punch() * 0.5);
      for (var k = 0; k < 18; k++) {
        final q = k / 18;
        final on = q < level;
        final led = Color.lerp(Tone.teal, Tone.magenta, q)!;
        c.drawRect(Rect.fromLTWH(x - 15 * u, y0 + h - (k + 1) * h / 18 + 1.5 * u, 10 * u, h / 18 - 3 * u), fill(on ? led : const Color(0xFF16142A)));
      }
      final ky = y0 + h * (1 - v);
      final cap = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + 8 * u, ky), width: 24 * u, height: 40 * u), Radius.circular(5 * u));
      c.drawRRect(cap, fill(hot ? Tone.magenta : const Color(0xFFE9E4FF)));
      c.drawRRect(cap, stroke(const Color(0xFF000000), 2 * u));
      c.drawLine(Offset(x - 3 * u, ky), Offset(x + 19 * u, ky), stroke(hot ? kInk : const Color(0xFF1A1630), 2 * u));
      f.film.line(c, _days[i].substring(0, 1), x, y0 + h + 22 * u, 17 * u, weight: hot ? FontWeight.w800 : FontWeight.w600, align: 0.5, color: hot ? Tone.magenta : const Color(0xFFB9B4D9));
      if (f.t > 3.2 + i * 0.08) {
        f.film.line(c, week[i] >= 60 ? '${(week[i] / 60).toStringAsFixed(1)}h' : '${week[i]}m', x, y0 + h + 46 * u, 12.5 * u, weight: FontWeight.w600, align: 0.5, color: hot ? kInk : const Color(0xFFB9B4D9));
      }
    }
    f.film.kinetic(f, '${listeningTime(week[best])} on an average ${_days[best]}', x: 24 * u, y: f.h * 0.865, size: 17 * u, at: 3.8, weight: FontWeight.w500, color: const Color(0xFFB9B4D9), lines: 1);
  }
}

// ── Calendar ────────────────────────────────────────────────────────────────

/// The year's calendar glows day by day like coals, then a flame runs through your longest streak.
class CalendarScene extends FilmScene {
  @override
  String get id => 'streak';
  @override
  String get technique => 'calendar of embers and a running flame';
  @override
  double get length => 8;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) => 'Every square is a day with music; hotter had more minutes. The flame runs your longest run of days in a row.';
  @override
  String share(WrappedData d) => 'My longest streak of ${d.year}: ${d.longestStreak} days.';
  @override
  String speech(WrappedData d) => 'Your longest streak was ${d.longestStreak} days, ${sayDate(d.streakStart)} to ${sayDate(d.streakEnd)}.';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, d = f.d;
    f.sky(const Color(0xFF1A0806), const Color(0xFF050101));
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
      final k = DateTime.utc(d.year, m).weekday - 1 + dd - 1;
      return Offset(24 * u + ((m - 1) % 3) * mw + (k % 7 + 0.5) * cell, f.h * 0.115 + ((m - 1) ~/ 3) * mh + 18 * u + (k ~/ 7 + 0.5) * cell);
    }

    final drawn = ramp(f.t, 0.2, 3.0, Curves.easeInOutSine) * 372;
    for (var m = 1; m <= 12; m++) {
      f.film.line(c, monthNames[m - 1].substring(0, 3), 24 * u + ((m - 1) % 3) * mw + 1 * u, f.h * 0.115 + ((m - 1) ~/ 3) * mh, 12.5 * u, weight: FontWeight.w700, color: const Color(0xFFFFB38A));
      final last = DateTime.utc(d.year, m + 1, 0).day;
      for (var dd = 1; dd <= last; dd++) {
        final order = (m - 1) * 31 + dd;
        if (order > drawn) break;
        final v = by[m * 32 + dd];
        final pass = f.t < 5.6 ? 99.0 : ((f.t - 5.6) * 190 - order).abs();
        final pop = clamp01(math.min((drawn - order) / 12, pass / 14));
        final s = (cell - 2 * u) * (v == null ? 1 : mix(1.5, 1, pop));
        final heat = v == null ? 0.0 : math.sqrt(v / peak);
        final shade = v == null
            ? const Color(0xFF241210)
            : heat < 0.5
            ? Color.lerp(const Color(0xFF6A1A0C), Tone.ember, heat * 2)!
            : Color.lerp(Tone.ember, const Color(0xFFFFE08A), (heat - 0.5) * 2)!;
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: day(m, dd), width: s, height: s), Radius.circular(1.5 * u)), fill(shade));
      }
    }
    final start = DateTime.tryParse(d.streakStart ?? ''), end = DateTime.tryParse(d.streakEnd ?? '');
    final pen = ramp(f.t, 3.2, 5.4, Curves.easeInOutCubic);
    if (start != null && end != null && pen > 0) {
      final s0 = DateTime.utc(start.year, start.month, start.day);
      final n = DateTime.utc(end.year, end.month, end.day).difference(s0).inDays + 1;
      final upto = (n * pen).ceil();
      for (var i = 0; i < upto; i++) {
        final t = s0.add(Duration(days: i));
        final p = day(t.month, t.day);
        // a tongue of flame on each day of the run, flickering, hottest at the head
        final head = i == upto - 1;
        final hgt = cell * (1.3 + 0.5 * math.sin(f.t * 13 + i * 1.9).abs() + (head ? 0.8 : 0));
        final flame = Path()
          ..moveTo(p.dx - cell * 0.42, p.dy + cell * 0.42)
          ..quadraticBezierTo(p.dx - cell * 0.5, p.dy - hgt * 0.3, p.dx + math.sin(f.t * 9 + i) * cell * 0.15, p.dy - hgt)
          ..quadraticBezierTo(p.dx + cell * 0.5, p.dy - hgt * 0.3, p.dx + cell * 0.42, p.dy + cell * 0.42)
          ..close();
        c.drawPath(flame, Paint()..shader = ui.Gradient.linear(Offset(p.dx, p.dy + cell * 0.4), Offset(p.dx, p.dy - hgt), const [Color(0xFFFF4A1C), Color(0xFFFFB627), Color(0xFFFFF4C2)], const [0, 0.55, 1]));
      }
    }
    final y = f.h * 0.685;
    final w = f.film.counter(f, d.longestStreak, (v) => '$v', x: 24 * u, y: y, size: 108 * u, from: 3.2, to: 5.4, width: 200 * u, color: const Color(0xFFFFC46B));
    f.film.kinetic(f, d.longestStreak == 1 ? 'day' : 'days in a row', x: 36 * u + w, y: y + 48 * u, size: 26 * u, at: 4.0, width: f.w - 60 * u - w);
    f.film.kinetic(f, '${sayDate(d.streakStart)} to ${sayDate(d.streakEnd)}, not one missed', x: 24 * u, y: y + 126 * u, size: 17 * u, at: 5.2, weight: FontWeight.w500, color: const Color(0xFFFFB38A));
  }
}
