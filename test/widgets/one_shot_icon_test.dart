import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/ui/one_shot_icon.dart';

String? _assetOf(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image).first).image;
  final inner = image is ResizeImage ? image.imageProvider : image;
  return inner is AssetImage ? inner.assetName : null;
}

void main() {
  test('tab animations decode as finite animations (not endless loops)', () async {
    for (final name in const ['tab_home', 'tab_shuffle', 'tab_stats', 'tab_library']) {
      final bytes = await File('assets/icons/$name.webp').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      expect(codec.frameCount, greaterThan(30), reason: name);
      // -1 would mean "loop forever".
      expect(codec.repetitionCount, isNot(-1), reason: name);
      codec.dispose();
    }
  });

  testWidgets('rests on the still, plays once on demand, then settles back', (tester) async {
    final key = GlobalKey<OneShotIconState>();
    const duration = Duration(milliseconds: 1980);
    await tester.pumpWidget(MaterialApp(
      home: Center(child: OneShotIcon(key: key, name: 'tab_home', size: 26, duration: duration)),
    ));

    expect(_assetOf(tester), 'assets/icons/tab_home.png');

    key.currentState!.play();
    await tester.pump();
    expect(find.byType(Image), findsWidgets);
    expect(
      tester.widgetList<Image>(find.byType(Image)).map((i) {
        final p = i.image;
        return ((p is ResizeImage ? p.imageProvider : p) as AssetImage).assetName;
      }),
      contains('assets/icons/tab_home.webp'),
    );

    // Not continuous: once the animation's length has passed it stops.
    await tester.pump(duration + const Duration(milliseconds: 50));
    expect(_assetOf(tester), 'assets/icons/tab_home.png');
    expect(find.byType(Image), findsOneWidget);
  });
}
