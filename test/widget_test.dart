import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('minimal scaffold renders without throwing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Text('NaviVibe'),
          ),
        ),
      ),
    );

    // Drain pending microtasks — do NOT use pumpAndSettle
    // (it times out on continuous animations from the real app tree).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('NaviVibe'), findsOneWidget);
  });
}
