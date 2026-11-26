import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/format.dart';
import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes.dart';

// What it says about you.

// ── Scoreboard ──────────────────────────────────────────────────────────────

/// A stadium scoreboard of bulbs: the months one artist stayed, and who came back.
class ScoreboardScene extends FilmScene {
  @override
  String get id => 'loyalty';
  @override
  String get technique => 'stadium bulb scoreboard';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) =>
      'The artist who was in your top artists in the most months. A comeback left those lists for at least two months and returned.';
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
    f.film.kinetic(f, 'They never left', x: 24 * u, y: f.h * 0.115, size: 36 * u, at: 0.1, lines: 1);
    final board = Rect.fromLTWH(16 * u, f.h * 0.195, f.w - 32 * u, f.h * 0.33);
    c.drawRRect(RRect.fromRectAndRadius(board, Radius.circular(12 * u)), fill(const Color(0xFF0E0E0F)));
    // the frame's bulbs chase
    final path = Path()..addRRect(RRect.fromRectAndRadius(board.deflate(7 * u), Radius.circular(8 * u)));
    for (final m in path.computeMetrics()) {
      final n = (m.length / (15 * u)).floor();
      for (var i = 0; i < n; i++) {
        final p = m.getTangentForOffset(m.length * i / n)!.position;
        final on = (i + (f.t * 9).floor()) % 3 == 0;
        c.drawCircle(p, 2.6 * u, fill(on ? kInk : const Color(0xFF3A3A3C)));
      }
    }
    final lit = ramp(f.t, 1.0, 4.0, Curves.linear) * 12;
    var score = 0;
    final w = (board.width - 48 * u) / 6;
    for (var m = 1; m <= 12; m++) {
      final here = l.months.contains(m) && m <= lit;
      if (here) score++;
      final p = Offset(board.left + 24 * u + ((m - 1) % 6 + 0.5) * w, board.top + (m <= 6 ? 0.36 : 0.74) * board.height);
      final pop = here ? 1 + 0.35 * clamp01(1 - (lit - m)) : 1.0;
      c.drawCircle(p, 17 * u * pop, fill(here ? kInk : const Color(0xFF1C1C1E)));
      if (here) {
        for (var k = 0; k < 8; k++) {
          final a = k / 8 * kTau;
          c.drawLine(p + Offset.fromDirection(a, 21 * u), p + Offset.fromDirection(a, 25 * u), stroke(white(0.7), 1.6 * u, cap: StrokeCap.round));
        }
      }
      f.film.line(c, monthNames[m - 1].substring(0, 3), p.dx, p.dy - 6.5 * u, 11 * u, weight: FontWeight.w800, align: 0.5, color: here ? kBlack : const Color(0xFF8E8E93));
    }
    final y = f.h * 0.555;
    f.film.picture(c, f.assets.people[l.name], Rect.fromLTWH(24 * u, y, 92 * u, 92 * u), radius: 46 * u, tile: true);
    f.film.kinetic(f, l.name, x: 132 * u, y: y + 2 * u, size: 31 * u, at: 1.0, width: f.w - 156 * u);
    if (f.t > 1.2) f.film.line(c, '$score of 12 months', 132 * u, y + 70 * u, 18 * u, color: kDim);
    if (back != null) {
      // a boomerang: thrown out, round, and home
      final k = ramp(f.t, 4.2, 6.2, Curves.easeInOutCubic);
      final by = f.h * 0.755;
      final arc = Path();
      for (var i = 0; i <= 40; i++) {
        final a = math.pi * (0.5 + 2 * i / 40);
        final p = Offset(f.w / 2 + math.cos(a) * (f.w / 2 - 36 * u), by + 8 * u + math.sin(a) * 17 * u);
        i == 0 ? arc.moveTo(p.dx, p.dy) : arc.lineTo(p.dx, p.dy);
      }
      for (final m in arc.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * k), stroke(white(0.35), 1.6 * u));
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
            stroke(kInk, 6 * u, cap: StrokeCap.round),
          );
          c.restore();
        }
      }
      f.film.kinetic(f, '${back.name} went away for ${back.gap} months and came back in ${monthNames[back.month - 1]}', x: 24 * u, y: by + 36 * u, size: 19 * u, at: 5.2, weight: FontWeight.w600, lines: 3, stagger: 0.05);
    }
  }
}

