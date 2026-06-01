import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/screens/now_playing_screen.dart';

void main() {
  testWidgets('SoundBar with disableAnimations renders no transient callbacks', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: SoundBar(isPlaying: true, color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
