import 'dart:convert';
import 'dart:io';
import 'dart:io' as dart_io;
import 'dart:async' as dart_async;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../core/constants.dart';
import '../core/app_exception.dart';
import '../core/hive_boxes.dart';
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
  final http.Client _client;

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

  static const int _webDavMaxAttempts = 3;
  static const int _webDavChunkSize = 64 * 1024;

  SubsonicService({
    required String serverUrl,
    required this.username,
    required this.password,
    required PlaylistCacheService cache,
    http.Client? client,
    this.customUploadUrl,
    this.customUploadDir,
    this.webdavUsername,
    this.webdavPassword,
  })  : serverUrl = _normalizeServerUrl(serverUrl),
        _cache = cache,
        _client = client ?? http.Client() {
    // BUG-8: Restore or generate a stable salt for cover-art URLs.
    // We compute the token dynamically so it updates if the password changes.
    // Changed key to coverArtSalt_v2 to permanently bust the corrupted CachedNetworkImage cache.
    final box = HiveBoxes.auth;
    final savedSalt = box.get('coverArtSalt_v2')?.toString();

    if (savedSalt != null && savedSalt.isNotEmpty) {
      _coverArtSalt = savedSalt;
    } else {
      _coverArtSalt = _generateSalt();
      box.put('coverArtSalt_v2', _coverArtSalt);
    }
    
    // Always generate token from current password so it never goes stale
    _coverArtToken = _generateToken(_coverArtSalt);
  }

  static String _normalizeServerUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return Constants.defaultServerUrl;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.parse(url);

    if (uri.scheme == 'http') {
      final allowHttp = HiveBoxes.prefs.get(HiveBoxes.kAllowHttp) == true;
      if (!allowHttp) {
        throw const NetworkException(
          'Insecure connection rejected. NaviVibe requires HTTPS. Enable "Allow HTTP" in Advanced Settings to override.',
        );
      }
    }

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
  String getCoverArtUrl(String? coverArtId, {int? size}) {
    if (coverArtId == null || coverArtId.isEmpty) return '';
    final params = {'id': coverArtId};
    if (size != null) params['size'] = size.toString();
    return _buildStableUrl('getCoverArt.view', params);
  }

  // ---------------------------------------------------------------------------
  // HTTP helper
  // ---------------------------------------------------------------------------

  Future<dynamic> _get(String endpoint, [Map<String, String>? params]) async {
    final url = _buildUrl(endpoint, params);
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401) throw const AuthException();
      if (response.statusCode != 200) {
        throw ServerException(response.statusCode);
      }

      // BUG-29: parse JSON on a background isolate — response.body can be
      // 2–5 MB for large song libraries; doing this on the main thread
      // causes visible freezes of 300–800 ms.
      final jsonResponse = await compute(_decodeJsonBody, response.body);
      final subsonicResponse =
          jsonResponse['subsonic-response'] as Map<String, dynamic>;

      if (subsonicResponse['status'] == 'ok') {
        return subsonicResponse;
      } else {
        final error = subsonicResponse['error'] as Map<String, dynamic>?;
        final code = error?['code'] as int? ?? 0;
        final msg  = error?['message']?.toString() ?? 'Subsonic API error';
        // Subsonic error codes 40 (wrong creds) / 41 (token not supported)
        if (code == 40 || code == 41) throw const AuthException();
        throw SubsonicApiException(code, msg);
      }
    } on AuthException {
      rethrow;
    } on ServerException {
      rethrow;
    } on SubsonicApiException {
      rethrow;
    } on dart_io.SocketException catch (e) {
      debugPrint('[SubsonicService] SocketException: ${e.message}, host: ${e.address?.host}, port: ${e.port}');
      throw NetworkException('No internet connection: ${e.message}');
    } on dart_async.TimeoutException {
      debugPrint('[SubsonicService] TimeoutException');
      throw const TimeoutException();
    } catch (e) {
      debugPrint('[SubsonicService] Unexpected error: $e');
      // Wrap any other unexpected error so callers don't need to handle
      // raw platform exceptions.
      throw NetworkException(e.toString());
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

  Future<List<Song>> getAllSongs({int size = 5000, int offset = 0}) async {
    // BUG-29: Song.fromJson mapping moved to background isolate.
    // BUG-31: in-memory cache removed — Riverpod allSongsProvider.keepAlive()
    //         is the authoritative cache.
    try {
      final res = await _get('search3.view', {
        'query': '*',
        'songCount': size.toString(),
        'songOffset': offset.toString(),
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
    final toFetch = albums.take(10).map((a) => a['id']?.toString() ?? '').toList();
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

  /// General-purpose album list — supports all Subsonic 'type' values:
  /// newest, recent, frequent, highest, starred, random, alphabeticalByName,
  /// alphabeticalByArtist, byYear, byGenre.
  Future<List<Album>> getAlbumList({
    String type = 'recent',
    int size = 20,
    int offset = 0,
  }) async {
    final res = await _get('getAlbumList2.view', {
      'type': type,
      'size': size.toString(),
      'offset': offset.toString(),
    });
    final albums =
        (res['albumList2'] as Map<String, dynamic>)['album'] as List<dynamic>? ??
            [];
    return albums.map((e) => Album.fromJson(e as Map<String, dynamic>)).toList();
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

  Future<Song> getSong(String id) async {
    final res = await _get('getSong.view', {'id': id});
    final song = res['song'] as Map<String, dynamic>;
    return Song.fromJson(song);
  }

  Future<List<Song>> getSongs(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Fetch all concurrently. Subsonic doesn't have a batch getSong.
    final results = await Future.wait(ids.map((id) => getSong(id).then((s) => s as Song?).catchError((e) {
      debugPrint('Failed to fetch song $id: $e');
      return null;
    })));
    return results.whereType<Song>().toList();
  }

  Future<({List<Song> songs, List<Album> albums})> getStarred() async {
    final res = await _get('getStarred.view');
    final starred = res['starred'] as Map<String, dynamic>? ?? {};

    final songs = (starred['song'] as List<dynamic>? ?? [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();

    final albums = (starred['album'] as List<dynamic>? ?? [])
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();

    return (songs: songs, albums: albums);
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
      return <Song>[];
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
    
    // Invalidate cache so the next getPlaylistSongs call re-fetches fresh data
    await invalidatePlaylist(playlistId);
  }

  /// CRIT-4: Replaces the server-side song list for [playlistId] with [songIds]
  /// in the given order.
  ///
  /// Subsonic's `createPlaylist.view?playlistId=X&songId=a&songId=b...` replaces
  /// the existing playlist content — it does NOT create a new playlist when
  /// `playlistId` is provided.
  ///
  /// `Map<String, String>` cannot express repeated keys so we build the URI
  /// manually using [Uri.queryParametersAll] which accepts `Map<String, List<String>>`.
  Future<void> setPlaylistSongs(
      String playlistId, List<String> songIds) async {
    final salt = _generateSalt();
    final token = _generateToken(salt);

    final uri = Uri.parse('$serverUrl/createPlaylist.view').replace(
      queryParameters: {
        'u': [username],
        't': [token],
        's': [salt],
        'v': [Constants.apiVersion],
        'c': [Constants.defaultClient],
        'f': ['json'],
        'playlistId': [playlistId],
        'songId': songIds, // repeated key — sets the full ordered song list
      },
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('setPlaylistSongs HTTP ${response.statusCode}');
    }
    // Invalidate cache so the next open reflects the new order.
    await invalidatePlaylist(playlistId);
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
        .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
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

  Future<void> scrobble(String songId, {required bool submission}) async {
    try {
      final url = _buildUrl('scrobble.view', {
        'id': songId,
        'submission': submission.toString(),
        'time': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      await _client.get(Uri.parse(url));
    } catch (_) {
      // fire-and-forget: swallow all errors silently
    }
  }

  // ---------------------------------------------------------------------------
  // Lyrics
  // ---------------------------------------------------------------------------

  /// Fetches structured lyrics via the OpenSubsonic `getLyricsBySongId` endpoint.
  ///
  /// Returns the best [Map] from `structuredLyrics[]` (preferring synced entries),
  /// or `null` if the server does not support the extension, returns an empty
  /// list, or an error occurs.
  ///
  /// Callers should inspect the `synced` key on the returned map to decide
  /// whether to treat the `line[]` array as timestamped or plain text.
  Future<Map<String, dynamic>?> getLyricsBySongId(String songId) async {
    try {
      final res = await _get('getLyricsBySongId.view', {'id': songId});
      final lyricsList = res['lyricsList'];
      if (lyricsList == null) return null;

      final structured = lyricsList['structuredLyrics'];
      if (structured == null || structured is! List || structured.isEmpty) {
        return null;
      }

      // Prefer a synced entry; fall back to unsynced if that is all we have.
      Map<String, dynamic>? syncedEntry;
      Map<String, dynamic>? unsyncedEntry;

      for (final entry in structured) {
        if (entry is! Map<String, dynamic>) continue;
        final isSynced = entry['synced'] == true;
        final lines = entry['line'];
        if (lines == null || lines is! List || lines.isEmpty) continue;
        if (isSynced) {
          syncedEntry ??= entry;
        } else {
          unsyncedEntry ??= entry;
        }
      }

      return syncedEntry ?? unsyncedEntry;
    } catch (e) {
      debugPrint('[SubsonicService] getLyricsBySongId error: $e');
      return null;
    }
  }


  Future<String?> getLyrics({String? artist, String? title}) async {
    try {
      final params = <String, String>{};
      if (artist != null) params['artist'] = artist;
      if (title != null) params['title'] = title;
      final res = await _get('getLyrics.view', params);
      return (res['lyrics'] as Map<String, dynamic>?)?['value']?.toString();
    } catch (e) {
      debugPrint('Error fetching lyrics: $e');
      return null;
    }
  }

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

  Future<void> uploadTextToWebDav({
    required String remoteFileName,
    required String contents,
    String contentType = 'text/csv; charset=utf-8',
  }) async {
    if (customUploadUrl == null || customUploadUrl!.isEmpty) {
      throw Exception('WebDAV upload URL is not configured');
    }

    await _webDavUploadText(remoteFileName, contents, contentType: contentType);
  }

  // ---------------------------------------------------------------------------
  // WebDAV Upload
  // ---------------------------------------------------------------------------

  Uri _buildWebDavUploadUri(String targetFileName) {
    final baseUri = Uri.parse(
      customUploadUrl!.trim().replaceAll(RegExp(r'/+$'), ''),
    );

    final remoteDir =
        (customUploadDir == null || customUploadDir!.trim().isEmpty)
            ? '/DATA/Media/Music'
            : customUploadDir!.trim();

    final normalizedDir = remoteDir.startsWith('/') ? remoteDir : '/$remoteDir';
    final dirSegments = normalizedDir
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final fileSegments = targetFileName
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    return baseUri.replace(
      pathSegments: <String>[
        ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        ...dirSegments,
        ...fileSegments,
      ],
    );
  }

  bool _isRetryableWebDavStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  Future<void> _webDavUploadText(
    String targetFileName,
    String contents, {
    String contentType = 'text/csv; charset=utf-8',
  }) async {
    final bytes = utf8.encode(contents);
    await _webDavUploadStream(
      targetFileName: targetFileName,
      bodyStreamFactory: () => Stream<List<int>>.value(bytes),
      contentLength: bytes.length,
      contentType: contentType,
    );
  }

  Future<void> _webDavUploadStream({
    required String targetFileName,
    required Stream<List<int>> Function() bodyStreamFactory,
    required int contentLength,
    required String contentType,
  }) async {
    final uri = _buildWebDavUploadUri(targetFileName);

    if (webdavUsername == null || webdavUsername!.isEmpty ||
        webdavPassword == null || webdavPassword!.isEmpty) {
      throw const AuthException();
    }

    final webdavUser = webdavUsername!;
    final webdavPass = webdavPassword!;
    final auth = base64Encode(utf8.encode('$webdavUser:$webdavPass'));

    Object? lastError;
    for (var attempt = 1; attempt <= _webDavMaxAttempts; attempt++) {
      final request = http.StreamedRequest('PUT', uri)
        ..headers.addAll({
          'Authorization': 'Basic $auth',
          'Content-Type': contentType,
          'Content-Length': contentLength.toString(),
        })
        ..persistentConnection = true
        ..followRedirects = false;

      try {
        final responseFuture = _client.send(request);

        try {
          await request.sink.addStream(bodyStreamFactory());
        } finally {
          await request.sink.close();
        }

        final streamedResponse = await responseFuture;
        debugPrint(
            'Upload(WebDAV): Response status: ${streamedResponse.statusCode}');

        if (streamedResponse.statusCode == 200 ||
            streamedResponse.statusCode == 201 ||
            streamedResponse.statusCode == 204) {
          return;
        }

        final body = await streamedResponse.stream.bytesToString();
        debugPrint('Upload(WebDAV): Response body: $body');

        if (_isRetryableWebDavStatus(streamedResponse.statusCode) &&
            attempt < _webDavMaxAttempts) {
          lastError = Exception(
            'WebDAV upload failed (${streamedResponse.statusCode}): $body',
          );
        } else {
          throw Exception(
            'WebDAV upload failed (${streamedResponse.statusCode}): $body',
          );
        }
      } on dart_io.SocketException catch (e) {
        lastError = e;
      } on dart_async.TimeoutException catch (e) {
        lastError = e;
      }

      if (attempt < _webDavMaxAttempts) {
        await dart_async.Future<void>.delayed(
          Duration(milliseconds: 250 * attempt),
        );
      }
    }

    throw Exception('WebDAV upload failed after $_webDavMaxAttempts attempts: '
        '$lastError');
  }

  Future<void> _webDavUpload(File file, String targetFileName) async {
    if (!await file.exists()) {
      throw Exception('WebDAV upload failed: file does not exist');
    }

    await _webDavUploadStream(
      targetFileName: targetFileName,
      bodyStreamFactory: () => file.openRead(),
      contentLength: await file.length(),
      contentType: 'application/octet-stream',
    );
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

  /// Exposes the shared HTTP client for reuse by co-located services
  /// (e.g. [ListeningLogService]).
  ///
  /// **Do NOT close this client** — [SubsonicService.dispose] owns its lifecycle.
  http.Client get client => _client;

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
