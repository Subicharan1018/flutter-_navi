import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'album_overnight_models.dart';

/// Client for the shuffle server's `/exportify/album-overnight` routes. Build it on the fetch Dio, so a slow
/// answer is waited for and a POST is never replayed.
class AlbumOvernightApi {
  final Dio _dio;
  const AlbumOvernightApi(this._dio);

  Future<AlbumOvernight> current() => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/exportify/album-overnight');
        return AlbumOvernight.fromJson(r.data!);
      });

  /// Turn it on or off, choose film albums only, the songs a night and the most tracks an album.
  Future<AlbumOvernight> setPrefs({bool? enabled, bool? filmOnly, int? perNight, int? maxPerAlbum}) => guardFetchCall(() async {
        final r = await _dio.put<Map<String, dynamic>>('/exportify/album-overnight/prefs', data: {
          'enabled': ?enabled,
          'film_only': ?filmOnly,
          'per_night': ?perNight,
          'max_per_album': ?maxPerAlbum,
        });
        return AlbumOvernight.fromJson(r.data!);
      });

  /// Drop what is not with the bot yet. The album is not queued again.
  Future<CancelResult> cancelAlbum(int id) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/exportify/album-overnight/albums/$id/cancel', data: const {});
        return CancelResult.fromJson(r.data ?? const {});
      });

  Future<CancelResult> cancelAll() => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/exportify/album-overnight/cancel-all', data: const {});
        return CancelResult.fromJson(r.data ?? const {});
      });
}
