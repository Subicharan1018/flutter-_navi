import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// =============================================================================
// pair_crypto.dart — end-to-end encryption for "sign in another device".
//
// The TV makes an X25519 key pair and shows its PUBLIC key (in the QR, and as a
// short fingerprint). The phone makes a fresh X25519 pair, derives
//
//   key = HKDF-SHA256(X25519(phonePriv, tvPub),
//                     salt = "navivibe-pair-v1:" + code,
//                     info = tvPub || phonePub)            → 32 bytes
//
// and seals the credentials with AES-256-GCM, binding the code and both public
// keys as associated data. The relay only ever holds [PairSealed]; opening it
// needs the TV's private key, which never leaves the TV.
// =============================================================================

/// What travels: the server address, username and password.
class PairCredentials {
  final String serverUrl;
  final String username;
  final String password;
  const PairCredentials({required this.serverUrl, required this.username, required this.password});

  Map<String, Object> toJson() => {'v': 1, 's': serverUrl, 'u': username, 'p': password};

  /// Throws [FormatException] when the shape is wrong (a tampered or foreign payload).
  static PairCredentials fromJson(Object? json) {
    if (json is Map && json['v'] == 1) {
      final s = json['s'], u = json['u'], p = json['p'];
      if (s is String && u is String && p is String && s.isNotEmpty && u.isNotEmpty && p.isNotEmpty) {
        return PairCredentials(serverUrl: s, username: u, password: p);
      }
    }
    throw const FormatException('Not a sign-in payload');
  }

  @override
  bool operator ==(Object other) =>
      other is PairCredentials &&
      other.serverUrl == serverUrl &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(serverUrl, username, password);
}

/// The ciphertext as the relay stores it (all unpadded base64url).
class PairSealed {
  final String epk;
  final String nonce;
  final String ct;
  const PairSealed({required this.epk, required this.nonce, required this.ct});

  Map<String, String> toJson() => {'epk': epk, 'nonce': nonce, 'ct': ct};

  static PairSealed fromJson(Map<String, dynamic> json) =>
      PairSealed(epk: json['epk'] as String, nonce: json['nonce'] as String, ct: json['ct'] as String);
}

/// The TV's key pair; the public half goes on screen.
class PairKeyPair {
  final SimpleKeyPair _pair;
  final Uint8List publicKey;
  const PairKeyPair._(this._pair, this.publicKey);

  String get publicKeyB64 => b64url(publicKey);
}

class PairDecryptException implements Exception {
  const PairDecryptException();
  @override
  String toString() => 'The sign-in could not be decrypted.';
}

String b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64url(String s) => Uint8List.fromList(base64Url.decode(s + '=' * ((4 - s.length % 4) % 4)));

abstract final class PairCrypto {
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();

  static Future<PairKeyPair> newKeyPair() async {
    final pair = await _x25519.newKeyPair();
    final pub = await pair.extractPublicKey();
    return PairKeyPair._(pair, Uint8List.fromList(pub.bytes));
  }

  static List<int> _info(List<int> tvPub, List<int> phonePub) => [...tvPub, ...phonePub];

  static List<int> _aad(String code, List<int> info) => [...utf8.encode(code), ...info];

  static Future<SecretKey> _key(SecretKey shared, String code, List<int> info) =>
      _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode('navivibe-pair-v1:$code'), info: info);

  /// Phone side: encrypt [credentials] to the TV whose public key is [tvPublic].
  static Future<PairSealed> seal({
    required List<int> tvPublic,
    required String code,
    required PairCredentials credentials,
  }) async {
    final phone = await _x25519.newKeyPair();
    final phonePub = (await phone.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: phone,
      remotePublicKey: SimplePublicKey(tvPublic, type: KeyPairType.x25519),
    );
    final info = _info(tvPublic, phonePub);
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(credentials.toJson())),
      secretKey: await _key(shared, code, info),
      aad: _aad(code, info),
    );
    return PairSealed(
      epk: b64url(phonePub),
      nonce: b64url(box.nonce),
      ct: b64url([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// TV side. Throws [PairDecryptException] for anything that does not open
  /// cleanly (wrong key, other code, tampering, malformed data).
  static Future<PairCredentials> open({
    required PairKeyPair keys,
    required String code,
    required PairSealed sealed,
  }) async {
    try {
      final phonePub = unb64url(sealed.epk);
      final nonce = unb64url(sealed.nonce);
      final blob = unb64url(sealed.ct);
      if (phonePub.length != 32 || nonce.length != 12 || blob.length < 17) throw const PairDecryptException();
      final shared = await _x25519.sharedSecretKey(
        keyPair: keys._pair,
        remotePublicKey: SimplePublicKey(phonePub, type: KeyPairType.x25519),
      );
      final info = _info(keys.publicKey, phonePub);
      final clear = await _aes.decrypt(
        SecretBox(blob.sublist(0, blob.length - 16), nonce: nonce, mac: Mac(blob.sublist(blob.length - 16))),
        secretKey: await _key(shared, code, info),
        aad: _aad(code, info),
      );
      return PairCredentials.fromJson(jsonDecode(utf8.decode(clear)));
    } on PairDecryptException {
      rethrow;
    } catch (_) {
      throw const PairDecryptException();
    }
  }

  /// Eight digits (two groups of four) from a SHA-256 of the TV's public key.
  /// The TV shows it and the phone repeats it for a typed code, so a relay that
  /// swapped keys would be caught by eye. (Only needed when the key did not
  /// come by QR; a QR carries the whole key.)
  static Future<String> fingerprint(List<int> tvPublic) async {
    final h = (await Sha256().hash(tvPublic)).bytes;
    final n = (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) % 100000000;
    final d = n.toString().padLeft(8, '0');
    return '${d.substring(0, 4)} ${d.substring(4)}';
  }
}
