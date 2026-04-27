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

class SubsonicService {
  final String serverUrl;
  final String username;
  final String password;
  final String? customUploadUrl;
  final String? customUploadDir;
  final String? webdavUsername;
  final String? webdavPassword;
  final http.Client _client = http.Client();

  // ---------------------------------------------------------------------------
  // In-memory library cache (retained for the lifetime of this service instance)
  // ---------------------------------------------------------------------------
  List<Album>? _recentlyPlayedAlbumsCache;
  List<Album>? _frequentAlbumsCache;
  List<Playlist>? _playlistsCache;
  List<Song>? _allSongsCache;
  List<Album>? _albumsCache;

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
    this.customUploadUrl,
    this.customUploadDir,
    this.webdavUsername,
    this.webdavPassword,
  }) : serverUrl = _normalizeServerUrl(serverUrl) {
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
      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
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
    if (_allSongsCache != null) return _allSongsCache!;

    try {
      final res = await _get('search3.view', {
        'query': '*',
        'songCount': size.toString(),
      });
      final searchResult =
          res['searchResult3'] as Map<String, dynamic>? ?? {};
      final songs = (searchResult['song'] as List<dynamic>? ?? [])
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
      if (songs.length > 10) {
        _allSongsCache = songs;
        return songs;
      }
    } catch (e) {
      debugPrint('Wildcard search failed: $e');
    }

    final result = await getRandomSongs(size: size);
    _allSongsCache = result;
    return result;
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
    final allSongs = <Song>[];
    for (final album in albums) {
      final songs = await getAlbum(album['id'] as String);
      allSongs.addAll(songs);
      if (allSongs.length >= size) break;
    }
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
    if (_recentlyPlayedAlbumsCache != null) return _recentlyPlayedAlbumsCache!;

    final res = await _get('getAlbumList2.view', {'type': 'recent'});
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    _recentlyPlayedAlbumsCache = albums
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
    return _recentlyPlayedAlbumsCache!;
  }

  Future<List<Album>> getFrequentAlbums() async {
    if (_frequentAlbumsCache != null) return _frequentAlbumsCache!;

    final res = await _get('getAlbumList2.view', {'type': 'frequent'});
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    _frequentAlbumsCache = albums
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
    return _frequentAlbumsCache!;
  }

  Future<List<Album>> getAlbums({int offset = 0, int size = 50}) async {
    if (offset == 0 && size == 1000 && _albumsCache != null) {
      return _albumsCache!;
    }

    final res = await _get('getAlbumList2.view', {
      'type': 'alphabeticalByArtist',
      'offset': offset.toString(),
      'size': size.toString(),
    });
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    final result =
        albums.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();

    if (offset == 0 && size == 1000) _albumsCache = result;
    return result;
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
    if (_playlistsCache != null) return _playlistsCache!;

    final res = await _get('getPlaylists.view');
    final playlists =
        (res['playlists'] as Map<String, dynamic>)['playlist'] as List<dynamic>? ??
            [];
    _playlistsCache = playlists
        .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
        .toList();
    return _playlistsCache!;
  }

  Future<List<Song>> getPlaylistSongs(String id) async {
    final res = await _get('getPlaylist.view', {'id': id});
    final songs =
        (res['playlist'] as Map<String, dynamic>)['entry'] as List<dynamic>? ??
            [];
    return songs
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createPlaylist(String name) async {
    await _get('createPlaylist.view', {'name': name});
    _playlistsCache = null; // invalidate so next fetch is fresh
  }

  Future<void> deletePlaylist(String id) async {
    await _get('deletePlaylist.view', {'id': id});
    _playlistsCache = null; // invalidate
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
    _playlistsCache = null; // content changed — invalidate
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

  /// Clears all in-memory caches. Call this on logout or server change.
  void clearCache() {
    _recentlyPlayedAlbumsCache = null;
    _frequentAlbumsCache = null;
    _playlistsCache = null;
    _allSongsCache = null;
    _albumsCache = null;
  }

  /// Invalidates only the recently-played / frequent caches (call after
  /// scrobble so the next fetch reflects the updated play counts).
  void invalidatePlayHistory() {
    _recentlyPlayedAlbumsCache = null;
    _frequentAlbumsCache = null;
  }

  // BUG-3: close the http.Client to release socket connections.
  void dispose() {
    _client.close();
  }
}