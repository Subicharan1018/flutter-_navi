/// The Smart Shuffle glyph next to plain shuffle at 16 / 24 / 32 / 48 pt, in
/// outline and selected forms, on the app's black and on a light ground.
///
///   flutter test test/goldens/smart_shuffle_icon_test.dart --update-goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

Widget _row(Color ground, Color ink) => ColoredBox(
      color: ground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in [NaviGlyph.shuffle, NaviGlyph.smartShuffle])
              for (final filled in [false, true])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      for (final s in [16.0, 24.0, 32.0, 48.0])
                        Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: NaviIcon(g, size: s, color: ink, filled: filled),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('Smart Shuffle glyph on dark and light', (tester) async {
    await tester.binding.setSurfaceSize(const Size(340, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Expanded(child: RepaintBoundary(key: const Key('dark'), child: _row(const Color(0xFF000000), Colors.white))),
            Expanded(child: RepaintBoundary(key: const Key('light'), child: _row(const Color(0xFFF2F2F7), const Color(0xFF111111)))),
          ],
        ),
      ),
    );
    await expectLater(find.byKey(const Key('dark')), matchesGoldenFile('smart_shuffle/dark.png'));
    await expectLater(find.byKey(const Key('light')), matchesGoldenFile('smart_shuffle/light.png'));
  });
}
