import 'dart:async';
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

/// The covers (by "title|artist") and portraits (by name) the film paints with, filled in as they arrive.
class FilmAssets {
  final Map<String, ui.Image> covers = {};
  final Map<String, ui.Image> people = {};

  void dispose() {
    for (final i in [...covers.values, ...people.values]) {
      i.dispose();
    }
    covers.clear();
    people.clear();
  }
}
