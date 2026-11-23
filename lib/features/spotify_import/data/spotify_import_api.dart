import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import '../logic/spotify_parser.dart';
import 'spotify_import_models.dart';

/// Client for the shuffle server's `/spotify-import` routes. Build it on the fetch Dio, so a slow answer is
/// waited for and a POST is never replayed. Only [SpotifyPlay.toJson]'s fields are ever sent.
class SpotifyImportApi {
  final Dio _dio;
  const SpotifyImportApi(this._dio);

  /// Starts an import, or returns the unfinished one (that is the resume: pages sent again add nothing).
  Future<SpotifyJob> create(SpotifyFormat format, int total) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/spotify-import/jobs',
      data: {'format': format.wire, 'total': total},
    );
    return SpotifyJob.fromJson(r.data!);
  });

  /// The person's Spotify imports, newest first.
  Future<List<SpotifyJob>> jobs() => guardFetchCall(() async {
    final r = await _dio.get<List<dynamic>>('/spotify-import/jobs');
    return [for (final j in r.data ?? const []) SpotifyJob.fromJson(j as Map<String, dynamic>)];
  });

  /// Sends one page of plays (at most [spotifyPageSize]).
  Future<SpotifyJob> page(int id, List<SpotifyPlay> plays) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/spotify-import/jobs/$id/page',
      data: {'plays': [for (final p in plays) p.toJson()]},
    );
    return SpotifyJob.fromJson(r.data!);
  });

  Future<SpotifyJob> finish(int id) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>('/spotify-import/jobs/$id/finish', data: const {});
    return SpotifyJob.fromJson(r.data!);
  });

  /// Takes back every play and Wishlist song this import added (history-import-v1's undo). Returns plays removed.
  Future<int> undo(int id) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>('/history-import/jobs/$id/undo', data: const {});
    final n = r.data?['removed_plays'];
    return n is num ? n.toInt() : 0;
  });
}
