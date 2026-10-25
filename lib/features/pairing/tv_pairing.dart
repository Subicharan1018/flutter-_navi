import 'dart:async';

import 'package:flutter/foundation.dart';

import 'pair_crypto.dart';
import 'pair_link.dart';
import 'pair_relay.dart';

// =============================================================================
// tv_pairing.dart — the TV's side of "sign in another device", as a state
// machine with no widgets in it:
//
//   starting → waiting(code) ─┬→ signingIn → done
//                             ├→ (code ran out) → starting … a fresh code
//                             └→ failed(message)
//
// It owns the key pair, polls the relay, decrypts what arrives and hands the
// credentials to [signIn] (verify against the server and save).
// =============================================================================

sealed class TvPairState {
  const TvPairState();
}

class TvPairStarting extends TvPairState {
  const TvPairStarting();
}

class TvPairWaiting extends TvPairState {
  final String code;
  final PairLink link;
  final String fingerprint;
  final DateTime expiresAt;
  const TvPairWaiting(this.code, this.link, this.fingerprint, this.expiresAt);
}

/// Credentials arrived and are being checked.
class TvPairSigningIn extends TvPairState {
  final String serverUrl;
  final String username;
  const TvPairSigningIn(this.serverUrl, this.username);
}

class TvPairDone extends TvPairState {
  const TvPairDone();
}

class TvPairFailed extends TvPairState {
  final String message;
  const TvPairFailed(this.message);
}

/// Verify and save the credentials; throw with a readable message on failure.
typedef PairSignIn = Future<void> Function(PairCredentials credentials);

class TvPairing extends ValueNotifier<TvPairState> {
  final PairRelay relay;
  final PairSignIn signIn;
  final Duration pollEvery;
  final DateTime Function() now;

  /// Consecutive network failures before the screen says it can't reach the server.
  static const maxNetworkFailures = 5;

  TvPairing({
    required this.relay,
    required this.signIn,
    this.pollEvery = const Duration(seconds: 2),
    this.now = DateTime.now,
  }) : super(const TvPairStarting());

  PairKeyPair? _keys;
  String? _code;
  Timer? _timer;
  int _failures = 0;
  bool _busy = false;
  bool _disposed = false;

  /// Ask for a code and start polling. Safe to call again for a fresh code.
  Future<void> start() async {
    _timer?.cancel();
    _failures = 0;
    _code = null;
    value = const TvPairStarting();
    try {
      final keys = _keys = await PairCrypto.newKeyPair();
      final ticket = await relay.create(keys.publicKeyB64);
      final fp = await PairCrypto.fingerprint(keys.publicKey);
      if (_disposed) return;
      _code = ticket.code;
      value = TvPairWaiting(
        ticket.code,
        PairLink(ticket.code, keys.publicKeyB64),
        fp,
        now().add(Duration(seconds: ticket.expiresInSeconds)),
      );
      _timer = Timer.periodic(pollEvery, (_) => pollNow());
    } on PairRelayException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('Couldn’t start pairing. Try again.');
    }
  }

  /// One poll of the relay (the timer calls this; tests call it directly).
  @visibleForTesting
  Future<void> pollNow() async {
    final code = _code, keys = _keys;
    final state = value;
    if (_busy || _disposed || code == null || keys == null || state is! TvPairWaiting) return;
    _busy = true;
    try {
      if (!now().isBefore(state.expiresAt)) {
        _busy = false;
        await _renew();
        return;
      }
      final r = await relay.poll(code, keys.publicKeyB64);
      if (_disposed) return;
      _failures = 0;
      switch (r) {
        case PairWaiting():
          break;
        case PairGone():
          _busy = false;
          await _renew();
        case PairReady(:final sealed):
          _timer?.cancel();
          await _open(code, keys, sealed);
      }
    } on PairRelayException catch (e) {
      switch (e.problem) {
        case PairRelayProblem.network || PairRelayProblem.server:
          if (++_failures >= maxNetworkFailures) _fail(e.message);
        case PairRelayProblem.rateLimited:
          break; // back off one beat; the next tick tries again
        default:
          _fail(e.message);
      }
    } finally {
      _busy = false;
    }
  }

  /// A code that ran out is replaced without anyone touching the remote.
  Future<void> _renew() async {
    _timer?.cancel();
    await start();
  }

  Future<void> _open(String code, PairKeyPair keys, PairSealed sealed) async {
    final PairCredentials creds;
    try {
      creds = await PairCrypto.open(keys: keys, code: code, sealed: sealed);
    } on PairDecryptException {
      _fail('That sign-in couldn’t be read. Start again on your phone.');
      return;
    }
    if (_disposed) return;
    value = TvPairSigningIn(creds.serverUrl, creds.username);
    try {
      await signIn(creds);
      if (!_disposed) value = const TvPairDone();
    } catch (e) {
      _fail(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _fail(String message) {
    _timer?.cancel();
    if (!_disposed) value = TvPairFailed(message);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
