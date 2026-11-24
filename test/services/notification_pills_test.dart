import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/notification_pills.dart';

void main() {
  group('output route', () {
    AudioDevice d(int type, [String name = '']) => AudioDevice(type: type, name: name);

    test('phone speaker when nothing else is connected', () {
      final r = outputRoute([d(AudioDevice.earpiece), d(AudioDevice.builtinSpeaker, 'Pixel')]);
      expect(r.kind, RouteKind.speaker);
      expect(r.label, 'Phone speaker');
    });

    test('bluetooth wins over the speaker and shows its name', () {
      final r = outputRoute([d(AudioDevice.builtinSpeaker), d(AudioDevice.bluetoothA2dp, 'WH-1000XM5')]);
      expect(r.kind, RouteKind.bluetooth);
      expect(r.label, 'WH-1000XM5');
    });

    test('bluetooth without a name still says bluetooth', () {
      expect(outputRoute([d(AudioDevice.bluetoothA2dp, '  ')]).label, 'Bluetooth headphones');
    });

    test('wired headphones beat the speaker, bluetooth beats wired', () {
      expect(outputRoute([d(AudioDevice.builtinSpeaker), d(AudioDevice.wiredHeadphones)]).label, 'Wired headphones');
      expect(outputRoute([d(AudioDevice.wiredHeadset), d(AudioDevice.bleHeadset, 'Buds')]).label, 'Buds');
    });

    test('car audio bus is a car', () {
      final r = outputRoute([d(AudioDevice.builtinSpeaker), d(AudioDevice.bus, 'Head unit')]);
      expect(r.kind, RouteKind.car);
      expect(r.label, 'Head unit');
      expect(outputRoute([d(AudioDevice.bus)]).label, 'Car');
    });

    test('usb and hdmi', () {
      expect(outputRoute([d(AudioDevice.usbHeadset, 'DAC')]).label, 'DAC');
      expect(outputRoute([d(AudioDevice.usbDevice)]).label, 'USB audio');
      expect(outputRoute([d(AudioDevice.hdmi)]).label, 'HDMI');
    });

    test('an empty list falls back to the speaker', () {
      expect(outputRoute(const []).kind, RouteKind.speaker);
    });

    test('parses the platform payload and skips malformed rows', () {
      final list = AudioDevice.parseList([
        {'type': 8, 'name': 'Buds'},
        {'type': 'x'},
        'junk',
      ]);
      expect(list.length, 1);
      expect(outputRoute(list).label, 'Buds');
    });

    test('subtext line', () {
      expect(routeSubtext(const OutputRoute(RouteKind.bluetooth, 'Buds')), 'Playing on Buds');
      expect(routeSubtext(const OutputRoute(RouteKind.speaker, 'Phone speaker')), 'Phone speaker');
    });
  });

  group('progress mapping', () {
    test('counted jobs give a fraction and a chip', () {
      final p = countedProgress(done: 2, total: 8);
      expect(p.max, 8);
      expect(p.value, 2);
      expect(p.chip, '2/8');
      expect(p.indeterminate, isFalse);
    });

    test('done never exceeds total; zero total is indeterminate', () {
      expect(countedProgress(done: 9, total: 8).value, 8);
      expect(countedProgress(done: 0, total: 0).indeterminate, isTrue);
    });

    test('fractional progress becomes percent', () {
      final p = fractionProgress(0.456);
      expect(p.max, 100);
      expect(p.value, 46);
      expect(p.chip, '46%');
      expect(fractionProgress(null).indeterminate, isTrue);
      expect(fractionProgress(3).value, 100);
      expect(fractionProgress(-1).value, 0);
    });
  });

  group('update gate', () {
    test('first update and the last one always go through', () {
      var t = DateTime(2026);
      final g = UpdateGate(const Duration(seconds: 2), () => t);
      expect(g.allow('a'), isTrue);
      expect(g.allow('b'), isFalse); // too soon
      expect(g.allow('c', force: true), isTrue);
    });

    test('an unchanged value is dropped, a changed one waits for the gap', () {
      var t = DateTime(2026);
      final g = UpdateGate(const Duration(seconds: 2), () => t);
      expect(g.allow('1/8'), isTrue);
      t = t.add(const Duration(seconds: 5));
      expect(g.allow('1/8'), isFalse);
      expect(g.allow('2/8'), isTrue);
      t = t.add(const Duration(milliseconds: 500));
      expect(g.allow('3/8'), isFalse);
      t = t.add(const Duration(seconds: 2));
      expect(g.allow('3/8'), isTrue);
    });

    test('reset lets the next update through', () {
      final g = UpdateGate(const Duration(seconds: 2), DateTime.now);
      g.allow('x');
      g.reset();
      expect(g.allow('x'), isTrue);
    });
  });

  group('notification buttons', () {
    test('classic keeps like, shuffle and repeat', () {
      expect(ButtonPreset.classic.extras, ['like', 'shuffle', 'repeat']);
    });

    test('every preset fits the three custom slots', () {
      for (final p in ButtonPreset.values) {
        expect(p.extras.length, lessThanOrEqualTo(3));
      }
    });

    test('parse falls back to classic', () {
      expect(ButtonPreset.parse('seek'), ButtonPreset.seek);
      expect(ButtonPreset.parse(null), ButtonPreset.classic);
      expect(ButtonPreset.parse('nope'), ButtonPreset.classic);
    });
  });

  group('seek by', () {
    test('clamps inside the song', () {
      const len = Duration(minutes: 3);
      expect(seekBy(const Duration(seconds: 5), -10, len), Duration.zero);
      expect(seekBy(const Duration(seconds: 100), 30, len), const Duration(seconds: 130));
      expect(seekBy(const Duration(seconds: 170), 30, len), const Duration(seconds: 179));
      expect(seekBy(const Duration(seconds: 50), 30, null), const Duration(seconds: 80));
    });
  });

  group('notice text', () {
    test('finished fetch of one song', () {
      final n = fetchedNotice(['a'], 'Africa', 'Toto')!;
      expect(n.title, 'Africa is in your library');
      expect(n.body, 'Toto · tap to play');
      expect(n.playIds, ['a']);
    });

    test('finished fetch of many names the group', () {
      final n = fetchedNotice(['a', 'b', 'c'], 'Rumours', 'Fleetwood Mac')!;
      expect(n.title, 'Rumours is in your library');
      expect(n.body, '3 songs · tap to play');
    });

    test('nothing landed means no notice', () {
      expect(fetchedNotice(const [], 'x', 'y'), isNull);
    });

    test('jam line', () {
      expect(jamLine(code: 'ABCD', people: 1), 'ABCD · just you');
      expect(jamLine(code: 'ABCD', people: 3), 'ABCD · 3 people');
    });

    test('play ids round trip through the intent extra', () {
      expect(parsePlayIds('a,b,,c'), ['a', 'b', 'c']);
      expect(parsePlayIds(null), isEmpty);
      expect(joinPlayIds(['a', 'b']), 'a,b');
    });
  });
}
