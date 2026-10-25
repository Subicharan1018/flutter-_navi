import 'pair_crypto.dart';
import 'pair_link.dart';
import 'pair_relay.dart';

// =============================================================================
// phone_pairing.dart — the signed-in device's side: find the TV's key, show a
// fingerprint for a typed code, then seal this device's credentials to the TV
// and drop them in the mailbox.
// =============================================================================

/// A TV the phone is about to sign in.
class PairTarget {
  final String code;
  final List<int> publicKey;

  /// True when the key came from a scanned QR (no need to compare fingerprints);
  /// false when the relay supplied it for a typed code.
  final bool keyFromQr;
  final String fingerprint;
  const PairTarget(this.code, this.publicKey, this.keyFromQr, this.fingerprint);
}

class PhonePairing {
  final PairRelay relay;
  const PhonePairing(this.relay);

  /// From a scanned QR: nothing to ask the relay.
  Future<PairTarget> fromLink(PairLink link) async {
    final pub = unb64url(link.publicKeyB64);
    return PairTarget(link.code, pub, true, await PairCrypto.fingerprint(pub));
  }

  /// From a typed code. Throws [PairRelayException] (not found, rate limited…)
  /// or [FormatException] when [typed] can't be a code.
  Future<PairTarget> fromTypedCode(String typed) async {
    final code = PairLink.normaliseCode(typed);
    if (code == null) throw const FormatException('Enter the 6 characters shown on the TV.');
    final pub = unb64url(await relay.keyFor(code));
    if (pub.length != 32) {
      throw const PairRelayException(PairRelayProblem.rejected, 'The server sent something unexpected.');
    }
    return PairTarget(code, pub, false, await PairCrypto.fingerprint(pub));
  }

  Future<void> send(PairTarget target, PairCredentials credentials) async {
    final sealed = await PairCrypto.seal(tvPublic: target.publicKey, code: target.code, credentials: credentials);
    await relay.deposit(target.code, sealed);
  }
}
