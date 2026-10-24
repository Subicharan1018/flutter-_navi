import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:navivibe/player/artwork.dart';

void main() {
  testWidgets('a cover load completes and yields a palette (no self-await deadlock)', (tester) async {
    final cover = img.Image(width: 32, height: 32);
    img.fill(cover, color: img.ColorRgb8(200, 60, 30));
    final png = Uint8List.fromList(img.encodePng(cover));
    debugCoverImageOverride = (url, key) => MemoryImage(png);
    addTearDown(() => debugCoverImageOverride = null);

    final data = await tester.runAsync(
      () => ArtworkRepository.instance.load('cover_repro', 'cover://repro').timeout(const Duration(seconds: 10)),
    );

    expect(data, isNotNull, reason: 'the load must complete, not wait on itself');
    // A red-orange cover gives a warm, non-fallback palette.
    final hue = HSLColor.fromColor(data!.palette.base).hue;
    expect(hue, inInclusiveRange(0, 40));
  });
}
