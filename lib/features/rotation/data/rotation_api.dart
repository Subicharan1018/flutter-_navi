import 'package:dio/dio.dart';

import '../../listen/data/listen_api.dart' show ListenException;
import '../../listen/data/listen_models.dart';
import 'rotation_models.dart';

/// Client for the shuffle server's rotation routes: `/rotation`, `/rotation/rest`,
/// `/rotation/season`, `/rotation/prefs` and `/rotation/back`.
class RotationApi {
  final Dio _dio;
  const RotationApi(this._dio);

  static final _json = Options(contentType: 'application/json');

  Future<Rotation> rotation() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/rotation');
        return Rotation.fromJson(r.data ?? const {});
      });

  /// Rests [songId] for [days]; [label] (the title) is kept so the list can name it.
  Future<void> rest(String songId, int days, {String? label}) => _wrap(() async {
        await _dio.post<Map<String, dynamic>>('/rotation/rest',
            data: {'song_id': songId, 'days': days, 'label': ?label}, options: _json);
      });

  Future<void> unrest(String songId) => _wrap(() async {
        await _dio.delete<Map<String, dynamic>>('/rotation/rest', data: {'song_id': songId}, options: _json);
      });

  /// Tags [songId] with a season key, `none` (never seasonal) or null (forget the tag).
  Future<void> setSeason(String songId, String? season) => _wrap(() async {
        await _dio.put<Map<String, dynamic>>('/rotation/season', data: {'song_id': songId, 'season': season}, options: _json);
      });

  Future<RotationPrefs> savePrefs({bool? autoRest, bool? seasons, bool? back}) => _wrap(() async {
        final r = await _dio.put<Map<String, dynamic>>('/rotation/prefs',
            data: {'auto_rest': ?autoRest, 'seasons': ?seasons, 'back': ?back}, options: _json);
        return RotationPrefs.fromJson(r.data?['prefs']);
      });

  /// Songs you loved long ago and have not played for two months.
  Future<List<ListenPick>> back({int limit = 20}) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/rotation/back', queryParameters: {'limit': limit});
        return ListenPick.parseAll(r.data?['items']);
      });

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ListenException(switch (e.response?.statusCode) {
        null => 'Can’t reach the server. Check your connection.',
        401 => 'Sign in again to continue.',
        503 => 'The server is still starting up. Try again in a minute.',
        _ => 'The server couldn’t answer that right now.',
      });
    }
  }
}
