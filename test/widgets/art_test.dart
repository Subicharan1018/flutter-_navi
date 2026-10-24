import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/widgets/art/empty_art.dart';
import 'package:navivibe/widgets/art/generated_cover.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

void main() {
  group('coverSeed', () {
    test('is case/whitespace-insensitive on the name', () {
      expect(coverSeed(' Road Trip '), coverSeed('road trip'));
    });

    test('ignores songs beyond the first six', () {
      final ids = List.generate(10, (i) => 'id$i');
      expect(coverSeed('a', ids), coverSeed('a', ids.take(6)));
    });

    test('differs when song ids differ', () {
      expect(coverSeed('a', ['1']), isNot(coverSeed('a', ['2'])));
    });
  });

  group('GeneratedCoverSpec', () {
    test('same seed -> identical spec', () {
      final a = GeneratedCoverSpec.fromSeed('mix|1,2,3');
      final b = GeneratedCoverSpec.derive('mix|1,2,3');
      expect(a.samples, b.samples);
      expect(a.motif, b.motif);
      expect(a.focusX, b.focusX);
      expect(a.inverted, b.inverted);
      expect(a.grainSeed, b.grainSeed);
    });

    test('fnv1a is stable', () {
      expect(fnv1a(''), 0x811c9dc5);
      expect(fnv1a('a'), 0xe40c292c);
    });

    test('samples span the full 0..1 range', () {
      final s = GeneratedCoverSpec.fromSeed('anything').samples;
      expect(s.length, GeneratedCoverSpec.sampleCount);
      expect(s.reduce((a, b) => a < b ? a : b), 0);
      expect(s.reduce((a, b) => a > b ? a : b), 1);
    });

    test('different seeds produce different covers', () {
      final sigs = {
        for (var i = 0; i < 40; i++)
          GeneratedCoverSpec.fromSeed('seed$i').samples.join(','),
      };
      expect(sigs.length, 40);
    });

    test('all motifs occur across seeds', () {
      final motifs = {
        for (var i = 0; i < 300; i++)
          GeneratedCoverSpec.fromSeed('m$i').motif,
      };
      expect(motifs, containsAll(CoverMotif.values));
    });
  });

  group('painting', () {
    Future<List<int>> render(String seed, Size size) async {
      final recorder = PictureRecorder();
      GeneratedCoverPainter(GeneratedCoverSpec.fromSeed(seed))
          .paint(Canvas(recorder), size);
      final image = await recorder
          .endRecording()
          .toImage(size.width.toInt(), size.height.toInt());
      final bytes = await image.toByteData();
      return bytes!.buffer.asUint8List();
    }

    test('same seed -> identical pixels', () async {
      final a = await render('Road Trip|a,b', const Size(120, 120));
      final b = await render('Road Trip|a,b', const Size(120, 120));
      expect(a, b);
    });

    test('different seeds -> different pixels', () async {
      final a = await render('one', const Size(120, 120));
      final b = await render('two', const Size(120, 120));
      expect(a, isNot(b));
    });

    test('small and large sizes both paint without error', () async {
      for (final seed in ['a', 'b', 'c', 'd', 'e', 'f']) {
        await render(seed, const Size(48, 48));
        await render(seed, const Size(320, 320));
      }
    });
  });

  test('glyph painter repaints only on change', () {
    const p = NaviGlyphPainter(NaviGlyph.home, Color(0xFFFFFFFF), false);
    expect(p.shouldRepaint(p), isFalse);
    expect(
      p.shouldRepaint(
        const NaviGlyphPainter(NaviGlyph.home, Color(0xFFFFFFFF), true),
      ),
      isTrue,
    );
  });

  test('every motif paints at list and hero size, deterministically', () async {
    final byMotif = <CoverMotif, String>{};
    for (var i = 0; i < 400 && byMotif.length < CoverMotif.values.length; i++) {
      byMotif.putIfAbsent(GeneratedCoverSpec.fromSeed('probe$i').motif, () => 'probe$i');
    }
    expect(byMotif.length, CoverMotif.values.length);
    for (final seed in byMotif.values) {
      for (final size in const [Size(48, 48), Size(300, 300)]) {
        List<int> once() {
          final rec = PictureRecorder();
          GeneratedCoverPainter(GeneratedCoverSpec.fromSeed(seed)).paint(Canvas(rec), size);
          return [rec.endRecording().approximateBytesUsed];
        }
        expect(once(), once());
      }
    }
  });

  test('every glyph and empty illustration paints in both forms', () {
    for (final g in NaviGlyph.values) {
      for (final filled in [false, true]) {
        NaviGlyphPainter(g, const Color(0xFFFFFFFF), filled)
            .paint(Canvas(PictureRecorder()), const Size(24, 24));
      }
    }
    for (final k in EmptyArtKind.values) {
      EmptyArtPainter(k, const Color(0x99FFFFFF), const Color(0xFFFFFFFF))
          .paint(Canvas(PictureRecorder()), const Size(160, 120));
    }
    expect(NaviGlyph.values.length, greaterThanOrEqualTo(18));
    expect(CoverMotif.values.length, greaterThanOrEqualTo(12));
    expect(EmptyArtKind.values.length, greaterThanOrEqualTo(7));
  });
}
