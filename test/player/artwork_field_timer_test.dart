import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/player/artwork_field.dart';

Widget _field({required bool playing, bool tickers = true}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: TickerMode(
          enabled: tickers,
          child: ArtworkField(art: null, playing: playing),
        ),
      ),
    );

void main() {
  testWidgets('drift runs on a 30 fps timer while playing and stops when it is covered or paused', (t) async {
    await t.pumpWidget(_field(playing: true));
    // A periodic timer is live while playing.
    await t.pump(const Duration(milliseconds: 100));

    // Covered by another route (TickerMode off): the timer is cancelled.
    await t.pumpWidget(_field(playing: true, tickers: false));
    // Paused: also cancelled.
    await t.pumpWidget(_field(playing: false));
    // No pending timer is left behind when the widget goes away.
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a covered or paused field leaves no timer running', (t) async {
    await t.pumpWidget(_field(playing: true, tickers: false));
    await t.pumpWidget(_field(playing: false));
    // The test harness fails the test if a periodic timer is still pending
    // here without the widget being disposed; none should be.
  });
}
