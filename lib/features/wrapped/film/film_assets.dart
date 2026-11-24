import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A picture as the film uses it: the image itself, and its colours read off as a square grid of particles.
class FilmCover {
  final ui.Image image;
  final int side;

  /// ARGB, row by row, [side] x [side].
  final Int32List pixels;
  const FilmCover(this.image, this.side, this.pixels);

  static Future<FilmCover> of(ui.Image image, {int side = 38}) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final s = math.min(image.width, image.height).toDouble();
    c.drawImageRect(
      image,
      Rect.fromCenter(center: Offset(image.width / 2, image.height / 2), width: s, height: s),
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final pic = rec.endRecording();
    final small = await pic.toImage(side, side);
    pic.dispose();
    final bytes = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    small.dispose();
    final out = Int32List(side * side);
    for (var i = 0; i < out.length; i++) {
      final r = bytes.getUint8(i * 4), g = bytes.getUint8(i * 4 + 1), b = bytes.getUint8(i * 4 + 2);
      out[i] = (0xFF << 24) | (r << 16) | (g << 8) | b;
    }
    return FilmCover(image, side, out);
  }
}

/// Reads the shape of [text] as points in 0..1 x 0..1 (of its own box), [count] of them, spread evenly.
Future<Float32List> textPoints(String text, int count, {String family = 'InterDisplay'}) async {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: family, fontSize: 120, fontWeight: FontWeight.w800, color: const Color(0xFFFFFFFF), letterSpacing: -4),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width.ceil(), h = tp.height.ceil();
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), Offset.zero);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  tp.dispose();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  final lit = <int>[];
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      if (bytes.getUint8((y * w + x) * 4 + 3) > 128) lit.add(y * w + x);
    }
  }
  final out = Float32List(count * 2);
  if (lit.isEmpty) return out;
  // a fixed stride over the lit pixels: the same year always lands the same way
  for (var i = 0; i < count; i++) {
    final p = lit[(i * lit.length ~/ count + (i * 7919) % 3) % lit.length];
    out[i * 2] = (p % w) / w;
    out[i * 2 + 1] = (p ~/ w) / h;
  }
  return out;
}

/// Resolves [provider] once, or null when it fails or takes too long (the film never waits on a picture).
Future<ui.Image?> loadFilmImage(ImageProvider provider, {int width = 512, Duration timeout = const Duration(seconds: 12)}) {
  final done = Completer<ui.Image?>();
  final stream = ResizeImage(provider, width: width).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(ui.Image? image) {
    if (!done.isCompleted) done.complete(image);
  }

  listener = ImageStreamListener((info, _) => finish(info.image.clone()), onError: (_, _) => finish(null));
  stream.addListener(listener);
  return done.future.timeout(timeout, onTimeout: () => null).whenComplete(() => stream.removeListener(listener));
}

/// Everything the film paints with that is not numbers: covers and portraits, filled in as they arrive.
class FilmAssets {
  final Map<int, FilmCover> songs = {};
  final Map<int, ui.Image> artists = {};
  Float32List year = Float32List(0);

  void dispose() {
    for (final s in songs.values) {
      s.image.dispose();
    }
    for (final a in artists.values) {
      a.dispose();
    }
    songs.clear();
    artists.clear();
  }
}
