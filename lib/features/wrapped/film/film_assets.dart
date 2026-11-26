import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

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

/// The covers (by "title|artist"), portraits (by name), their colours, and the year as points, filled in as they arrive.
class FilmAssets {
  final Map<String, ui.Image> covers = {};
  final Map<String, ui.Image> people = {};
  final Map<String, Color> hues = {};

  /// The year's digits as points for the opening (empty until read).
  Float32List year = Float32List(0);

  void dispose() {
    for (final i in [...covers.values, ...people.values]) {
      i.dispose();
    }
    covers.clear();
    people.clear();
  }
}
