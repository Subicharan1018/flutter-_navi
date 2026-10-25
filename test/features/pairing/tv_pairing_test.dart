import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/pairing/pair_crypto.dart';
import 'package:navivibe/features/pairing/pair_link.dart';
import 'package:navivibe/features/pairing/pair_relay.dart';
import 'package:navivibe/features/pairing/phone_pairing.dart';
import 'package:navivibe/features/pairing/tv_pairing.dart';

const _creds = PairCredentials(serverUrl: 'https://music.example', username: 'alice', password: 'secret');

/// An in-memory mailbox with the same rules as navivibe/pair.py.
class FakeRelay implements PairRelay {
  final Map<String, ({String pub, PairSealed? sealed})> boxes = {};
  int _n = 0;
  int polls = 0;
  PairRelayException? pollError;

  @override
  Future<PairTicket> create(String pub) async {
    final code = 'ABCD${23 + _n++}';
    boxes[code] = (pub: pub, sealed: null);
    return PairTicket(code, 300);
  }

  @override
  Future<PairPoll> poll(String code, String pub) async {
    polls++;
    if (pollError != null) throw pollError!;
    final box = boxes[code];
    if (box == null || box.pub != pub) return const PairGone();
    if (box.sealed == null) return const PairWaiting();
    boxes.remove(code);
    return PairReady(box.sealed!);
  }

  @override
  Future<String> keyFor(String code) async {
    final box = boxes[code];
    if (box == null) throw const PairRelayException(PairRelayProblem.notFound, 'That code isn’t active.');
    return box.pub;
  }

  @override
  Future<void> deposit(String code, PairSealed sealed) async {
    final box = boxes[code];
    if (box == null) throw const PairRelayException(PairRelayProblem.notFound, 'That code isn’t active.');
    if (box.sealed != null) throw const PairRelayException(PairRelayProblem.alreadyUsed, 'Already used.');
    boxes[code] = (pub: box.pub, sealed: sealed);
  }
}

/// A TV whose own timer never fires; the tests poll by hand.
TvPairing makeTv(FakeRelay relay, {PairSignIn? signIn, DateTime Function()? now}) => TvPairing(
      relay: relay,
      signIn: signIn ?? (_) async {},
      pollEvery: const Duration(hours: 1),
      now: now ?? DateTime.now,
    );

void main() {
  test('a code appears, the phone answers, the TV signs in', () async {
    final relay = FakeRelay();
    PairCredentials? signedIn;
    final tv = makeTv(relay, signIn: (c) async => signedIn = c);
    addTearDown(tv.dispose);

    expect(tv.value, isA<TvPairStarting>());
    await tv.start();
    final waiting = tv.value as TvPairWaiting;
    expect(waiting.code, hasLength(6));
    expect(waiting.link.code, waiting.code);

    await tv.pollNow(); // nothing yet
    expect(tv.value, isA<TvPairWaiting>());
    expect(relay.polls, 1);

    // The phone scans the QR (key known) and sends.
    final phone = PhonePairing(relay);
    final target = await phone.fromLink(PairLink.parse(waiting.link.uri)!);
    expect(target.keyFromQr, isTrue);
    await phone.send(target, _creds);

    await tv.pollNow();
    expect(tv.value, isA<TvPairDone>());
    expect(signedIn, _creds);
    expect(relay.boxes, isEmpty); // single use: the mailbox is gone
  });

  test('a typed code shows the same fingerprint on both devices', () async {
    final relay = FakeRelay();
    final tv = makeTv(relay);
    addTearDown(tv.dispose);
    await tv.start();
    final waiting = tv.value as TvPairWaiting;

    final target = await PhonePairing(relay).fromTypedCode(waiting.code.toLowerCase());
    expect(target.keyFromQr, isFalse);
    expect(target.fingerprint, waiting.fingerprint);
  });

  test('a wrong or malformed code is a clear error on the phone', () async {
    final relay = FakeRelay();
    await expectLater(PhonePairing(relay).fromTypedCode('ZZZZZZ'), throwsA(isA<PairRelayException>()));
    await expectLater(PhonePairing(relay).fromTypedCode('12'), throwsFormatException);
  });

  test('a code that runs out is replaced by a fresh one', () async {
    final relay = FakeRelay();
    var clock = DateTime(2030);
    final tv = makeTv(relay, now: () => clock);
    addTearDown(tv.dispose);
    await tv.start();
    final first = (tv.value as TvPairWaiting).code;

    clock = clock.add(const Duration(minutes: 6));
    await tv.pollNow();
    final second = tv.value;
    expect(second, isA<TvPairWaiting>());
    expect((second as TvPairWaiting).code, isNot(first));
  });

  test('a mailbox the server forgot also gets a fresh code', () async {
    final relay = FakeRelay();
    final tv = makeTv(relay);
    addTearDown(tv.dispose);
    await tv.start();
    final first = (tv.value as TvPairWaiting).code;
    relay.boxes.clear();
    await tv.pollNow();
    expect((tv.value as TvPairWaiting).code, isNot(first));
  });

  test('credentials that fail to verify show the reason, with a way to retry', () async {
    final relay = FakeRelay();
    final tv = makeTv(relay, signIn: (_) async => throw Exception('That username and password didn’t work.'));
    addTearDown(tv.dispose);
    await tv.start();
    final phone = PhonePairing(relay);
    await phone.send(await phone.fromLink((tv.value as TvPairWaiting).link), _creds);

    await tv.pollNow();
    expect((tv.value as TvPairFailed).message, 'That username and password didn’t work.');

    await tv.start(); // "Try again"
    expect(tv.value, isA<TvPairWaiting>());
  });

  test('something that will not decrypt is refused, not trusted', () async {
    final relay = FakeRelay();
    var signedIn = false;
    final tv = makeTv(relay, signIn: (_) async => signedIn = true);
    addTearDown(tv.dispose);
    await tv.start();
    final waiting = tv.value as TvPairWaiting;
    // Someone sealed to a different key.
    final other = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: other.publicKey, code: waiting.code, credentials: _creds);
    await relay.deposit(waiting.code, sealed);

    await tv.pollNow();
    expect(tv.value, isA<TvPairFailed>());
    expect(signedIn, isFalse);
  });

  test('a flaky network is tolerated, a dead one is reported', () async {
    final relay = FakeRelay();
    final tv = makeTv(relay);
    addTearDown(tv.dispose);
    await tv.start();

    relay.pollError = const PairRelayException(PairRelayProblem.network, 'Can’t reach the server.');
    for (var i = 0; i < TvPairing.maxNetworkFailures - 1; i++) {
      await tv.pollNow();
    }
    expect(tv.value, isA<TvPairWaiting>());

    await tv.pollNow();
    expect((tv.value as TvPairFailed).message, 'Can’t reach the server.');
  });

  test('a recovered network resets the failure count', () async {
    final relay = FakeRelay();
    final tv = makeTv(relay);
    addTearDown(tv.dispose);
    await tv.start();

    relay.pollError = const PairRelayException(PairRelayProblem.network, 'down');
    for (var i = 0; i < TvPairing.maxNetworkFailures - 1; i++) {
      await tv.pollNow();
    }
    relay.pollError = null;
    await tv.pollNow();
    relay.pollError = const PairRelayException(PairRelayProblem.network, 'down');
    for (var i = 0; i < TvPairing.maxNetworkFailures - 1; i++) {
      await tv.pollNow();
    }
    expect(tv.value, isA<TvPairWaiting>());
  });
}
