import 'package:http/http.dart' as http;

class PlaylistImageException implements Exception {
  final String message;
  const PlaylistImageException(this.message);
  @override
  String toString() => message;
}

/// A playlist's picture, stored by Navidrome itself (its native API; the
/// Subsonic API has no call for it), so every device and platform shows it.
class PlaylistImageApi {
  final String base;
  final Future<String> Function() jwt;
  final http.Client _client;

  PlaylistImageApi({required this.base, required this.jwt, http.Client? client}) : _client = client ?? http.Client();

  Uri _url(String id) => Uri.parse('$base/api/playlist/${Uri.encodeComponent(id)}/image');

  Future<void> upload(String playlistId, List<int> bytes, String filename) async {
    final req = http.MultipartRequest('POST', _url(playlistId))
      ..headers['X-ND-Authorization'] = 'Bearer ${await jwt()}'
      ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
    await _send(req);
  }

  Future<void> remove(String playlistId) async {
    final req = http.Request('DELETE', _url(playlistId))..headers['X-ND-Authorization'] = 'Bearer ${await jwt()}';
    await _send(req);
  }

  Future<void> _send(http.BaseRequest req) async {
    http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 60));
      await res.stream.drain<void>();
    } catch (_) {
      throw const PlaylistImageException('Couldn’t reach your server. Check your connection and try again.');
    }
    final code = res.statusCode;
    if (code == 401 || code == 403) {
      throw const PlaylistImageException('You can only change the picture of your own playlists.');
    }
    if (code == 404) throw const PlaylistImageException('This server can’t store playlist pictures. Update Navidrome.');
    if (code >= 300) throw PlaylistImageException('The server answered $code. Try again later.');
  }
}
