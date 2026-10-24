import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Renders the [RepaintBoundary] behind [key] to a PNG in the temp folder, at
/// [width] pixels wide (1080 is what social apps expect). Null when the
/// boundary isn't on screen or the render fails, so callers can still share
/// the text alone.
Future<File?> renderCardPng(GlobalKey key, {required double logicalWidth, required String name, double width = 1080}) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: width / logicalWidth);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name.png');
    return await file.writeAsBytes(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}
