import 'package:dio/dio.dart';

import 'fetch_models.dart';
import 'fetch_queue_models.dart';
import 'server_capabilities.dart';

/// A "Search online" request failed. [message] is safe to show as is.
class OnlineFetchException implements Exception {
  final String message;
  final int? statusCode;

  /// The server is up but slow or busy (502/503/504, or the proxy's
  /// `busy` flag). Not a verdict on the request: keep waiting and asking.
  final bool busy;
  const OnlineFetchException(this.message, {this.statusCode, this.busy = false});

  /// Nothing was decided: no connection, or a slow server. Polls carry on.
  bool get isTransient => statusCode == null || busy;

  @override
  String toString() => message;
}

/// "Search online" waits for a Telegram bot that can take a minute to answer
/// (the server queues and retries on its own), so its requests get more
/// patience than the shuffle API's 20 s receive timeout: a slow answer is
/// "still looking", never an error.
Dio configureFetchTimeouts(Dio dio) {
  dio.options
    ..connectTimeout = const Duration(seconds: 15)
    ..receiveTimeout = const Duration(seconds: 40)
    ..sendTimeout = const Duration(seconds: 20);
  return dio;
}

/// Client for the shuffle server's /fetch routes. Build it with
/// `createShuffleDio` so it shares the shuffle client's auth and retry rules
/// (POSTs are never replayed after a timeout, so a search or download is
/// never created twice).
class OnlineFetchApi {
  final Dio _dio;
  const OnlineFetchApi(this._dio);

  /// What this account may do. Any failure means nothing — the buttons simply
  /// don't appear. A server older than `/me/capabilities` (404) is asked the
  /// old question instead, so a new app still works against it.
  Future<ServerCapabilities> capabilities() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/me/capabilities');
      return ServerCapabilities.fromJson(r.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return ServerCapabilities(download: await enabled());
      return ServerCapabilities.none;
    } catch (_) {
      return ServerCapabilities.none;
    }
  }

  /// Whether this account may use online search (the pre-capabilities
  /// endpoint). Any failure means no.
  Future<bool> enabled() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/fetch/enabled');
      return r.data?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> startSearch(String query, {FetchSearchType type = FetchSearchType.song}) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/searches', data: {
          'query': query,
          if (type != FetchSearchType.song) 'kind': type.name,
        });
        return (r.data!['search_id'] as num).toInt();
      });

  /// An artist result's top songs, as a search to poll like any other.
  Future<int> startArtistSongs(int artistCandidateId) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/searches', data: {'candidate_id': artistCandidateId});
        return (r.data!['search_id'] as num).toInt();
      });

  /// A pasted playlist link: the server lists its songs (owned or new).
  Future<int> startLinkSearch(String link) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/searches', data: {'link': link.trim()});
        return (r.data!['search_id'] as num).toInt();
      });

  /// Downloads a listed link's whole playlist (it becomes the user's playlist).
  Future<int> startLinkBatch(int searchId) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/batches', data: {'search_id': searchId});
        return (r.data!['batch_id'] as num).toInt();
      });

  /// Several songs, or whole albums / playlists, downloaded as one batch.
  Future<int> startBatch(List<int> candidateIds) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/batches', data: {'candidate_ids': candidateIds});
        return (r.data!['batch_id'] as num).toInt();
      });

  Future<FetchBatch> batch(int id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/batches/$id');
        return FetchBatch.fromJson(r.data!);
      });

  /// Records that the user's playlist [playlistId] was made from batch [id].
  Future<void> setBatchPlaylist(int id, String playlistId) => _wrap(() async {
        await _dio.post<Map<String, dynamic>>('/fetch/batches/$id/playlist', data: {'playlist_id': playlistId});
      });

  /// The account's recent batches (without items), to pick up ones still
  /// running after the app restarts.
  Future<List<FetchBatch>> recentBatches() => _wrap(() async {
        final r = await _dio.get<List<dynamic>>('/fetch/batches');
        return [for (final b in r.data ?? const []) FetchBatch.fromJson(b as Map<String, dynamic>)];
      });

  /// The download queue: the account's own downloads, or everyone's for an admin.
  Future<FetchQueue> queue() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/queue');
        return FetchQueue.fromJson(r.data!);
      });

  /// Stops a queued or running batch.
  Future<void> cancelBatch(int id) => _batchAction(id, 'cancel');

  /// Queues a failed or cancelled batch again.
  Future<void> retryBatch(int id) => _batchAction(id, 'retry');

  /// Admin: runs a queued batch next.
  Future<void> moveBatchToTop(int id) => _batchAction(id, 'top');

  Future<void> _batchAction(int id, String action) => _wrap(() async {
        await _dio.post<Map<String, dynamic>>('/fetch/batches/$id/$action');
      });

  Future<FetchSearch> search(int id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/searches/$id');
        return FetchSearch.fromJson(r.data!);
      });

  Future<int> startDownload(int candidateId) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>('/fetch/jobs', data: {'candidate_id': candidateId});
        return (r.data!['job_id'] as num).toInt();
      });

  Future<FetchJob> job(int id) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/fetch/jobs/$id');
        return FetchJob.fromJson(r.data!);
      });

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final serverMessage = body is Map && body['error'] is String ? body['error'] as String : null;
      final busy = code == 502 || code == 504 || (body is Map && body['busy'] == true);
      throw OnlineFetchException(
        switch (code) {
          null => 'Can’t reach the server. Check your connection.',
          401 => 'Sign in again to search online.',
          429 => serverMessage ?? 'Too many requests. Try again in a minute.',
          _ when busy => 'The server is busy — still working on it.',
          _ => serverMessage ?? 'Online search isn’t available right now.',
        },
        statusCode: code,
        busy: busy,
      );
    }
  }
}
