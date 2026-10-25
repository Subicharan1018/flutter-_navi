import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/pairing/pair_crypto.dart';
import 'package:navivibe/features/pairing/pair_link.dart';

const _creds = PairCredentials(serverUrl: 'https://music.example', username: 'alice', password: 'p@ss wörd/1');

void main() {
  test('what the phone seals, only the TV opens', () async {
    final tv = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    expect(await PairCrypto.open(keys: tv, code: 'K7M4PQ', sealed: sealed), _creds);
  });

  test('the relay never holds anything readable', () async {
    final tv = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    final stored = jsonEncode(sealed.toJson());
    for (final secret in ['alice', 'p@ss', 'music.example']) {
      expect(stored.contains(secret), isFalse);
      expect(utf8.decode(unb64url(sealed.ct), allowMalformed: true).contains(secret), isFalse);
    }
    expect(unb64url(sealed.epk), hasLength(32));
    expect(unb64url(sealed.nonce), hasLength(12));
    expect(stored.length, lessThan(2048));
  });

  test('another TV cannot open it', () async {
    final tv = await PairCrypto.newKeyPair();
    final other = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    expect(
      () => PairCrypto.open(keys: other, code: 'K7M4PQ', sealed: sealed),
      throwsA(isA<PairDecryptException>()),
    );
  });

  test('it is bound to the code it was sealed for', () async {
    final tv = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    expect(
      () => PairCrypto.open(keys: tv, code: 'ZZZZZZ', sealed: sealed),
      throwsA(isA<PairDecryptException>()),
    );
  });

  test('any tampering is refused', () async {
    final tv = await PairCrypto.newKeyPair();
    final sealed = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);

    final ct = unb64url(sealed.ct)..[3] ^= 1;
    final flipped = PairSealed(epk: sealed.epk, nonce: sealed.nonce, ct: b64url(ct));
    final swappedKey = PairSealed(epk: b64url((await PairCrypto.newKeyPair()).publicKey), nonce: sealed.nonce, ct: sealed.ct);
    final truncated = PairSealed(epk: sealed.epk, nonce: sealed.nonce, ct: b64url(unb64url(sealed.ct).sublist(0, 10)));
    final junk = PairSealed(epk: '!!', nonce: sealed.nonce, ct: sealed.ct);

    for (final bad in [flipped, swappedKey, truncated, junk]) {
      expect(() => PairCrypto.open(keys: tv, code: 'K7M4PQ', sealed: bad), throwsA(isA<PairDecryptException>()));
    }
  });

  test('two seals of the same login differ (fresh key and nonce each time)', () async {
    final tv = await PairCrypto.newKeyPair();
    final a = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    final b = await PairCrypto.seal(tvPublic: tv.publicKey, code: 'K7M4PQ', credentials: _creds);
    expect(a.epk, isNot(b.epk));
    expect(a.nonce, isNot(b.nonce));
    expect(a.ct, isNot(b.ct));
  });

  test('credentials with the wrong shape are not accepted', () {
    expect(() => PairCredentials.fromJson({'v': 2, 's': 'a', 'u': 'b', 'p': 'c'}), throwsFormatException);
    expect(() => PairCredentials.fromJson({'v': 1, 's': 'a', 'u': '', 'p': 'c'}), throwsFormatException);
    expect(() => PairCredentials.fromJson('nope'), throwsFormatException);
  });

  test('the fingerprint is stable per key and differs between keys', () async {
    final a = await PairCrypto.newKeyPair();
    final b = await PairCrypto.newKeyPair();
    final fa = await PairCrypto.fingerprint(a.publicKey);
    expect(fa, matches(RegExp(r'^\d{4} \d{4}$')));
    expect(await PairCrypto.fingerprint(a.publicKey), fa);
    expect(await PairCrypto.fingerprint(b.publicKey), isNot(fa));
  });

  group('PairLink', () {
    test('round-trips through the QR text', () async {
      final tv = await PairCrypto.newKeyPair();
      final link = PairLink('K7M4PQ', tv.publicKeyB64);
      final back = PairLink.parse(link.uri)!;
      expect(back.code, 'K7M4PQ');
      expect(back.publicKeyB64, tv.publicKeyB64);
    });

    test('rejects anything else', () {
      expect(PairLink.parse('https://example.com'), isNull);
      expect(PairLink.parse('navivibe://pair?c=K7M4PQ'), isNull);
      expect(PairLink.parse('navivibe://pair?c=K7M4PQ&k=short'), isNull);
      expect(PairLink.parse('navivibe://pair?c=K7M0PQ&k=${'A' * 43}'), isNull); // 0 isn't in the alphabet
    });

    test('typed codes are forgiving', () {
      expect(PairLink.normaliseCode('k7m-4pq'), 'K7M4PQ');
      expect(PairLink.normaliseCode(' K7M 4PQ '), 'K7M4PQ');
      expect(PairLink.normaliseCode('K7M4P'), isNull);
      expect(PairLink.normaliseCode('K7M4PI'), isNull);
      expect(PairLink.display('K7M4PQ'), 'K7M 4PQ');
    });
  });
}