// ── Ticket ──────────────────────────────────────────────────────────────────

/// Admit one, to your biggest day. Pull it and it tears.
class TicketScene extends FilmScene {
  @override
  String get id => 'best-day';
  @override
  String get technique => 'printed ticket that tears';
  @override
  double get length => 8;
  @override
  String why(WrappedData d) => 'Your day with the most minutes, next to your average over the days you listened.';
  @override
  String share(WrappedData d) => 'My biggest music day of ${d.year}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String speech(WrappedData d) => 'Your biggest day was ${sayDate(d.bestDay!.date)}: ${listeningTime(d.bestDay!.minutes)}.';
  @override
  String? get hint => 'Tap to tear it';
  @override
  double? tap(FilmFrame f, Offset p) => f.t < 4.4 ? 4.4 : null;

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, best = f.d.bestDay!;
    final usual = f.d.days.isEmpty ? 0.0 : f.d.days.fold<int>(0, (a, b) => a + b.minutes) / f.d.days.length;
    final drop = ramp(f.t, 0.1, 1.2, Curves.easeOutBack);
    final tear = ramp(f.t, 4.4, 5.2, Curves.easeInCubic);
    final fall = math.max(0.0, f.t - 5.1);
    final w = 268 * u, h1 = 262 * u, h2 = 106 * u;
    c.save();
    c.translate(f.w / 2, f.h * 0.43 - (1 - drop) * f.h * 0.8);
    c.rotate(-0.07 + math.sin(f.t * 1.6) * 0.015);

    Path part(double top, double bottom, {required bool perfBelow, required bool perfAbove}) {
      final p = Path()..moveTo(-w / 2 + 12 * u, top);
      if (perfAbove) {
        for (var x = -w / 2; x < w / 2; x += 11 * u) {
          p.lineTo(x + 5.5 * u, top + 4 * u);
          p.lineTo(x + 11 * u, top);
        }
      } else {
        p
          ..lineTo(w / 2 - 12 * u, top)
          ..arcToPoint(Offset(w / 2, top + 12 * u), radius: Radius.circular(12 * u), clockwise: false);
      }
      p.lineTo(w / 2, bottom - (perfBelow ? 0 : 12 * u));
      if (perfBelow) {
        for (var x = w / 2; x > -w / 2; x -= 11 * u) {
          p.lineTo(x - 5.5 * u, bottom - 4 * u);
          p.lineTo(x - 11 * u, bottom);
        }
      } else {
        p
          ..arcToPoint(Offset(w / 2 - 12 * u, bottom), radius: Radius.circular(12 * u), clockwise: false)
          ..lineTo(-w / 2 + 12 * u, bottom)
          ..arcToPoint(Offset(-w / 2, bottom - 12 * u), radius: Radius.circular(12 * u), clockwise: false);
      }
      if (!perfAbove) {
        p
          ..lineTo(-w / 2, top + 12 * u)
          ..arcToPoint(Offset(-w / 2 + 12 * u, top), radius: Radius.circular(12 * u), clockwise: false);
      }
      return p..close();
    }

