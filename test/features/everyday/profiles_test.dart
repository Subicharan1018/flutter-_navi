import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navivibe/features/everyday/dont_count.dart';
import 'package:navivibe/features/everyday/profiles.dart';
import 'package:navivibe/features/everyday/profiles_providers.dart';
import 'package:navivibe/services/scrobble_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

class _Api extends Mock implements SubsonicService {}

class _Conn extends Mock implements Connectivity {}

class MemBackend implements ProfilesBackend {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String v) async => value = v;
}

const srv = 'https://music.example.com';

void main() {
  group('Profiles', () {
    test('remember adds a new person, with the username as the name', () {
      final p = const Profiles().remember(srv, 'Asha', 'pw1');
      expect(p.all, hasLength(1));
      expect(p.all.single.displayName, 'Asha');
      expect(p.all.single.initial, 'A');
    });

    test('a known person gets the new password and keeps their name', () {
      var p = const Profiles().remember(srv, 'asha', 'old');
      p = p.rename(srv, 'asha', 'Amma');
      p = p.remember('$srv/', 'ASHA', 'new'); // same person: case and trailing slash differ
      expect(p.all, hasLength(1));
      expect(p.all.single.password, 'new');
      expect(p.all.single.displayName, 'Amma');
    });

    test('the same login again changes nothing (same object)', () {
      final p = const Profiles().remember(srv, 'a', 'x');
      expect(identical(p.remember(srv, 'a', 'x'), p), isTrue);
    });

    test('empty fields are ignored', () {
      const p = Profiles();
      expect(p.remember('', 'a', 'x').all, isEmpty);
      expect(p.remember(srv, ' ', 'x').all, isEmpty);
      expect(p.remember(srv, 'a', '').all, isEmpty);
    });

    test('forServer keeps profiles apart per server, in first-seen order', () {
      final p = const Profiles()
          .remember(srv, 'b', '1')
          .remember('https://other', 'x', '1')
          .remember(srv, 'a', '1');
      expect(p.forServer(srv).map((e) => e.username), ['b', 'a']);
      expect(p.forServer('HTTPS://MUSIC.EXAMPLE.COM/').length, 2);
    });

    test('forget removes only that person; rename trims', () {
      var p = const Profiles().remember(srv, 'a', '1').remember(srv, 'b', '1');
      p = p.rename(srv, 'a', '  Appa ');
      expect(p.find(srv, 'a')!.displayName, 'Appa');
      p = p.forget(srv, 'a');
      expect(p.all.map((e) => e.username), ['b']);
    });

    test('a blank name falls back to the username', () {
      final p = const Profiles().remember(srv, 'asha', '1').rename(srv, 'asha', '   ');
      expect(p.all.single.displayName, 'asha');
    });

    test('encode/decode round trip; junk and duplicates are dropped', () {
      final p = const Profiles().remember(srv, 'a', '1').rename(srv, 'a', 'Amma').remember(srv, 'b', '2');
      final back = Profiles.decode(p.encode());
      expect(back.all.map((e) => (e.username, e.password, e.displayName)), [('a', '1', 'Amma'), ('b', '2', 'b')]);
      expect(Profiles.decode('nope').all, isEmpty);
      expect(Profiles.decode(null).all, isEmpty);
      expect(Profiles.decode('[{"x":1},{"s":"$srv","u":"a","p":"1"},{"s":"$srv","u":"A","p":"2"}]').all, hasLength(1));
    });
  });

  group('ProfilesNotifier', () {
    test('persists and survives a restart', () {
      final backend = MemBackend();
      ProviderContainer make() => ProviderContainer(overrides: [profilesBackendProvider.overrideWithValue(backend)]);
      final c = make();
      addTearDown(c.dispose);
      c.read(profilesProvider.notifier).remember(srv, 'asha', 'pw');
      final c2 = make();
      addTearDown(c2.dispose);
      final p = c2.read(profilesProvider).all.single;
      expect((p.username, p.password), ('asha', 'pw'));
      c2.read(profilesProvider.notifier).forget(p);
      expect(c2.read(profilesProvider).all, isEmpty);
      expect(Profiles.decode(backend.value).all, isEmpty);
    });
  });

  group("Don't count", () {
    test('is a session switch, off by default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(dontCountProvider), isFalse);
      c.read(dontCountProvider.notifier).toggle();
      expect(c.read(dontCountProvider), isTrue);
      c.read(dontCountProvider.notifier).set(false);
      expect(c.read(dontCountProvider), isFalse);
    });

    test('while on, the scrobble service sends nothing; when off again it does', () async {
      final api = _Api();
      final conn = _Conn();
      when(() => conn.checkConnectivity()).thenAnswer((_) async => [ConnectivityResult.wifi]);
      when(() => api.scrobble(any(), submission: any(named: 'submission'))).thenAnswer((_) async {});
      var counting = false;
      final svc = ScrobbleService(api, conn, isCounting: () => counting);

      svc.nowPlaying('s1');
      svc.submit('s1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      verifyNever(() => api.scrobble(any(), submission: any(named: 'submission')));

      counting = true;
      svc.nowPlaying('s1');
      svc.submit('s1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      verify(() => api.scrobble('s1', submission: false)).called(1);
      verify(() => api.scrobble('s1', submission: true)).called(1);
    });
  });
}
