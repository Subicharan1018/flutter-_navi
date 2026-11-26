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
const kBlack = Color(0xFF000000);
const kTau = math.pi * 2;

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double mix(double a, double b, double t) => a + (b - a) * t;
Color white(double a) => Color.fromRGBO(255, 255, 255, clamp01(a));
Color grey(int v) => Color.fromRGBO(v, v, v, 1);

/// Eased 0..1 as [t] runs from [a] to [b].
double ramp(double t, double a, double b, [Curve curve = Curves.easeInOutCubic]) => b <= a ? (t >= b ? 1 : 0) : curve.transform(clamp01((t - a) / (b - a)));

/// A fixed 0..1 for an index, the same on every run and in every picture.
double rnd(int i, [int salt = 0]) {
  var x = (i * 374761393 + salt * 668265263 + 1274126177) & 0x7fffffff;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
  return ((x ^ (x >> 16)) & 0xffff) / 0xffff;
}

Paint stroke(Color c, double w, {StrokeCap cap = StrokeCap.butt}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = cap
  ..strokeJoin = StrokeJoin.round
  ..color = c;
Paint fill(Color c) => Paint()..color = c;

/// What your finger is doing to the film. Pictures and videos are made with an untouched one.
class FilmTouch {
  Offset? finger;
  double spin = 0; // radians added by dragging
  double tiltX = 0, tiltY = 0; // -1..1
  double? scrubX; // 0..1 across the stage while a finger chooses something
  int? guess;
  double guessAt = 0;
  Offset? kickAt;
  double kick = 9; // seconds since the last tap on the scene

  void tick(double dt) => kick += dt;

  /// 1 at the tap, gone within [over] seconds.
  double punch([double over = 0.6]) => math.max(0, 1 - kick / over);
}

/// One particle, reused for every particle of every frame.
class Dot {
  double x = 0, y = 0, r = 1, a = 1;
  void set(double px, double py, double radius, double alpha) {
    x = px;
    y = py;
    r = radius;
    a = alpha;
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
  WrappedData get d => film.data;
  FilmAssets get assets => film.assets;
  FilmFrame at(double time) => FilmFrame(film, canvas, size, time, touch, name);
}

abstract class FilmScene {
  String get id;
  double get length;

  /// The moment that makes the best still: after its numbers have landed.
  double get still => length * 0.82;

  /// How it is drawn, in a few words (for the contact sheet).
  String get technique;
  bool get particles => false;
  String why(WrappedData d);
  String share(WrappedData d);

  /// Read aloud by a screen reader in place of the animation.
  String speech(WrappedData d);
  String? get hint => null;

  /// True when a drag belongs to the scene across its width ([FilmTouch.scrubX]).
  int get scrubSteps => 0;
  void paint(FilmFrame f);

  /// A tap on the scene at [p]; return a new time to jump to, or null.
  double? tap(FilmFrame f, Offset p) => null;

  /// How long the scene runs given what was touched.
  double end(FilmTouch t) => length;
}

/// The whole film as a pure function of time: the same inputs always paint the same frame, which is why a scene can be
/// saved as a picture or rendered to a video exactly as it plays. Only the scene on screen is ever painted.
class WrappedFilm {
  WrappedData data;

  /// False while more of the year is on its way; the scenes then stop at what is known.
  bool settled;
  final FilmAssets assets;

  /// Particles for the two scenes that use them. Lowered on a phone that cannot keep up.
  int grains;
  late List<FilmScene> scenes = filmScenes(data, settled: settled);
  late final ui.Image _sprite = _makeSprite();
  Float32List _transforms = Float32List(0), _rects = Float32List(0);
  Int32List _colors = Int32List(0);
  final Dot _dot = Dot();
  final Map<String, TextPainter> _text = {};

  WrappedFilm(this.data, this.assets, {this.grains = 520, this.settled = true});

  /// More of the year has arrived: the scenes ahead appear, the ones so far stay where they are.
  void update(WrappedData data, {required bool settled}) {
    this.data = data;
    this.settled = settled;
    scenes = filmScenes(data, settled: settled);
  }

  static ui.Image _makeSprite() {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawCircle(
      const Offset(16, 16),
      16,
      Paint()..shader = ui.Gradient.radial(const Offset(16, 16), 16, const [kInk, kInk, Color(0x00FFFFFF)], const [0, 0.62, 1]),
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

  static const cut = 0.6;

  /// Paints scene [index] at [t] seconds. For the first moments it is cutting in over scene [from].
  void paint(Canvas canvas, Size size, {required int index, required double t, int? from, double fromT = 0, FilmTouch? touch, String? name}) {
    // Only between frames: within one, a scene may still be holding a line of words.
    if (_text.length > 320) {
      for (final p in _text.values) {
        p.dispose();
      }
      _text.clear();
    }
    final hand = touch ?? FilmTouch();
    final box = Offset.zero & size;
    void scene(int i, double time) {
      canvas.drawRect(box, fill(kBlack));
      scenes[i].paint(FilmFrame(this, canvas, size, time, i == index ? hand : FilmTouch(), name));
    }

    canvas.save();
    canvas.clipRect(box);
    if (from == null || t >= cut) {
      scene(index, t);
    } else {
      final k = Curves.easeInOutCubic.transform(clamp01(t / cut));
      _cut(canvas, size, index % 5, k, () => scene(from, fromT), () => scene(index, t));
    }
    canvas.restore();
  }

  /// Five cuts, so two neighbours never change the same way.
  void _cut(Canvas c, Size s, int kind, double k, VoidCallback old, VoidCallback next) {
    void moved(double dx, double dy, VoidCallback draw) {
      c.save();
      c.translate(dx, dy);
      c.clipRect(Offset.zero & s);
      draw();
      c.restore();
    }

    void clipped(Path path, VoidCallback draw) {
      c.save();
      c.clipPath(path);
      draw();
      c.restore();
    }

    switch (kind) {
      case 0: // pushed up
        moved(0, -s.height * k, old);
        moved(0, s.height * (1 - k), next);
      case 1: // iris
        old();
        clipped(Path()..addOval(Rect.fromCircle(center: s.center(Offset.zero), radius: s.longestSide * 0.62 * k)), next);
      case 2: // blinds
        old();
        final path = Path();
        for (var i = 0; i < 6; i++) {
          path.addRect(Rect.fromLTWH(s.width * i / 6, 0, s.width / 6 * k + 0.5, s.height));
        }
        clipped(path, next);
      case 3: // whip
        moved(-s.width * k, 0, old);
        moved(s.width * (1 - k), 0, next);
      default: // doors
        old();
        clipped(Path()..addRect(Rect.fromLTWH(0, s.height / 2 * (1 - k), s.width, s.height * k)), next);
    }
  }

  // ── particles ──────────────────────────────────────────────────────────

  /// Draws [n] particles in one call.
  void dots(Canvas c, int n, void Function(int i, Dot out) place) {
    if (_transforms.length != n * 4) {
      _transforms = Float32List(n * 4);
      _rects = Float32List(n * 4);
      _colors = Int32List(n);
      for (var i = 0; i < n; i++) {
        _rects[i * 4 + 2] = 32;
        _rects[i * 4 + 3] = 32;
      }
    }
    for (var i = 0; i < n; i++) {
      place(i, _dot);
      _transforms[i * 4] = _dot.r / 16;
      _transforms[i * 4 + 1] = 0;
      _transforms[i * 4 + 2] = _dot.x - _dot.r;
      _transforms[i * 4 + 3] = _dot.y - _dot.r;
      _colors[i] = ((clamp01(_dot.a) * 255).round() << 24) | 0xFFFFFF;
    }
    c.drawRawAtlas(_sprite, _transforms, _rects, _colors, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low);
  }

  // ── words ──────────────────────────────────────────────────────────────

  TextPainter words(String text, double size, {FontWeight weight = FontWeight.w800, Color color = kInk, double outline = 0}) {
    final key = '$text|${size.toStringAsFixed(1)}|${weight.value}|${color.toARGB32()}|$outline';
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
          color: outline > 0 ? null : color,
          foreground: outline > 0 ? stroke(color, outline) : null,
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
      if (s <= size * 0.55) {
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

  /// One line, as it is, fitted to [width]. [align] 0 left, 0.5 middle, 1 right of [x]. Returns its width.
  double line(Canvas c, String text, double x, double y, double size, {FontWeight weight = FontWeight.w700, Color color = kInk, double align = 0, double width = 1e6}) {
    final (s, rows) = fit(text, size, width, 1, weight);
    final tp = words(rows.first, s, weight: weight, color: color);
    tp.paint(c, Offset(x - tp.width * align, y));
    return tp.width;
  }

  /// Words that rise out of their own baseline one after another and settle with a small overshoot. Returns the height.
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
        if (k >= 0.999) {
          tp.paint(c, Offset(px, top));
        } else if (k > 0.001) {
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

  /// A number that races up and lands with a kick. Returns its width.
  double counter(
    FilmFrame f,
    int value,
    String Function(int) say, {
    required double x,
    required double y,
    required double size,
    required double from,
    required double to,
    double? width,
    double align = 0,
    Color color = kInk,
  }) {
    final end = words(say(value), size, color: color);
    final maxW = width ?? f.w - 48 * f.u;
    final s = end.width > maxW ? size * maxW / end.width : size;
    if (f.t < from) return math.min(end.width, maxW);
    final k = ramp(f.t, from, to, Curves.easeOutExpo);
    final tp = words(say(k >= 1 ? value : (value * k).round()), s, color: color);
    final kick = 1 + 0.1 * math.sin(math.pi * clamp01((f.t - to + 0.25) / 0.45));
    final c = f.canvas;
    c.save();
    c.translate(x + tp.width * (0.5 - align), y + tp.height / 2);
    c.scale(kick);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
    return tp.width;
  }

  /// A cover inside [rect] with corner [radius], turned by [angle]; a plain grey tile until it has arrived.
  void picture(Canvas c, ui.Image? image, Rect rect, {double radius = 0, double angle = 0, bool tile = false}) {
    if (rect.width < 1 || (image == null && !tile)) return;
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    if (angle != 0) c.rotate(angle);
    final box = Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height);
    c.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
    if (image == null) {
      c.drawRect(box, fill(const Color(0xFF2C2C2E)));
    } else {
      final scale = math.min(image.width / rect.width, image.height / rect.height);
      c.drawImageRect(
        image,
        Rect.fromCenter(center: Offset(image.width / 2, image.height / 2), width: rect.width * scale, height: rect.height * scale),
        box,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    c.restore();
  }
}