    final top = -(h1 + h2) / 2;
    c.drawPath(part(top, top + h1, perfBelow: true, perfAbove: false), fill(kInk));
    final x = -w / 2 + 20 * u;
    f.film.line(c, 'Admit one', x, top + 18 * u, 17 * u, color: const Color(0xFF48484A));
    f.film.line(c, '${f.d.year}', w / 2 - 20 * u, top + 18 * u, 17 * u, color: const Color(0xFF48484A), align: 1);
    c.drawLine(Offset(x, top + 48 * u), Offset(w / 2 - 20 * u, top + 48 * u), stroke(kBlack, 2 * u));
    f.film.line(c, sayDate(best.date), x, top + 60 * u, 44 * u, weight: FontWeight.w800, color: kBlack, width: w - 40 * u);
    f.film.line(c, 'The biggest night of your year', x, top + 116 * u, 15 * u, weight: FontWeight.w600, color: const Color(0xFF48484A), width: w - 40 * u);
    f.film.counter(f, best.minutes, listeningTime, x: x, y: top + 152 * u, size: 70 * u, from: 1.2, to: 3.6, width: w - 40 * u, color: kBlack);
    c.save();
    c.translate(0, top + h1 + 2 * u);
    c.translate(tear * 26 * u + fall * 40 * u, fall * fall * 700 * u);
    c.rotate(tear * 0.22 + fall * 1.3);
    c.drawPath(part(0, h2, perfBelow: false, perfAbove: true), fill(kInk));
    var bx = -w / 2 + 20 * u;
    for (var i = 0; bx < w / 2 - 20 * u; i++) {
      final bw = (1 + (rnd(i, 3) * 3).floor()) * 1.5 * u;
      c.drawRect(Rect.fromLTWH(bx, 24 * u, bw, 60 * u), fill(kBlack));
      bx += bw + (1 + (rnd(i, 4) * 2).floor()) * 1.6 * u;
    }
    c.restore();
    c.restore();
    if (usual > 0) {
      final times = best.minutes / usual;
      f.film.kinetic(
        f,
        times >= 1.5 ? '${times.toStringAsFixed(times >= 10 ? 0 : 1)} times a usual day' : 'Your longest day of listening',
        x: 24 * u, y: f.h * 0.755, size: 42 * u, at: 5.0,
      );
    }
  }
}

// ── Receipt ─────────────────────────────────────────────────────────────────

/// The till prints your year, line by line, and tears it off.
class ReceiptScene extends FilmScene {
  @override
  String get id => 'discovery';
  @override
  String get technique => 'printing receipt';
  @override
  double get length => 8;
  @override
  double get still => 7;
  @override
  String why(WrappedData d) => 'Your year’s totals as your server counted them. Skipped is the share of plays your server marked as skips.';
  @override
  String share(WrappedData d) => 'My ${d.year} receipt: ${d.uniqueSongs} different songs.';
  @override
  String speech(WrappedData d) => '${d.totalPlays} plays, ${d.uniqueSongs} different songs, ${d.uniqueArtists} artists, ${d.listeningDays} days with music.';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u, d = f.d;
    final lines = [
      ('Plays', grouped(d.totalPlays)),
      ('Different songs', grouped(d.uniqueSongs)),
      ('Different artists', grouped(d.uniqueArtists)),
      ('Days with music', '${d.listeningDays}'),
      if (d.listeningDays > 0) ('Songs a day', (d.totalPlays / d.listeningDays).toStringAsFixed(1)),
      if (d.uniqueSongs > 0) ('Plays a song', (d.totalPlays / d.uniqueSongs).toStringAsFixed(1)),
      ('Skipped', '${(d.skipRate * 100).round()}%'),
    ];
    final w = 278 * u, rowH = 33 * u;
    final full = 100 * u + lines.length * rowH + 128 * u;
    // the printer jerks one line at a time
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
    c.drawPath(paper..close(), fill(kInk));
    final l = -w / 2 + 18 * u, r = w / 2 - 18 * u;
    f.film.line(c, 'NaviVibe', 0, 20 * u, 25 * u, weight: FontWeight.w800, color: kBlack, align: 0.5);
    f.film.line(c, 'Your ${d.year} in full', 0, 52 * u, 14 * u, weight: FontWeight.w500, color: const Color(0xFF48484A), align: 0.5);
    void dash(double y) {
      for (var x = l; x < r; x += 8 * u) {
        c.drawLine(Offset(x, y), Offset(math.min(r, x + 4.5 * u), y), stroke(kBlack, 1.3 * u));
      }
    }

