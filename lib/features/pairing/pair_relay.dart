import 'package:dio/dio.dart';

import 'pair_crypto.dart';

// =============================================================================
// pair_relay.dart — the shuffle server's /pair mailbox, behind an interface so
// the state machines can be tested with a fake. See navivibe/pair.py.
// =============================================================================

class PairTicket {
  final String code;
  final int expiresInSeconds;
  const PairTicket(this.code, this.expiresInSeconds);
}

sealed class PairPoll {
  const PairPoll();
}

class PairWaiting extends PairPoll {
  const PairWaiting();
}

class PairReady extends PairPoll {
  final PairSealed sealed;
  const PairReady(this.sealed);
}

/// Unknown, expired, or already collected.
class PairGone extends PairPoll {
  const PairGone();
}

enum PairRelayProblem { network, rateLimited, notFound, alreadyUsed, rejected, server }

class PairRelayException implements Exception {
  final PairRelayProblem problem;
  final String message;
  const PairRelayException(this.problem, this.message);
  @override
  String toString() => message;
}

abstract interface class PairRelay {
  /// TV: ask for a code for [publicKeyB64].
  Future<PairTicket> create(String publicKeyB64);

  /// TV: has the phone answered?
  Future<PairPoll> poll(String code, String publicKeyB64);

  /// Phone: the public key a TV registered under [code].
  Future<String> keyFor(String code);

  /// Phone: leave the sealed credentials for the TV.
  Future<void> deposit(String code, PairSealed sealed);
}

class HttpPairRelay implements PairRelay {
  final Dio _dio;
  HttpPairRelay(this._dio);

  static bool _anyStatus(int? s) => s != null && s < 600;

  PairRelayException _problem(Response<dynamic> r) {
    final body = r.data;
    final msg = body is Map && body['error'] is String ? body['error'] as String : null;
    final status = r.statusCode ?? 0;
    if (status >= 500) {
      return PairRelayException(PairRelayProblem.server, msg ?? 'The server is busy. Try again shortly.');
    }
    return switch (status) {
      404 => PairRelayException(PairRelayProblem.notFound, msg ?? 'That code isn’t active.'),
      409 => PairRelayException(PairRelayProblem.alreadyUsed, msg ?? 'That code has already been used.'),
      429 => const PairRelayException(PairRelayProblem.rateLimited, 'Too many tries. Wait a minute and try again.'),
      _ => PairRelayException(PairRelayProblem.rejected, msg ?? 'The server turned that down.'),
    };
  }

  Future<Response<dynamic>> _call(Future<Response<dynamic>> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final r = e.response;
      if (r != null) throw _problem(r);
      throw const PairRelayException(PairRelayProblem.network, 'Can’t reach the server. Check the connection.');
    }
  }

  @override
  Future<PairTicket> create(String publicKeyB64) async {
    final r = await _call(
      () => _dio.post<dynamic>('/pair', data: {'pub': publicKeyB64}, options: Options(validateStatus: _anyStatus)),
    );
    if (r.statusCode != 201) throw _problem(r);
    final d = r.data as Map;
    return PairTicket(d['code'] as String, (d['expires_in'] as num?)?.toInt() ?? 300);
  }

  @override
  Future<PairPoll> poll(String code, String publicKeyB64) async {
    final r = await _call(
      () => _dio.get<dynamic>(
        '/pair/$code',
        options: Options(headers: {'X-Pair-Key': publicKeyB64}, validateStatus: _anyStatus),
      ),
    );
    return switch (r.statusCode) {
      200 => PairReady(PairSealed.fromJson((r.data as Map).cast<String, dynamic>())),
      202 => const PairWaiting(),
      404 => const PairGone(),
      _ => throw _problem(r),
    };
  }

  @override
  Future<String> keyFor(String code) async {
    final r = await _call(() => _dio.get<dynamic>('/pair/$code/key', options: Options(validateStatus: _anyStatus)));
    if (r.statusCode != 200) throw _problem(r);
    return (r.data as Map)['pub'] as String;
  }

  @override
  Future<void> deposit(String code, PairSealed sealed) async {
    final r = await _call(
      () => _dio.post<dynamic>('/pair/$code', data: sealed.toJson(), options: Options(validateStatus: _anyStatus)),
    );
    if (r.statusCode != 204) throw _problem(r);
  }
}
