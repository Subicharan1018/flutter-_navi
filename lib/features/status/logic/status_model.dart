import 'dart:async';

import 'package:dio/dio.dart';

/// How a service is doing, in words (no coloured dots).
enum HealthLevel {
  ok('OK'),
  slow('Slow'),
  down('Down'),
  off('Off'),
  checking('Checking…');

  final String label;
  const HealthLevel(this.label);
}

/// A reply slower than this is "slow" rather than "OK".
const Duration kSlowAfter = Duration(milliseconds: 1500);

/// Probes give up after this: a status page must not hang on a dead server.
const Duration kProbeTimeout = Duration(seconds: 6);

/// What a probe found. [detail] is one short line shown under the title.
class ProbeResult {
  final HealthLevel level;
  final String detail;
  final Duration? latency;
  const ProbeResult(this.level, this.detail, {this.latency});

  const ProbeResult.off(String detail) : this(HealthLevel.off, detail);
}

/// One row of the status screen.
class HealthRow {
  final String id;
  final String title;
  final HealthLevel level;
  final String detail;
  final Duration? latency;
  final DateTime? checkedAt;

  const HealthRow({
    required this.id,
    required this.title,
    this.level = HealthLevel.checking,
    this.detail = '',
    this.latency,
    this.checkedAt,
  });

  HealthRow withResult(ProbeResult r, DateTime at) =>
      HealthRow(id: id, title: title, level: r.level, detail: r.detail, latency: r.latency, checkedAt: at);

  HealthRow checking() =>
      HealthRow(id: id, title: title, level: HealthLevel.checking, detail: detail, latency: latency, checkedAt: checkedAt);

  bool get busy => level == HealthLevel.checking;
}

/// "OK" or "Slow" from how long a reply took.
HealthLevel levelForLatency(Duration d) => d > kSlowAfter ? HealthLevel.slow : HealthLevel.ok;

/// Runs [call], times it, and turns any failure into a "Down" result with a
/// sentence. [describe] words a successful reply.
Future<ProbeResult> timedProbe(
  Future<Object?> Function() call, {
  String Function(Object? reply)? describe,
  Duration timeout = kProbeTimeout,
}) async {
  final sw = Stopwatch()..start();
  try {
    final reply = await call().timeout(timeout);
    sw.stop();
    final lat = sw.elapsed;
    final extra = describe?.call(reply);
    return ProbeResult(
      levelForLatency(lat),
      [formatLatency(lat), if (extra != null && extra.isNotEmpty) extra].join(' · '),
      latency: lat,
    );
  } on TimeoutException {
    return const ProbeResult(HealthLevel.down, 'No answer in time');
  } catch (e) {
    return ProbeResult(HealthLevel.down, describeProbeError(e));
  }
}

String formatLatency(Duration d) => d.inMilliseconds >= 1000
    ? '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s'
    : '${d.inMilliseconds} ms';

/// A failure whose [message] is already safe to show.
class ProbeFailure implements Exception {
  final String message;
  const ProbeFailure(this.message);
  @override
  String toString() => message;
}

/// A short, token-free reason for a failed request.
String describeProbeError(Object e) {
  if (e is ProbeFailure) return e.message;
  if (e is DioException) {
    final code = e.response?.statusCode;
    if (code != null) {
      return switch (code) {
        401 || 403 => 'Sign-in refused ($code)',
        404 => 'Not found (404)',
        >= 500 => 'Server error ($code)',
        _ => 'Error $code',
      };
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'No answer in time',
      _ => 'Can’t reach the server',
    };
  }
  final s = e.toString();
  if (s.contains('Authentication') || s.contains('AuthException')) return 'Sign-in refused';
  if (s.contains('Timeout') || s.contains('timed out')) return 'No answer in time';
  if (s.contains('SocketException') || s.contains('Network') || s.contains('ClientException')) {
    return 'Can’t reach the server';
  }
  return 'Failed';
}

/// "just now", "12 s ago", "3 min ago", "2 h ago".
String formatAgo(DateTime? at, DateTime now) {
  if (at == null) return 'Not checked';
  final d = now.difference(at);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatSpeed(double bytesPerSecond) => '${formatBytes(bytesPerSecond.round())}/s';

/// Counts of a download queue in words: "2 queued · 1 running · 0 failed".
String queueSummary({required int queued, required int running, required int failed}) =>
    '$queued queued · $running running · $failed failed';

final RegExp _urlCreds = RegExp(r'(https?://)[^/\s:@]+:[^/\s@]+@');
final RegExp _secretParam = RegExp(
  r'([?&;\s](?:p|password|pass|t|s|token|salt|apikey|api_key|key|u|username)=)[^&\s]*',
  caseSensitive: false,
);
final RegExp _bearer = RegExp(r'(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);

/// Strips anything credential-shaped from a line of diagnostics.
String redact(String s) => s
    .replaceAllMapped(_urlCreds, (m) => '${m[1]}***@')
    .replaceAllMapped(_secretParam, (m) => '${m[1]}***')
    .replaceAllMapped(_bearer, (m) => '${m[1]} ***');

/// The report "Copy diagnostics" puts on the clipboard. Never includes
/// credentials; server addresses are reduced to host names.
String buildDiagnostics({
  required List<HealthRow> rows,
  required String appVersion,
  required String platform,
  required DateTime now,
  Map<String, String> extra = const {},
}) {
  final b = StringBuffer()
    ..writeln('NaviVibe diagnostics')
    ..writeln('Generated: ${now.toUtc().toIso8601String()}')
    ..writeln('App: $appVersion')
    ..writeln('Platform: $platform');
  for (final e in extra.entries) {
    b.writeln('${e.key}: ${redact(e.value)}');
  }
  b.writeln();
  for (final r in rows) {
    final when = r.checkedAt == null ? 'not checked' : 'checked ${formatAgo(r.checkedAt, now)}';
    b.writeln('${r.title}: ${r.level.label}${r.detail.isEmpty ? '' : ' — ${redact(r.detail)}'} ($when)');
  }
  return b.toString().trimRight();
}

/// Host part of a server address, for the report ("music.example.com").
String hostOf(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return url.isEmpty ? 'not set' : 'invalid';
  return u.hasPort ? '${u.host}:${u.port}' : u.host;
}
