import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/lyrics/controllers/lyrics_controller.dart';
import 'package:navivibe/lyrics/models/lyric_line.dart';
import 'package:navivibe/player/lyric_gap_dots.dart';
import 'package:navivibe/player/lyrics_motion.dart';
import 'package:navivibe/player/lyrics_pane.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;

class _Lyrics extends LyricsController {
  @override
  LyricsState build() => LyricsState(
        status: LyricsStatus.synced,
        activeLineIndex: -1,
        lyrics: SyncedLyrics(lines: [
          for (var i = 0; i < 40; i++) LyricLine(timestamp: Duration(seconds: 2 + i * 4), text: 'Placeholder line $i'),
        ]),
      );

  void setActive(int i) => state = state.copyWith(activeLineIndex: i);
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  _Player()
      : super(const PlayerState(
          queue: [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

Widget _host({double textScale = 1, bool reduceMotion = false, Size size = const Size(390, 760)}) {
  return ProviderScope(
    overrides: [
      lyricsControllerProvider.overrideWith(_Lyrics.new),
      playerProvider.overrideWith((ref) => _Player()),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale), disableAnimations: reduceMotion),
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: LyricsPane(style: NowPlayingStyle.onArtwork),
        ),
      ),
    ),
  );
}

Finder _motionOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(LyricLineMotion)).first;

double _scaleOf(WidgetTester t, String text) => t
    .widget<Transform>(find.descendant(of: _motionOf(text), matching: find.byType(Transform)).first)
    .transform
    .storage[0];

double _opacityOf(WidgetTester t, String text) =>
    t.widget<Opacity>(find.descendant(of: _motionOf(text), matching: find.byType(Opacity)).first).opacity;

