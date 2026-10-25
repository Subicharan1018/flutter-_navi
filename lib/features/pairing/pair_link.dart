/// What the TV's QR code carries: `navivibe://pair?c=<code>&k=<public key>`.
/// The key rides in the QR so a phone that scans it needs nothing from the
/// relay but the mailbox; a phone given only the typed code asks the relay and
/// confirms the fingerprint instead.
class PairLink {
  final String code;
  final String publicKeyB64;
  const PairLink(this.code, this.publicKeyB64);

  /// Characters a code may contain (no 0/O/1/I), matching the server.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;

  String get uri =>
      Uri(scheme: 'navivibe', host: 'pair', queryParameters: {'c': code, 'k': publicKeyB64}).toString();

  /// Null when [text] is not a pairing link.
  static PairLink? parse(String text) {
    final u = Uri.tryParse(text.trim());
    if (u == null || u.scheme != 'navivibe' || u.host != 'pair') return null;
    final c = normaliseCode(u.queryParameters['c'] ?? '');
    final k = u.queryParameters['k'] ?? '';
    if (c == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(k)) return null;
    return PairLink(c, k);
  }

  /// "k7m-4pq" → "K7M4PQ"; null when it can't be a code.
  static String? normaliseCode(String input) {
    final c = input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (c.length != codeLength) return null;
    return c.split('').every(alphabet.contains) ? c : null;
  }

  /// "K7M4PQ" → "K7M 4PQ" for reading aloud and across a room.
  static String display(String code) =>
      code.length == codeLength ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}
