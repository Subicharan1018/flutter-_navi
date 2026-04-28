import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants.dart';
import '../models/song.dart';
import '../models/album.dart';
import '../models/playlist.dart';
import 'playlist_cache_service.dart';

class SubsonicService {
  final String serverUrl;
  final String username;
  final String password;
  final String? customUploadUrl;
  final String? customUploadDir;
  final String? webdavUsername;
  final String? webdavPassword;
  final http.Client _client = http.Client();

  /// SQLite-backed persistent playlist cache (injected by the provider).
  final PlaylistCacheService _cache;

  // In-memory library caches have been removed (BUG-31).
  // Riverpod providers with .keepAlive() are the single source of truth.
  // Holding the same data here caused ~1.5 MB of double-allocation and
  // made cache invalidation impossible without recreating the service.

  // ---------------------------------------------------------------------------
  // COVER ART URL FIX
  //
  // _buildUrl() generates a fresh random salt on every call (BUG-8 security
  // fix). That is correct for API requests, but getCoverArtUrl() is called
  // inside widget build() methods, meaning a new URL — with a new salt/token —
  // is produced on every rebuild.  CachedNetworkImage uses the URL string as
  // its primary cache key, so the image is treated as uncached and re-downloaded
  // on every scroll/rebuild, causing the "images refreshing on scroll" bug.
  //
  // Fix: generate ONE stable salt+token pair at construction time, used
  // exclusively for cover-art URLs.  Cover art never changes for a given ID so
  // there is no security downside to reusing the same token here.  All other
  // API calls (stream, search, star, scrobble …) continue to use a fresh random
  // salt via _buildUrl().
  // ---------------------------------------------------------------------------
  late final String _coverArtSalt;
  late final String _coverArtToken;

  SubsonicService({
    required String serverUrl,
    required this.username,
    required this.password,
    required PlaylistCacheService cache,
    this.customUploadUrl,
    this.customUploadDir,
    this.webdavUsername,
    this.webdavPassword,
  })  : serverUrl = _normalizeServerUrl(serverUrl),
        _cache = cache {
    // Initialise the stable cover-art credentials once.
    _coverArtSalt = _generateSalt();
    _coverArtToken = _generateToken(_coverArtSalt);
  }

