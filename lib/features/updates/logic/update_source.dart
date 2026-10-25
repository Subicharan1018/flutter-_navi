import '../data/update_manifest.dart';

/// Where releases are published. Nothing is built in: the user types it in
/// Settings > About > Updates, so an empty value means updates are off.
///
/// Accepted forms
///  * `github:owner/repo` or `https://github.com/owner/repo`, read through the
///    GitHub API so a private repository works with a token;
///  * any other http(s) URL of a `latest.json` (a static host, the user's own
///    server, a public release's `.../releases/latest/download/latest.json`).
class UpdateSource {
  final String raw;
  final String? token;
  final String? owner;
  final String? repo;
  final Uri? manifestUrl;

  /// Follow pre-releases (builds of non-main branches) too. GitHub mode only.
  final bool beta;

  const UpdateSource._(this.raw, this.token, this.owner, this.repo, this.manifestUrl, this.beta);

  bool get isGithub => owner != null;

  static UpdateSource? parse(String? input, {String? token, bool beta = false}) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return null;
    final tok = (token == null || token.trim().isEmpty) ? null : token.trim();

    final short = RegExp(r'^github:([\w.-]+)/([\w.-]+)$').firstMatch(raw);
    if (short != null) return UpdateSource._(raw, tok, short[1], short[2], null, beta);

    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if ((uri.host == 'github.com' || uri.host == 'www.github.com') && segs.length == 2) {
      return UpdateSource._(raw, tok, segs[0], segs[1].replaceAll(RegExp(r'\.git$'), ''), null, beta);
    }
    return UpdateSource._(raw, tok, null, null, uri, beta);
  }

  /// `/releases/latest` skips pre-releases by definition; with [beta] the list
  /// (newest first, pre-releases included) is read instead.
  Uri get releaseApi => beta
      ? Uri.https('api.github.com', '/repos/$owner/$repo/releases', {'per_page': '10'})
      : Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');

  /// The release to read from the API's answer: the object itself, or the
  /// newest non-draft release that carries a latest.json from a list.
  static Map<String, dynamic>? pickRelease(Object? json) {
    if (json is Map<String, dynamic>) return json;
    if (json is List) {
      for (final r in json) {
        if (r is! Map<String, dynamic> || r['draft'] == true) continue;
        final assets = r['assets'];
        if (assets is List && assets.any((a) => a is Map && a['name'] == 'latest.json')) return r;
      }
    }
    return null;
  }

  Map<String, String> get apiHeaders => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Where to fetch [file] of [m]. [githubAssets] maps asset name to API url
  /// (GitHub mode only).
  DownloadTarget targetFor(UpdateFile file, UpdateManifest m, Map<String, String> githubAssets) {
    if (isGithub) {
      final api = githubAssets[file.name];
      if (api == null) throw StateError('The release has no file called ${file.name}.');
      return DownloadTarget(Uri.parse(api), {
        'Accept': 'application/octet-stream',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    }
    final url = m.assetBase.isNotEmpty
        ? Uri.parse('${m.assetBase}${m.assetBase.endsWith('/') ? '' : '/'}${Uri.encodeComponent(file.name)}')
        : manifestUrl!.resolve(Uri.encodeComponent(file.name));
    // The token belongs to the manifest's host only.
    return DownloadTarget(url, {if (token != null && url.host == manifestUrl!.host) 'Authorization': 'Bearer $token'});
  }
}

class DownloadTarget {
  final Uri url;
  final Map<String, String> headers;
  const DownloadTarget(this.url, this.headers);
}
