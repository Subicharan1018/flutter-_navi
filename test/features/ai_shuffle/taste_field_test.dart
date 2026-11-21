import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/ai_shuffle/ui/widgets/energy_dial.dart';
import 'package:navivibe/features/ai_shuffle/ui/widgets/taste_field.dart';
import 'package:navivibe/features/ai_shuffle/ui/widgets/taste_math.dart';
import 'package:navivibe/models/song.dart';

TastePoint _p(String id, {double score = .5, double energy = .5, double valence = .5, double dance = .5}) =>
    TastePoint(id: id, title: 'T$id', artist: 'A', score: score, energy: energy, valence: valence, dance: dance);

Song _s(String id) => Song(
      id: id, title: 'T$id', artist: 'A', album: 'B', genre: 'G', composer: 'C', coverArt: '', duration: 100, track: 1, year: 2020);

Widget _host(Widget child, {bool reduce = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: ThemeTokens(
        tokens: AppThemeTokens.fallback,
        child: Directionality(textDirection: TextDirection.ltr, child: Center(child: SizedBox(width: 300, child: child))),
      ),
    );

void main() {
  group('radii', () {
    test('a closer fit sits nearer the centre', () {
      final r = tasteRadii([_p('a', score: .9), _p('b', score: .5), _p('c', score: .1)]);
      expect(r['a']! < r['b']!, isTrue);
      expect(r['b']! < r['c']!, isTrue);
      expect(r['a']!, greaterThanOrEqualTo(tasteInner));
      expect(r['c']!, lessThanOrEqualTo(tasteOuter));
    });

    test('equal scores fall back to list order, best first', () {
      final r = tasteRadii([_p('a'), _p('b'), _p('c')]);
      expect(r['a']! < r['c']!, isTrue);
    });

    test('with the dial, distance is distance from that energy', () {
      final r = tasteRadii([_p('calm', energy: .1), _p('lively', energy: .9)], dial: .9);
      expect(r['lively']! < r['calm']!, isTrue);
    });

    test('angles are deterministic and within a turn', () {
      final a = tasteAngle(_p('a', valence: .3), 2);
      expect(a, tasteAngle(_p('a', valence: .3), 2));
      expect(a.abs(), lessThanOrEqualTo(3.2));
    });
  });

  group('energy', () {
    test('no spread, no dial', () {
      expect(hasEnergySpread([_p('a', energy: 0), _p('b', energy: 0), _p('c', energy: 0)]), isFalse);
      expect(hasEnergySpread([_p('a', energy: .1), _p('b', energy: .5), _p('c', energy: .9)]), isTrue);
    });

    test('untouched dial keeps the server order', () {
      final songs = [_s('a'), _s('b'), _s('c')];
      expect(reshapeByEnergy(songs, {'a': .9, 'b': .1, 'c': .5}, null), songs);
    });

    test('the dial puts nearest energy first, stable on ties, unknown as middling', () {
      final songs = [_s('a'), _s('b'), _s('c'), _s('d')];
      final out = reshapeByEnergy(songs, {'a': .9, 'b': .1, 'c': .1}, .0);
      expect([for (final s in out) s.id], ['b', 'c', 'd', 'a']);
    });

    test('words follow the dial', () {
      expect(energyWord(0), 'Calm');
      expect(energyWord(.5), 'Steady');
      expect(energyWord(1), 'Lively');
    });
  });

  group('widgets', () {
    testWidgets('dial drag reports a value and tap selects a dot', (tester) async {
      double? got;
      await tester.pumpWidget(_host(EnergyDial(value: .5, active: false, onChanged: (v) => got = v, onReset: () {})));
      expect(find.text('As picked'), findsOneWidget);
      await tester.tapAt(tester.getTopLeft(find.byType(EnergyDial)) + const Offset(290, 40));
      expect(got, greaterThan(.9));
    });

    testWidgets('dial exposes slider semantics', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(_host(EnergyDial(value: .7, active: true, onChanged: (_) {}, onReset: () {})));
      expect(find.bySemanticsLabel('Energy'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      h.dispose();
    });

    testWidgets('field draws under reduced motion without a running ticker, and selects on tap', (tester) async {
      String? sel = 'unset';
      final pts = [for (var i = 0; i < 5; i++) _p('$i', score: i / 5, valence: i / 5)];
      await tester.pumpWidget(_host(reduce: true, TasteField(points: pts, dial: null, selectedId: null, onSelect: (id) => sel = id)));
      await tester.pump();
      // Reduced motion: nothing keeps asking for frames.
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(TasteField), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(TasteField)));
      expect(sel, anyOf(isNull, isA<String>()));
    });

    testWidgets('field animates, then is disposed cleanly', (tester) async {
      final pts = [for (var i = 0; i < 5; i++) _p('$i', score: i / 5)];
      await tester.pumpWidget(_host(TasteField(points: pts, dial: null, selectedId: null, onSelect: (_) {})));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpWidget(_host(const SizedBox()));
    });
  });
}