  static String _normalizeServerUrl(String url) {
    final uri = Uri.parse(url.trim());
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: '/rest').toString();
    }
    return uri.toString().replaceAll(RegExp(r'/+$'), '');
  }

  // ---------------------------------------------------------------------------
  // Auth helpers
  // ---------------------------------------------------------------------------

  static final Random _random = Random.secure();
  static const _saltChars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  String _generateSalt() {
    return List.generate(
            16, (_) => _saltChars[_random.nextInt(_saltChars.length)])
        .join();
  }

  String _generateToken(String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Builds a URL with a **fresh** random salt — used for every API call
  /// except cover-art image URLs (see [getCoverArtUrl]).
  String _buildUrl(String endpoint, [Map<String, String>? params]) {
    final salt = _generateSalt();
    final token = _generateToken(salt);

    final queryParams = <String, String>{
      'u': username,
      't': token,
      's': salt,
      'v': Constants.apiVersion,
      'c': Constants.defaultClient,
      'f': 'json',
    };
    if (params != null) queryParams.addAll(params);

    final uri = Uri.parse('$serverUrl/$endpoint');
    return uri.replace(queryParameters: queryParams).toString();
  }

  /// Builds a URL with the **stable** salt/token pair — used only for image
  /// URLs so that CachedNetworkImage always sees the same string for the same
  /// cover-art ID.
  String _buildStableUrl(String endpoint, [Map<String, String>? params]) {
    final queryParams = <String, String>{
      'u': username,
      't': _coverArtToken,
      's': _coverArtSalt,
      'v': Constants.apiVersion,
      'c': Constants.defaultClient,
      'f': 'json',
    };
    if (params != null) queryParams.addAll(params);

    final uri = Uri.parse('$serverUrl/$endpoint');
    return uri.replace(queryParameters: queryParams).toString();
  }

  // ---------------------------------------------------------------------------
  // URL builders
  // ---------------------------------------------------------------------------

  /// Stream URL — fresh salt per call (correct: each stream request is unique).
  String getStreamUrl(String songId) =>
      _buildUrl('stream.view', {'id': songId});

  /// Cover-art URL — **stable** salt so the URL never changes for a given ID.
  /// This is what allows CachedNetworkImage to serve from disk/memory cache
  /// instead of re-downloading on every widget rebuild or list scroll.
  String getCoverArtUrl(String? coverArtId) {
    if (coverArtId == null || coverArtId.isEmpty) return '';
    return _buildStableUrl('getCoverArt.view', {'id': coverArtId});
  }

  // ---------------------------------------------------------------------------
  // HTTP helper
  // ---------------------------------------------------------------------------

  Future<dynamic> _get(String endpoint, [Map<String, String>? params]) async {
    final url = _buildUrl(endpoint, params);
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      // BUG-29: parse JSON on a background isolate — response.body can be
      // 2–5 MB for large song libraries; doing this on the main thread
      // causes visible freezes of 300–800 ms.
      final jsonResponse =
          await compute(_decodeJsonBody, response.body);
      final subsonicResponse =
          jsonResponse['subsonic-response'] as Map<String, dynamic>;
      if (subsonicResponse['status'] == 'ok') {
        return subsonicResponse;
      } else {
        final error = subsonicResponse['error'] as Map<String, dynamic>?;
        throw Exception(error?['message'] ?? 'Subsonic API Error');
      }
    } else {
      throw Exception('HTTP Error: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // Auth / Connectivity
  // ---------------------------------------------------------------------------

  Future<bool> ping() async {
    try {
      await _get('ping.view');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Song library
  // ---------------------------------------------------------------------------

  Future<List<Song>> getAllSongs({int size = 5000}) async {
    // BUG-29: Song.fromJson mapping moved to background isolate.
    // BUG-31: in-memory cache removed — Riverpod allSongsProvider.keepAlive()
    //         is the authoritative cache.
    try {
      final res = await _get('search3.view', {
        'query': '*',
        'songCount': size.toString(),
      });
      final searchResult =
          res['searchResult3'] as Map<String, dynamic>? ?? {};
      final rawList = (searchResult['song'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      // Parse 5000 Song objects on a background isolate.
      final songs = await compute(_parseSongList, rawList);
      if (songs.length > 10) return songs;
    } catch (e) {
      debugPrint('Wildcard search failed: $e');
    }

    return getRandomSongs(size: size);
  }

  Future<List<Song>> getRandomSongs({int size = 50}) async {
    final res = await _get('getRandomSongs.view', {'size': size.toString()});
    final randomSongs =
        (res['randomSongs'] as Map<String, dynamic>)['song'] as List<dynamic>? ??
            [];
    return randomSongs
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Song>> getNewestSongs({int size = 50}) async {
    final res = await _get(
        'getAlbumList2.view', {'type': 'newest', 'size': size.toString()});
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    if (albums.isEmpty) return [];

    // PERF-4: fetch all albums concurrently instead of sequentially.
    // Clamp to 10 albums max to avoid flooding the server with requests.
    final toFetch = albums.take(10).map((a) => a['id'] as String).toList();
    final results = await Future.wait(toFetch.map(getAlbum));
    final allSongs = results.expand((s) => s).toList();
    return allSongs.take(size).toList();
  }

  Future<List<Song>> getSimilarSongs(String songId, {int count = 20}) async {
    final res = await _get('getSimilarSongs2.view', {
      'id': songId,
      'count': count.toString(),
    });
    final similarSongs =
        (res['similarSongs2'] as Map<String, dynamic>)['song'] as List<dynamic>? ??
            [];
    return similarSongs
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Albums
  // ---------------------------------------------------------------------------

  Future<List<Album>> getRecentlyPlayedAlbums() async {
    // BUG-31: cache removed — recentlyPlayedAlbumsProvider.keepAlive() owns it.
    final res = await _get('getAlbumList2.view', {'type': 'recent'});
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    return albums
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Album>> getFrequentAlbums() async {
    // BUG-31: cache removed — frequentAlbumsProvider.keepAlive() owns it.
    final res = await _get('getAlbumList2.view', {'type': 'frequent'});
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    return albums
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Album>> getAlbums({int offset = 0, int size = 50}) async {
    // BUG-31: _albumsCache removed — libraryAlbumsProvider.keepAlive() owns it.
    final res = await _get('getAlbumList2.view', {
      'type': 'alphabeticalByArtist',
      'offset': offset.toString(),
      'size': size.toString(),
    });
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    return albums.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Song>> getAlbum(String id) async {
    final res = await _get('getAlbum.view', {'id': id});
    final songs =
        (res['album'] as Map<String, dynamic>)['song'] as List<dynamic>? ?? [];
    return songs
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Artists
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getArtists() async {
    final res = await _get('getArtists.view');
    final indexes =
        (res['artists'] as Map<String, dynamic>)['index'] as List<dynamic>? ??
            [];
    final artists = <Map<String, dynamic>>[];
    for (final index in indexes) {
      final artistList =
          (index as Map<String, dynamic>)['artist'] as List<dynamic>? ?? [];
      for (final artist in artistList) {
        artists.add(artist as Map<String, dynamic>);
      }
    }
    return artists;
  }

  // ---------------------------------------------------------------------------
  // Playlists
  // ---------------------------------------------------------------------------

  Future<List<Playlist>> getPlaylists() async {
    // BUG-31: _playlistsCache removed — playlistsProvider.keepAlive() owns it.
    final res = await _get('getPlaylists.view');
    final playlists =
        (res['playlists'] as Map<String, dynamic>)['playlist'] as List<dynamic>? ??
            [];
    return playlists
        .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Playlist songs — stale-while-revalidate + SQLite cache
  // ---------------------------------------------------------------------------

  /// Returns songs for [playlistId].
  ///
  /// • If the SQLite cache has data (even stale) it is returned immediately
  ///   so the UI can render without waiting for the network.
  /// • A background refresh is fired whenever the cache is stale or
  ///   [forceRefresh] is true.
  /// • Pass [forceRefresh: true] only when you explicitly need fresh data
  ///   (e.g. after a mutation) and are willing to wait for the result.
  Future<List<Song>> getPlaylistSongs(
    String id, {
    bool forceRefresh = false,
  }) async {
    // ── 1. Check the persistent cache ──────────────────────────────────────
    if (!forceRefresh) {
      final cached = await _cache.getSongs(id);
      if (cached != null) {
        if (cached.isStale) {
          // Return cached data now; refresh silently in the background.
          _backgroundRefreshPlaylist(id);
        }
        return cached.songs;
      }
    }

    // ── 2. Cache miss or forced refresh — fetch from network ────────────────
    return _fetchAndCachePlaylist(id);
  }

  /// Fetches playlist songs from the Subsonic API, parses them off the main
  /// thread, writes the result to SQLite, and returns the list.
  Future<List<Song>> _fetchAndCachePlaylist(String id) async {
    final res = await _get('getPlaylist.view', {'id': id});
    final rawEntries =
        (res['playlist'] as Map<String, dynamic>)['entry'] as List<dynamic>? ??
            [];

    // Parse Song objects on a background isolate to keep the UI thread free.
    final songs = await compute(
      _parseSongList,
      rawEntries.cast<Map<String, dynamic>>(),
    );

    // Persist to SQLite (fire-and-forget — don't block the caller).
    _cache.putSongs(id, songs);

    return songs;
  }

  /// Fires a silent background refresh for [playlistId].
  /// Errors are swallowed — the stale cached data remains usable.
  void _backgroundRefreshPlaylist(String id) {
    _fetchAndCachePlaylist(id).catchError((e) {
      debugPrint('[SubsonicService] background refresh failed for $id: $e');
    });
  }

  /// Removes the SQLite cache for [playlistId].
  /// Call this after adding or removing songs so the next open re-fetches.
  Future<void> invalidatePlaylist(String id) => _cache.invalidate(id);

  Future<void> createPlaylist(String name) async {
    await _get('createPlaylist.view', {'name': name});
    // Playlist list is owned by playlistsProvider — callers invalidate via ref.invalidate(playlistsProvider).
  }

  Future<void> deletePlaylist(String id) async {
    await _get('deletePlaylist.view', {'id': id});
  }

  Future<void> updatePlaylist(
    String playlistId, {
    String? songIdToAdd,
    int? songIndexToRemove,
    String? name,
    String? comment,
  }) async {
    final params = <String, String>{'playlistId': playlistId};
    if (songIdToAdd != null) params['songIdToAdd'] = songIdToAdd;
    if (songIndexToRemove != null) {
      params['songIndexToRemove'] = songIndexToRemove.toString();
    }
    if (name != null) params['name'] = name;
    if (comment != null) params['comment'] = comment;
    await _get('updatePlaylist.view', params);
  }

  Future<void> setPlaylistImage(String playlistId, File imageFile) async {
    if (customUploadUrl != null && customUploadUrl!.isNotEmpty) {
      final extension = imageFile.path.split('.').last.toLowerCase();
      await _webDavUpload(imageFile, 'playlist_$playlistId.$extension');
      return;
    }

    final salt = _generateSalt();
    final token = _generateToken(salt);

    final uri = Uri.parse('$serverUrl/setPlaylistImage.view');
    final request = http.MultipartRequest('POST', uri);

    request.fields.addAll({
      'u': username,
      't': token,
      's': salt,
      'v': Constants.apiVersion,
      'c': Constants.defaultClient,
      'f': 'json',
      'id': playlistId,
    });

    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload failed with status ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<Map<String, List<dynamic>>> search(String query) async {
    final res = await _get('search3.view', {'query': query});
    final searchResult =
        res['searchResult3'] as Map<String, dynamic>? ?? {};
    final songs = (searchResult['song'] as List<dynamic>? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
    final albums = (searchResult['album'] as List<dynamic>? ?? [])
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
    final artists = (searchResult['artist'] as List<dynamic>? ?? [])
        .map((e) => (e as Map<String, dynamic>)['name'] as String)
        .toList();
    return {'songs': songs, 'albums': albums, 'artists': artists};
  }

  // ---------------------------------------------------------------------------
  // Starring / Rating / Scrobbling
  // ---------------------------------------------------------------------------

  Future<void> star(String songId) async =>
      _get('star.view', {'id': songId});

  Future<void> unstar(String songId) async =>
      _get('unstar.view', {'id': songId});

  Future<void> setRating(String songId, int rating) async {
    assert(rating >= 0 && rating <= 5, 'Subsonic rating must be 0–5');
    await _get('setRating.view', {
      'id': songId,
      'rating': rating.toString(),
    });
  }

  Future<void> scrobble(String songId) async =>
      _get('scrobble.view', {'id': songId, 'submission': 'true'});

  // ---------------------------------------------------------------------------
  // File upload
  // ---------------------------------------------------------------------------

  Future<void> uploadSong(File file) async {
    if (customUploadUrl != null && customUploadUrl!.isNotEmpty) {
      final fileName = Uri.file(file.path).pathSegments.last;
      await _webDavUpload(file, fileName);
      return;
    }

    final salt = _generateSalt();
    final token = _generateToken(salt);

    final uri = Uri.parse('$serverUrl/upload.view');
    final request = http.MultipartRequest('POST', uri);

    request.fields.addAll({
      'u': username,
      't': token,
      's': salt,
      'v': Constants.apiVersion,
      'c': Constants.defaultClient,
      'f': 'json',
    });

    request.files.add(await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType('audio', 'mpeg'),
    ));

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload failed with status ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // WebDAV Upload
  // ---------------------------------------------------------------------------

  Future<void> _webDavUpload(File file, String targetFileName) async {
    final baseUrl = customUploadUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    final remoteDir =
        (customUploadDir == null || customUploadDir!.trim().isEmpty)
            ? '/DATA/Media/Music'
            : customUploadDir!.trim();

    final normalizedDir =
        remoteDir.startsWith('/') ? remoteDir : '/$remoteDir';
    final finalDir = normalizedDir.endsWith('/')
        ? normalizedDir.substring(0, normalizedDir.length - 1)
        : normalizedDir;

    final uploadUrl = '$baseUrl$finalDir/$targetFileName';
    final uri = Uri.parse(uploadUrl);

    final webdavUser = webdavUsername ?? 'casaos';
    final webdavPass = webdavPassword ?? 'casaos';
    final auth = base64Encode(utf8.encode('$webdavUser:$webdavPass'));
    final bytes = await file.readAsBytes();

    debugPrint('Upload(WebDAV): PUT $uploadUrl');
    debugPrint('Upload(WebDAV): Using username: $webdavUser');
    debugPrint('Upload(WebDAV): File size: ${bytes.length} bytes');

    final response = await _client.put(
      uri,
      headers: {
        'Authorization': 'Basic $auth',
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );

    debugPrint('Upload(WebDAV): Response status: ${response.statusCode}');

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      debugPrint('Upload(WebDAV): Response body: ${response.body}');
      throw Exception(
          'WebDAV upload failed (${response.statusCode}): ${response.body}');
    }
  }

  // ---------------------------------------------------------------------------
  // Cache invalidation helpers (call after mutations if needed)
  // ---------------------------------------------------------------------------

  /// Wipes the SQLite playlist song cache.
  /// Call this on logout or server change, then use ref.invalidate() on
  /// Riverpod providers to trigger fresh network fetches.
  void clearCache() {
    _cache.clearAll(); // wipe persisted SQLite playlist songs
  }

  /// No-op — retained for API compatibility.
  /// Play history cache is owned by recentlyPlayedAlbumsProvider.keepAlive();
  /// call ref.invalidate(recentlyPlayedAlbumsProvider) to force a refresh.
  void invalidatePlayHistory() {}

  // BUG-3: close the http.Client to release socket connections.
  void dispose() {
    _client.close();
    _cache.dispose();
  }
}

// ---------------------------------------------------------------------------
// Top-level parse helpers — must be top-level for compute() compatibility
// ---------------------------------------------------------------------------

/// Parses raw song JSON entries into [Song] objects on a background isolate.
List<Song> _parseSongList(List<Map<String, dynamic>> entries) {
  return entries.map(Song.fromJson).toList();
}

/// Decodes a raw HTTP response body string into a JSON map on a background
/// isolate (BUG-29).  For large responses (e.g. 5,000 songs ≈ 2–5 MB) this
/// prevents the 300–800 ms UI freeze caused by synchronous [jsonDecode].
Map<String, dynamic> _decodeJsonBody(String body) =>
    jsonDecode(body) as Map<String, dynamic>;