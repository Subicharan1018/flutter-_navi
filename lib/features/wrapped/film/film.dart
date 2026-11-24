import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import '../data/wrapped_models.dart';
import 'film_assets.dart';
import 'scenes.dart';

const kInk = Color(0xFFFFFFFF);
const kDim = Color(0xFF9E9EA4);
const kTau = math.pi * 2;

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double mix(double a, double b, double t) => a + (b - a) * t;

/// Eased 0..1 as [t] runs from [a] to [b].
double ramp(double t, double a, double b, [Curve curve = Curves.easeInOutCubic]) => b <= a ? (t >= b ? 1 : 0) : curve.transform(clamp01((t - a) / (b - a)));

/// A fixed 0..1 for an index, the same on every run and in every picture.
double rnd(int i, [int salt = 0]) {
  var x = (i * 374761393 + salt * 668265263 + 1274126177) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return ((x ^ (x >> 16)) & 0xffff) / 0xffff;
}

/// One particle, reused for every particle of every frame.
class Dot {
  double x = 0, y = 0, r = 1, a = 1;
  int rgb = 0xFFFFFF;
  void set(double px, double py, double radius, double alpha, [int colour = 0xFFFFFF]) {
    x = px;
    y = py;
    r = radius;
    a = alpha;
    rgb = colour;
  }
}

/// What your finger is doing to the film. Pictures and videos are made with an untouched one.
class FilmTouch {
  Offset? finger;
  double grip = 0; // 0..1, eases in and out with the finger
  double spin = 0; // radians added by dragging
  double tiltX = 0, tiltY = 0; // -1..1
  double? scrubX; // 0..1 across the stage while a finger chooses something
  int? guess;
  double guessAt = 0;
  final List<(Offset, double)> blasts = []; // where, and how many seconds ago

  void tick(double dt) {
    grip = finger == null ? math.max(0, grip - dt * 2.5) : math.min(1, grip + dt * 6);
    for (var i = 0; i < blasts.length; i++) {
      blasts[i] = (blasts[i].$1, blasts[i].$2 + dt);
    }
    blasts.removeWhere((b) => b.$2 > 1.3);
  }
}

/// One frame's canvas and clock, handed to a scene.
class FilmFrame {
  final WrappedFilm film;
  final Canvas canvas;
  final Size size;
  final double t;
  final FilmTouch touch;
  final String? name;

  FilmFrame(this.film, this.canvas, this.size, this.t, this.touch, this.name);

  double get w => size.width;
  double get h => size.height;

  /// The unit: 1 at the 360 wide design.
  double get u => size.width / 360;
  Offset get mid => Offset(w / 2, h / 2);
  WrappedData get d => film.data;
  FilmAssets get assets => film.assets;
}

/// A scene is a formation for the swarm (where every particle is at a moment) and what is drawn over it.
abstract class FilmScene {
  String get id;
  double get length;

  /// The moment that makes the best still.
  double get still => length * 0.82;
  String why(WrappedData d);
  String share(WrappedData d);

  /// Read aloud by a screen reader in place of the animation.
  String speech(WrappedData d);

  /// What touching does, shown once as a hint; null when the scene only stirs.
  String? get hint => null;

  /// True when dragging belongs to the scene.
  bool get drags => false;
  void place(FilmFrame f, int i, int n, Dot out);
  void under(FilmFrame f) {}
  void over(FilmFrame f) {}
}

/// The whole film as a pure function of time: the same inputs always paint the same frame, which is why a scene can be
/// saved as a picture or rendered to a video exactly as it plays.
class WrappedFilm {
  WrappedData data;

  /// False while more of the year is on its way; the scenes then stop at what is known.
  bool settled;
  final FilmAssets assets;
  final int count;
  late List<FilmScene> scenes = filmScenes(data, settled: settled);
  late final ui.Image _sprite = _makeSprite();

  late final Float32List _transforms = Float32List(count * 4);
  late final Float32List _rects = _spriteRects(count);
  late final Int32List _colors = Int32List(count);
  final Dot _a = Dot(), _b = Dot();
  final Map<String, TextPainter> _text = {};

  WrappedFilm(this.data, this.assets, {this.count = 1500, this.settled = true});

  /// More of the year has arrived: the scenes ahead appear, the ones so far stay where they are.
  void update(WrappedData data, {required bool settled}) {
    this.data = data;
    this.settled = settled;
    scenes = filmScenes(data, settled: settled);
  }

  static Float32List _spriteRects(int n) {
    final r = Float32List(n * 4);
    for (var i = 0; i < n; i++) {
      r[i * 4 + 2] = 32;
      r[i * 4 + 3] = 32;
    }
    return r;
  }