    dash(84 * u);
    var y = 98 * u;
    for (final (k, v) in lines) {
      f.film.line(c, k, l, y, 16 * u, weight: FontWeight.w500, color: kBlack, width: 160 * u);
      f.film.line(c, v, r, y, 16 * u, color: kBlack, align: 1);
      y += rowH;
    }
    dash(y + 2 * u);
    f.film.line(c, 'Total', l, y + 16 * u, 26 * u, weight: FontWeight.w800, color: kBlack);
    f.film.line(c, '${grouped(d.totalMinutes)} min', r, y + 16 * u, 26 * u, weight: FontWeight.w800, color: kBlack, align: 1, width: 180 * u);
    var bx = l;
    for (var i = 0; bx < r - 3 * u; i++) {
      final bw = (1 + (rnd(i, 13) * 3).floor()) * 1.3 * u;
      c.drawRect(Rect.fromLTWH(bx, y + 62 * u, bw, 36 * u), fill(kBlack));
      bx += bw + (1 + (rnd(i, 14) * 3).floor()) * 1.3 * u;
    }
    c.restore();
    // the till
    final jig = raw > 0 && f.t < 5.4 ? math.sin(f.t * 70) * 0.8 * u : 0.0;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(16 * u, slot - 30 * u + jig, f.w - 32 * u, 36 * u), Radius.circular(10 * u)), fill(const Color(0xFF2C2C2E)));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(30 * u, slot - 6 * u + jig, f.w - 60 * u, 7 * u), Radius.circular(3 * u)), fill(kBlack));
    f.film.kinetic(f, 'You explored ${grouped(d.uniqueSongs)} songs', x: 24 * u, y: f.h * 0.82, size: 34 * u, at: 6.1);
  }
}

// ── Sigil ───────────────────────────────────────────────────────────────────

/// A spirograph geared from your four measures: nobody else's year draws this shape. Turn it.
class SigilScene extends FilmScene {
  final List<Offset> _points = [];
  final WrappedPersonality me;
  SigilScene(WrappedData d) : me = d.personality {
    double trait(String k) => me.traits[k] ?? 0;
    final teeth = 5 + (trait('explorer') * 8).round(); // petals
    final inner = 0.22 + 0.5 * trait('devotee'); // how deep it folds
    final second = 2 + (trait('night') * 9).round();
    final ripple = 0.06 + 0.2 * trait('marathon');
    final phase = (d.totalMinutes % 97) / 97 * kTau;
    const n = 900;
    for (var i = 0; i <= n; i++) {
      final a = i / n * kTau * 5;
      final r = (1 - inner) + inner * math.cos(a * teeth / 5) + ripple * math.sin(a * (second + 0.2) + phase);
      _points.add(Offset(math.cos(a), math.sin(a)) * r);
    }
    final most = _points.fold<double>(0.01, (m, p) => math.max(m, p.distance));
    for (var i = 0; i < _points.length; i++) {
      _points[i] = _points[i] / most;
    }
  }
  @override
  String get id => 'personality';
  @override
  String get technique => 'spirograph drawn from your own measures';
  @override
  double get length => 9;
  @override
  String why(WrappedData d) =>
      'Four measures from your year set the gears: how many different songs for your plays, how much was one artist, how much came between 10 pm and 5 am, and how big your biggest day was next to a usual one. The strongest names you.';
  @override
  String share(WrappedData d) => 'I am ${d.personality.name}.';
  @override
  String speech(WrappedData d) => 'Your listening personality: ${d.personality.name}. ${d.personality.line}';
  @override
  String? get hint => 'Turn your sigil';

