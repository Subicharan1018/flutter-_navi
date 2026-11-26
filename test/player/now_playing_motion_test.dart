// Now Playing's one layout motion (player alone <-> Lyrics/Queue open), its
// reduced-motion path, the wide layout's two columns, and the name of the
// audio output.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/motion.dart';
import 'package:navivibe/player/output_button.dart';
import 'package:navivibe/player/pane_flight.dart';
import 'package:navivibe/services/output_route.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  late final PaneFlight flight = PaneFlight(this);

  @override
  void dispose() {
    flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Future<(_HostState, BuildContext)> _pumpHost(WidgetTester tester, {bool motion = true, bool systemReduced = false}) async {
  Widget child = const _Host();
  child = MotionScope.resolve(
    level: motion ? MotionLevel.full : MotionLevel.reduced,
    systemReduced: systemReduced,
    child: child,
  );
  await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: child));
  final element = tester.element(find.byType(_Host));
  return (tester.state<_HostState>(find.byType(_Host)), element);
}

void main() {
  group('pane flight', () {
    testWidgets('travels, and finishes exactly on open and exactly on closed', (tester) async {
      final (host, context) = await _pumpHost(tester);
      final p = host.flight.position;

      host.flight.to(context, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(p.value, inExclusiveRange(0.05, 0.95), reason: 'mid-flight is between the two layouts');
      await tester.pumpAndSettle();
      expect(p.value, 1.0);

      host.flight.to(context, 0);
      await tester.pumpAndSettle();
      // "Almost 0" would leave the cover acting as if a pane were still open.
      expect(p.value, 0.0);
    });

    testWidgets('a second tap mid-flight turns it around without a jump', (tester) async {
      final (host, context) = await _pumpHost(tester);
      final p = host.flight.position;

      host.flight.to(context, 1);
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final before = p.value;
      final speed = p.velocity;
      expect(speed, greaterThan(0));

      host.flight.to(context, 0);
      await tester.pump();
      expect(p.value, closeTo(before, 0.001), reason: 'it carries on from where it was');
      await tester.pump(const Duration(milliseconds: 8));
      expect(p.value, greaterThan(before), reason: 'and keeps its speed for a moment before turning');
      var last = p.value;
      var peak = last;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect((p.value - last).abs(), lessThan(0.15), reason: 'no frame jumps');
        last = p.value;
        if (last > peak) peak = last;
      }
      expect(peak, lessThan(1));
      expect(p.value, 0.0);
    });

    for (final (label, motion, system) in const [
      ('Settings > Motion is Reduced', false, false),
      ('the system removes animations', true, true),
    ]) {
      testWidgets('nothing travels when $label: the new layout fades in', (tester) async {
        final (host, context) = await _pumpHost(tester, motion: motion, systemReduced: system);

        host.flight.to(context, 1);
        expect(host.flight.position.value, 1.0, reason: 'at once');
        expect(host.flight.position.isAnimating, isFalse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(host.flight.settle.value, inExclusiveRange(0.0, 1.0));
        await tester.pumpAndSettle();
        expect(host.flight.settle.value, 1.0);

        host.flight.to(context, 0);
        expect(host.flight.position.value, 0.0);
        await tester.pumpAndSettle();
      });
    }

    test('the pane waits for the cover, and the mode row lands in order', () {
      expect(paneArrival(0), 0);
      expect(paneArrival(0.2), 0);
      expect(paneArrival(1), 1);
      for (var i = 0; i < 4; i++) {
        expect(staggeredArrival(0.3, i), 0);
        expect(staggeredArrival(1, i), 1, reason: 'item $i is at rest when open');
      }
      expect(staggeredArrival(0.6, 0), greaterThan(staggeredArrival(0.6, 3)));
    });
  });

  group('wide layout', () {
    const window = Size(1440, 800);

    test('alone, the player stands in the middle', () {
      final g = WideGeometry.at(window, 0, maxPlayer: 440);
      expect(g.player.center.dx, window.width / 2);
      expect(g.player.width, 440);
    });

    test('open, the player sits left and the pane beside it without overlap', () {
      final g = WideGeometry.at(window, 1, maxPlayer: 440);
      expect(g.player.center.dx, lessThan(window.width / 2));
      expect(g.pane.left, greaterThanOrEqualTo(g.player.right + WideGeometry.gap - 0.5));
      expect(g.pane.right, closeTo(window.width - WideGeometry.sidePad, 0.5));
    });

    test('in between, both move steadily and the pane keeps its size', () {
      var last = WideGeometry.at(window, 0, maxPlayer: 440);
      final width = WideGeometry.at(window, 1, maxPlayer: 440).pane.width;
      for (var i = 1; i <= 20; i++) {
        final g = WideGeometry.at(window, i / 20, maxPlayer: 440);
        expect(g.player.left, lessThan(last.player.left));
        expect(g.pane.left, lessThanOrEqualTo(last.pane.left));
        expect(g.pane.width, width, reason: 'lyrics are never re-laid out while moving');
        last = g;
      }
    });

    test('a narrow window shrinks the columns instead of overflowing', () {
      for (final t in [0.0, 0.5, 1.0]) {
        final g = WideGeometry.at(const Size(820, 500), t, maxPlayer: 440);
        expect(g.player.left, greaterThanOrEqualTo(0));
        expect(g.player.right, lessThanOrEqualTo(820));
      }
    });
  });

  group('output', () {
    AudioDevice d(int type, [String name = '']) => AudioDevice(type: type, name: name);

    test('names the route Android prefers', () {
      expect(outputRoute([d(AudioDevice.earpiece), d(AudioDevice.builtinSpeaker, 'Pixel')]), OutputRoute.speaker);
      expect(outputRoute([d(AudioDevice.builtinSpeaker), d(AudioDevice.bluetoothA2dp, 'WH-1000XM5')]).label, 'WH-1000XM5');
      expect(outputRoute([d(AudioDevice.bluetoothA2dp, '  ')]).label, 'Bluetooth headphones');
      expect(outputRoute([d(AudioDevice.wiredHeadphones, 'CPH2585')]).label, 'Wired headphones');
      expect(outputRoute([d(AudioDevice.wiredHeadset), d(AudioDevice.bleHeadset, 'Buds')]).label, 'Buds');
      expect(outputRoute([d(AudioDevice.usbHeadset, 'DAC')]).label, 'DAC');
      expect(outputRoute([d(AudioDevice.hdmi)]).label, 'HDMI');
      expect(outputRoute([d(AudioDevice.bus, 'Head unit')]).kind, RouteKind.car);
      expect(outputRoute(const []), OutputRoute.speaker);
    });

    test('reads the platform payload and skips malformed rows', () {
      final list = AudioDevice.parseList([
        {'type': 8, 'name': 'Buds'},
        {'type': 'x'},
        'junk',
      ]);
      expect(list.single.name, 'Buds');
      expect(AudioDevice.parseList(null), isEmpty);
    });

    test('the button says where the sound is', () {
      const buds = OutputRoute(RouteKind.bluetooth, 'Buds');
      expect(
        outputBadge(passive: false, hostName: null, route: buds, sharing: true),
        const OutputBadge(NaviGlyph.headphones, 'Buds'),
      );
      expect(
        outputBadge(passive: false, hostName: null, route: OutputRoute.speaker, sharing: false),
        const OutputBadge(NaviGlyph.phone, 'Phone speaker'),
      );
      // Another device in the session plays: its name wins over this route.
      expect(
        outputBadge(passive: true, hostName: 'Living room PC', route: buds, sharing: false),
        const OutputBadge(NaviGlyph.speaker, 'Living room PC'),
      );
      // A platform that doesn't report outputs says nothing unless shared.
      expect(outputBadge(passive: false, hostName: null, route: null, sharing: false).label, isNull);
      expect(outputBadge(passive: false, hostName: null, route: null, sharing: true).label, 'This device');
    });
  });
}
