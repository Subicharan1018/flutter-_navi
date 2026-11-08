import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/widgets/shell/desktop/window_ground.dart';
import 'package:navivibe/widgets/ui/dock_ground.dart';

const _playing = AlbumPalette(
  deep: Color(0xFF301000),
  base: Color(0xFF8A4B2A), // brown
  vibrant: Color(0xFFFFB07A),
  glow: Color(0xFF402010),
);
const _pageBlue = Color(0xFF10284A);

Future<(Color, Color?)> _pump(WidgetTester tester, {required AlbumPalette? playing, Color? page}) async {
  DockGround.value.value = page;
  late Color bgBase;
  await tester.pumpWidget(ProviderScope(
    overrides: [windowPaletteProvider.overrideWithValue(playing)],
    child: MaterialApp(
      builder: (c, w) => ThemeTokens(tokens: AppThemeTokens.fallback, child: w!),
      home: DesktopWindowGround(
        child: Builder(builder: (context) {
          bgBase = ThemeTokens.of(context).bgBase;
          return const SizedBox.expand();
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(WindowGround), matching: find.byType(DecoratedBox)).first);
  final g = (box.decoration as BoxDecoration).gradient as LinearGradient?;
  return (bgBase, g?.colors.first);
}

void main() {
  tearDown(() => DockGround.value.value = null);

  testWidgets('the playing song is the one tint, even when the page has a cover of its own', (tester) async {
    final (bg, top) = await _pump(tester, playing: _playing, page: _pageBlue);
    expect(top, _playing.ground, reason: 'the gradient comes from the playing art');
    expect(bg, _playing.ground, reason: 'pages below use the same colour');
    expect(top, isNot(_pageBlue));
  });

  testWidgets('with nothing playing the page cover tints the window', (tester) async {
    final (bg, top) = await _pump(tester, playing: null, page: _pageBlue);
    expect(top, _pageBlue);
    expect(bg, _pageBlue);
  });

  testWidgets('a page without a cover (Settings) gets the playing tint, not black', (tester) async {
    final (bg, top) = await _pump(tester, playing: _playing, page: null);
    expect(top, _playing.ground);
    expect(bg, _playing.ground);
  });

  testWidgets('the gradient is one soft ramp: same hue, only darker toward the bottom', (tester) async {
    await _pump(tester, playing: _playing);
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(WindowGround), matching: find.byType(DecoratedBox)).first);
    final g = (box.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(g.colors.length, 2);
    expect(g.colors.last.computeLuminance(), lessThan(g.colors.first.computeLuminance()));
  });
}