  @override
  void paint(FilmFrame f) {
    final c = f.canvas, u = f.u;
    final mid = Offset(f.w / 2, f.h * 0.36);
    final draw = ramp(f.t, 0.2, 4.6, Curves.easeInOutSine);
    final turn = f.t * 0.12 + f.touch.spin * 0.5;
    final upto = (_points.length * draw).floor().clamp(1, _points.length);
    // three copies, each a step behind and a step smaller: depth from one line
    for (var layer = 2; layer >= 0; layer--) {
      final path = Path();
      final size = 150 * u * (1 - layer * 0.13);
      final yaw = math.sin(f.t * 0.6 + layer * 0.35) * 0.28 + f.touch.tiltX * 0.7;
      for (var i = 0; i < upto; i++) {
        final p = _points[i];
        final a = turn + layer * 0.2;
        final x = p.dx * math.cos(a) - p.dy * math.sin(a), y = p.dx * math.sin(a) + p.dy * math.cos(a);
        final o = mid + Offset(x * math.cos(yaw) * size, y * size);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, stroke(white([0.95, 0.4, 0.2][layer]), [1.7, 1.2, 1.0][layer] * u));
      if (layer == 0 && draw < 1) {
        // the pen and its gear
        final p = _points[upto - 1];
        final x = p.dx * math.cos(turn) - p.dy * math.sin(turn), y = p.dx * math.sin(turn) + p.dy * math.cos(turn);
        final tip = mid + Offset(x * math.cos(yaw) * size, y * size);
        c.drawCircle(tip, 5 * u, fill(kInk));
        c.drawLine(mid, tip, stroke(white(0.35), 1 * u));
      }
    }
    f.film.kinetic(f, 'You are', x: 24 * u, y: f.h * 0.645, size: 20 * u, at: 3.4, weight: FontWeight.w600, color: kDim);
    final h = f.film.kinetic(f, me.name, x: 24 * u, y: f.h * 0.645 + 26 * u, size: 58 * u, at: 3.7, stagger: 0.25);
    f.film.kinetic(f, me.line, x: 24 * u, y: f.h * 0.645 + 34 * u + h, size: 18 * u, at: 4.8, weight: FontWeight.w500, color: kDim, lines: 3, stagger: 0.04);
  }
}

// ── Mixtape ─────────────────────────────────────────────────────────────────