void main() {
  group('LyricsMotion maths', () {
    test('the sung line is full size, every other line sits at the rest scale', () {
      expect(LyricsMotion.scaleFor(0), 1);
      expect(LyricsMotion.scaleFor(1), closeTo(LyricsMotion.restScale, 1e-9));
      expect(LyricsMotion.scaleFor(-3), closeTo(LyricsMotion.restScale, 1e-9));
      expect(LyricsMotion.scaleFor(0.5), closeTo((1 + LyricsMotion.restScale) / 2, 1e-9));
    });

    test('opacity and blur fall off with distance, and are continuous', () {
      expect(LyricsMotion.opacityFor(0), 1);
      expect(LyricsMotion.blurFor(0), 0);
      for (var d = 0.0; d < 5; d += 0.5) {
        expect(LyricsMotion.opacityFor(d + 0.5), lessThanOrEqualTo(LyricsMotion.opacityFor(d)));
        expect(LyricsMotion.blurFor(d + 0.5), greaterThanOrEqualTo(LyricsMotion.blurFor(d)));
      }
      // Lines already sung fade a little further than the ones still to come.
      expect(LyricsMotion.opacityFor(-1), lessThan(LyricsMotion.opacityFor(1)));
    });

    test('the target offset puts a line a third of the way down, inside the scroll range', () {
      expect(
        LyricsMotion.scrollTarget(lineTop: 1000, lineHeight: 40, viewport: 700, minExtent: 0, maxExtent: 5000),
        closeTo(1000 - (700 - 40) * 0.3, 1e-9),
      );
      expect(LyricsMotion.scrollTarget(lineTop: 10, lineHeight: 40, viewport: 700, minExtent: 0, maxExtent: 5000), 0);
      expect(LyricsMotion.scrollTarget(lineTop: 9000, lineHeight: 40, viewport: 700, minExtent: 0, maxExtent: 5000), 5000);
    });

    test('moving on one line staggers; a jump of more than one does not', () {
      expect(LyricsMotion.isSeek(3, 4), isFalse);
      expect(LyricsMotion.isSeek(3, 9), isTrue);
      expect(LyricsMotion.staggerFor(3, 9), Duration.zero);
      expect(LyricsMotion.staggerFor(2, 1), LyricsMotion.staggerStep);
      expect(LyricsMotion.staggerFor(5, 4), LyricsMotion.staggerStep * 4);
      expect(LyricsMotion.staggerFor(1, 0), Duration.zero);
    });

    test('gap dots fill one by one and only long silences get them', () {
      expect(gapFill(0, 9000, 0), 0);
      expect(gapFill(0, 9000, 4500), closeTo(1.5, 1e-9));
      expect(gapFill(0, 9000, 20000), 3);
      expect(isInstrumentalGap(Duration.zero, const Duration(seconds: 3)), isFalse);
      expect(isInstrumentalGap(Duration.zero, const Duration(seconds: 5)), isTrue);
    });
  });

  group('LyricsPane motion', () {
    late _Lyrics ctl;

    Future<ProviderContainer> pump(WidgetTester t, Widget w) async {
      await t.pumpWidget(w);
      await t.pump();
      final c = ProviderScope.containerOf(t.element(find.byType(LyricsPane)));
      ctl = c.read(lyricsControllerProvider.notifier) as _Lyrics;
      return c;
    }

    testWidgets('the sung line grows to full size and the rest shrink, with no relayout', (t) async {
      await pump(t, _host());
      final before = t.getSize(find.text('Placeholder line 3'));
      ctl.setActive(3);
      await t.pump();
      await t.pump(const Duration(milliseconds: 900));
      expect(_scaleOf(t, 'Placeholder line 3'), closeTo(1, 1e-6));
      expect(_scaleOf(t, 'Placeholder line 4'), closeTo(LyricsMotion.restScale, 1e-6));
      expect(_opacityOf(t, 'Placeholder line 3'), 1);
      expect(_opacityOf(t, 'Placeholder line 4'), lessThan(0.6));
      // The text box itself never changed size: only a transform moved.
      expect(t.getSize(find.text('Placeholder line 3')), before);
    });

    testWidgets('the sung line settles a third of the way down the pane', (t) async {
      await pump(t, _host());
      ctl.setActive(12);
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      final pane = t.getRect(find.byType(LyricsPane));
      final top = t.getRect(find.ancestor(of: find.text('Placeholder line 12'), matching: find.byType(Padding)).first).top;
      final expected = pane.top + (pane.height - 40) * LyricsMotion.anchor;
      expect(top, closeTo(expected, 45)); // line height is a little over 40
    });

    testWidgets('the scroll glides: it is mid-way after a few frames and has not jumped', (t) async {
      await pump(t, _host());
      ctl.setActive(1);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      final scrollable = find.byType(Scrollable).first;
      double offset() => t.state<ScrollableState>(scrollable).position.pixels;
      final start = offset();
      ctl.setActive(2);
      await t.pump();
      await t.pump(const Duration(milliseconds: 80));
      final mid = offset();
      await t.pump(const Duration(seconds: 2));
      final end = offset();
      expect(end, greaterThan(start));
      expect(mid, greaterThan(start - 0.5));
      expect(mid, lessThan(end));
    });

    testWidgets('a jump (seek) lands quicker than a glide and without the stagger', (t) async {
      await pump(t, _host());
      ctl.setActive(2);
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      ctl.setActive(20);
      await t.pump();
      await t.pump(LyricsMotion.seekGlide + const Duration(milliseconds: 20));
      // The far line has finished growing by the time a normal glide is half done.
      expect(_scaleOf(t, 'Placeholder line 20'), closeTo(1, 1e-6));
    });

    testWidgets('reduced motion moves instantly: no animation left running', (t) async {
      await pump(t, _host(reduceMotion: true));
      ctl.setActive(10);
      await t.pump();
      await t.pump(); // one frame to settle the post-frame follow
      expect(_scaleOf(t, 'Placeholder line 10'), 1);
      expect(_scaleOf(t, 'Placeholder line 11'), closeTo(LyricsMotion.restScale, 1e-6));
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('no overflow at text scale 1.3, on a phone and a wide pane', (t) async {
      for (final size in const [Size(390, 760), Size(900, 700)]) {
        await pump(t, _host(textScale: 1.3, size: size));
        ctl.setActive(5);
        await t.pump();
        await t.pump(const Duration(seconds: 2));
        expect(t.takeException(), isNull);
      }
    });
  });
}