  static ui.Image _makeSprite() {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawCircle(
      const Offset(16, 16),
      16,
      Paint()
        ..shader = ui.Gradient.radial(const Offset(16, 16), 16, const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)], const [0, 0.62, 1]),
    );
    final pic = rec.endRecording();
    final img = pic.toImageSync(32, 32);
    pic.dispose();
    return img;
  }

  void dispose() {
    _sprite.dispose();
    for (final t in _text.values) {
      t.dispose();
    }
    assets.dispose();
  }

  /// Paints scene [index] at [t] seconds. For the first moments the swarm is still flying from scene [from].
  void paint(Canvas canvas, Size size, {required int index, required double t, int? from, double fromT = 0, FilmTouch? touch, String? name}) {
    // Only between frames: within one, a scene may still be holding a line of words.
    if (_text.length > 220) {
      for (final t in _text.values) {
        t.dispose();
      }
      _text.clear();
    }
    final scene = scenes[index];
    final f = FilmFrame(this, canvas, size, t, touch ?? FilmTouch(), name);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
    scene.under(f);
    _swarm(f, scene, from == null ? null : scenes[from], fromT);
    scene.over(f);
    canvas.restore();
  }

  void _swarm(FilmFrame f, FilmScene scene, FilmScene? prev, double fromT) {
    const flight = 1.5;
    final u = f.u;
    final morphing = prev != null && f.t < flight;
    final old = morphing ? FilmFrame(this, f.canvas, f.size, fromT + f.t, f.touch, f.name) : null;
    final finger = f.touch.finger;
    for (var i = 0; i < count; i++) {
      scene.place(f, i, count, _a);
      var x = _a.x, y = _a.y, r = _a.r, a = _a.a;
      var rgb = _a.rgb;
      if (morphing) {
        prev.place(old!, i, count, _b);
        final delay = rnd(i, 91) * 0.5;
        final k = ramp(f.t, delay, delay + flight - 0.5);
        final arc = math.sin(math.pi * k);
        final dx = x - _b.x, dy = y - _b.y;
        final bend = (rnd(i, 92) - 0.5) * 0.9;
        x = _b.x + dx * k - dy * bend * arc + math.sin(f.t * 5 + i) * 10 * u * arc;
        y = _b.y + dy * k + dx * bend * arc + math.cos(f.t * 4 + i) * 10 * u * arc;
        r = mix(_b.r, r, k) * (1 + arc * 0.5);
        a = mix(_b.a, a, k);
        rgb = _mixRgb(_b.rgb, rgb, k);
      }
      if (finger != null || f.touch.grip > 0) {
        final p = finger ?? _lastFinger;
        final dx = x - p.dx, dy = y - p.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final reach = 90 * u;
        if (dist < reach && dist > 0.5) {
          final push = (1 - dist / reach) * 46 * u * f.touch.grip;
          // away from the finger, with a little turn, so it feels like stirring
          x += dx / dist * push - dy / dist * push * 0.5;
          y += dy / dist * push + dx / dist * push * 0.5;
        }
      }
      for (final (at, age) in f.touch.blasts) {
        final dx = x - at.dx, dy = y - at.dy;
        final dist = math.sqrt(dx * dx + dy * dy) + 0.5;
        final ring = age * 520 * u;
        final band = (dist - ring) / (70 * u);
        final push = math.exp(-band * band) * 70 * u * (1 - age / 1.3);
        x += dx / dist * push;
        y += dy / dist * push;
      }
      final scale = r / 16;
      _transforms[i * 4] = scale;
      _transforms[i * 4 + 1] = 0;
      _transforms[i * 4 + 2] = x - r;
      _transforms[i * 4 + 3] = y - r;
      _colors[i] = ((clamp01(a) * 255).round() << 24) | rgb;
    }
    if (finger != null) _lastFinger = finger;
    f.canvas.drawRawAtlas(_sprite, _transforms, _rects, _colors, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low);
  }

  Offset _lastFinger = Offset.zero;

  static int _mixRgb(int a, int b, double k) {
    if (a == b) return a;
    int ch(int s) => (((a >> s) & 255) + ((((b >> s) & 255) - ((a >> s) & 255)) * k)).round();
    return (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }

  // ── words ──────────────────────────────────────────────────────────────

  TextPainter words(String text, double size, {FontWeight weight = FontWeight.w800, Color color = kInk}) {
    final key = '$text|${size.toStringAsFixed(1)}|${weight.value}|${color.toARGB32()}';
    final hit = _text[key];
    if (hit != null) return hit;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: size >= 18 ? 'InterDisplay' : 'Inter',
          fontSize: size,
          height: 1.08,
          fontWeight: weight,
          color: color,
          letterSpacing: size * (-0.0223 + 0.185 * math.exp(-0.1745 * size)),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _text[key] = tp;
    return tp;
  }

  /// The largest size up to [size] at which [text] wraps into [lines] lines of [width]; then those lines.
  (double, List<String>) fit(String text, double size, double width, int lines, FontWeight weight) {
    var s = size;
    while (true) {
      final out = <String>[];
      var line = '';
      for (final word in text.split(' ')) {
        final next = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && words(next, s, weight: weight).width > width) {
          out.add(line);
          line = word;
        } else {
          line = next;
        }
      }
      out.add(line);
      final fits = out.length <= lines && out.every((l) => words(l, s, weight: weight).width <= width);
      if (fits) return (s, out);
      if (s <= size * 0.42) {
        // too long even small: keep what fits and say so
        final cut = out.take(lines).toList();
        for (var i = 0; i < cut.length; i++) {
          var l = cut[i];
          final clipped = i == lines - 1 && out.length > lines;
          while (l.length > 1 && words(clipped ? '$l…' : l, s, weight: weight).width > width) {
            l = l.substring(0, l.length - 1);
          }
          cut[i] = clipped || l != cut[i] ? '$l…' : l;
        }
        return (s, cut);
      }
      s *= 0.92;
    }
  }

  /// Words that rise out of their own baseline one after another and settle with a small overshoot.
  /// Returns the height they take. [x] is the left edge, or the middle when [center].
  double kinetic(
    FilmFrame f,
    String text, {
    required double x,
    required double y,
    required double size,
    required double at,
    double? width,
    int lines = 2,
    FontWeight weight = FontWeight.w800,
    Color color = kInk,
    bool center = false,
    double stagger = 0.09,
  }) {
    final c = f.canvas;
    final (s, rows) = fit(text, size, width ?? f.w - 48 * f.u, lines, weight);
    var top = y;
    var n = 0;
    for (final row in rows) {
      final full = words(row, s, weight: weight, color: color);
      var px = center ? x - full.width / 2 : x;
      final space = words('a a', s, weight: weight, color: color).width - words('aa', s, weight: weight, color: color).width;
      for (final word in row.split(' ')) {
        final tp = words(word, s, weight: weight, color: color);
        final k = ramp(f.t, at + n * stagger, at + n * stagger + 0.7, Curves.easeOutBack);
        if (k > 0.001) {
          c.save();
          c.clipRect(Rect.fromLTWH(px - s * 0.2, top - s * 0.12, tp.width + s * 0.4, tp.height + s * 0.24));
          c.translate(px, top + tp.height * (1 - k) * 1.1);
          c.rotate((1 - k) * 0.12);
          tp.paint(c, Offset.zero);
          c.restore();
        }
        px += tp.width + space;
        n++;
      }
      top += full.height;
    }
    return top - y;
  }

  /// A number that races up and lands with a kick.
  void counter(FilmFrame f, int value, String Function(int) say, {required double x, required double y, required double size, required double from, required double to, double? width, bool center = false}) {
    if (f.t < from) return;
    final k = ramp(f.t, from, to, Curves.easeOutExpo);
    final shown = (value * k).round();
    final end = words(say(value), size);
    final maxW = width ?? f.w - 48 * f.u;
    final s = end.width > maxW ? size * maxW / end.width : size;
    final tp = k >= 1 ? words(say(value), s) : words(say(shown), s);
    final kick = 1 + 0.1 * math.sin(math.pi * clamp01((f.t - to + 0.25) / 0.45));
    final c = f.canvas;
    c.save();
    c.translate(center ? x : x + tp.width / 2, y + tp.height / 2);
    c.scale(kick);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  /// A cover inside [rect] with corner [radius], turned by [angle]; nothing until it has arrived.
  void picture(Canvas c, ui.Image? image, Rect rect, {double radius = 0, double angle = 0, double alpha = 1}) {
    if (image == null || alpha <= 0.003 || rect.width < 1) return;
    final s = math.min(image.width, image.height).toDouble();
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    if (angle != 0) c.rotate(angle);
    final box = Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height);
    c.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
    c.drawImageRect(
      image,
      Rect.fromCenter(center: Offset(image.width / 2, image.height / 2), width: s, height: s),
      box,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, clamp01(alpha)),
    );
    c.restore();
  }
}