/// The year as a mixtape sleeve: your cover slides together from slats, the track list is written in.
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

  void _sliced(FilmFrame f, Rect box, double from) {
    final c = f.canvas, d = f.d;
    final image = d.songs.isEmpty ? null : f.assets.covers[d.songs.first.coverKey];
    const n = 9;
    for (var i = 0; i < n; i++) {
      final k = ramp(f.t, from + i * 0.09, from + 0.8 + i * 0.09, Curves.easeOutBack);
      if (k <= 0) continue;
      final slat = Rect.fromLTWH(box.left + box.width * i / n, box.top, box.width / n + 0.5, box.height);
      c.save();
      c.clipRect(slat.shift(Offset(0, (1 - k) * (i.isEven ? -1 : 1) * box.height * 1.3)));
      c.translate(0, (1 - k) * (i.isEven ? -1 : 1) * box.height * 1.3);
      f.film.picture(c, image, box, tile: true);
      c.restore();
    }
  }

  @override
  void paint(FilmFrame f) {
    if (f.h < f.w * 1.2) return _square(f);
    final u = f.u, c = f.canvas, d = f.d;
    c.save();
    final tilt = Matrix4.identity()
      ..setEntry(3, 2, 0.0011 / u)
      ..rotateY(f.touch.tiltX * 0.35)
      ..rotateX(-f.touch.tiltY * 0.3);
    c.translate(f.w / 2, f.h / 2);
    c.transform(tilt.storage);
    c.translate(-f.w / 2, -f.h / 2);
    final art = Rect.fromLTWH(0, 0, f.w, f.h * 0.46);
    _sliced(f, art, 0.2);
    final x = 24 * u;
    var y = art.bottom + 18 * u;
    final who = f.name == null || f.name!.isEmpty ? 'Wrapped ${d.year}' : '${f.name} · Wrapped ${d.year}';
    f.film.kinetic(f, who, x: x, y: y, size: 17 * u, at: 1.3, weight: FontWeight.w700, lines: 1, color: kDim);
    y += 25 * u;
    y += f.film.kinetic(f, d.personality.name, x: x, y: y, size: 43 * u, at: 1.5, lines: 1) + 8 * u;
    final col = (f.w - 48 * u - 14 * u) / 2;
    final sideB = [
      (grouped(d.totalMinutes), 'minutes'),
      if (d.artists.isNotEmpty) (d.artists.first.name, 'artist'),
      if (d.genres.isNotEmpty) (d.genres.first.name, 'sound'),
      if (d.longestStreak > 1) ('${d.longestStreak} days', 'streak'),
      if (d.story.era != null) ('${d.story.era!.middle}', 'era') else ('${grouped(d.uniqueSongs)} songs', 'explored'),
    ];
    final rows = math.max(d.songs.length, sideB.length);
    for (var i = 0; i < rows; i++) {
      final at = 2.2 + i * 0.22, k = ramp(f.t, at, at + 0.5, Curves.easeOutCubic);
      if (k <= 0) break;
      final ry = y + i * 42 * u;
      c.drawLine(Offset(x, ry), Offset(x + (f.w - 48 * u) * k, ry), stroke(const Color(0xFF3A3A3C), 1 * u));
      if (k < 0.6) continue;
      if (i < d.songs.length) {
        f.film.line(c, '${i + 1}  ${nice(d.songs[i].title)}', x, ry + 6 * u, 15 * u, width: col);
        f.film.line(c, d.songs[i].artist, x + 17 * u, ry + 24 * u, 11.5 * u, weight: FontWeight.w500, color: kDim, width: col - 17 * u);
      }
      if (i < sideB.length) {
        f.film.line(c, sideB[i].$1, x + col + 14 * u, ry + 6 * u, 15 * u, width: col);
        f.film.line(c, sideB[i].$2, x + col + 14 * u, ry + 24 * u, 11.5 * u, weight: FontWeight.w500, color: kDim, width: col);
      }
    }
    f.film.kinetic(f, 'NaviVibe', x: x, y: f.h * 0.935, size: 15 * u, at: 3.6, weight: FontWeight.w700);
    // a band of light runs over the sleeve
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
  }

  void _square(FilmFrame f) {
    final u = f.u, d = f.d, c = f.canvas;
    _sliced(f, Rect.fromLTWH(f.w * 0.46, 0, f.w * 0.54, f.h * 0.54), 0);
    final x = 22 * u;
    f.film.line(c, f.name == null || f.name!.isEmpty ? 'Wrapped ${d.year}' : '${f.name} · ${d.year}', x, 22 * u, 16 * u, color: kDim, width: 136 * u);
    f.film.kinetic(f, d.personality.name, x: x, y: 62 * u, size: 36 * u, at: 0, lines: 3, width: 136 * u);
    var y = f.h * 0.54 + 16 * u;
    for (final (k, v) in [
      ('Listened', '${grouped(d.totalMinutes)} minutes'),
      if (d.songs.isNotEmpty) ('Song', nice(d.songs.first.title)),
      if (d.artists.isNotEmpty) ('Artist', d.artists.first.name),
      if (d.longestStreak > 1) ('Streak', '${d.longestStreak} days'),
    ]) {
      f.film.line(c, k, x, y + 3 * u, 13 * u, weight: FontWeight.w500, color: kDim);
      f.film.line(c, v, x + 72 * u, y, 17 * u, width: f.w - 120 * u);
      y += 27 * u;
    }
    f.film.line(c, 'NaviVibe', f.w - 22 * u, f.h - 34 * u, 14 * u, align: 1);
  }
}
