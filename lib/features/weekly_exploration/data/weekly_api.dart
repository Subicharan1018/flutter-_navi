import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'weekly_models.dart';

/// Client for the shuffle server's `/weekly/exploration` routes. Build it on the fetch Dio, so a slow
/// answer is waited for and a POST is never replayed.
class WeeklyApi {
  final Dio _dio;
  const WeeklyApi(this._dio);

  /// The page. The first open of a week makes the server build the list: `building` is true until it is done.
  Future<WeeklyExploration> current() => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/weekly/exploration');
        return WeeklyExploration.fromJson(r.data!);
      });

  /// Keep: the song is fetched at night under the weekly cap. Returns where it is now.
  Future<(DownloadStage, String?)> keep(int id) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/weekly/exploration/$id/keep', data: const {});
        final dl = Map<String, dynamic>.from((r.data?['download'] as Map?) ?? const {});
        final p = WeeklyPick.fromJson({'id': id, 'title': '', 'artist': '', 'download': dl});
        return (p.download, p.songId);
      });

  /// Not for me: gone now, not suggested again for six months.
  Future<void> skip(int id) => guardFetchCall(() async {
        await _dio.post<Map<String, dynamic>>('/weekly/exploration/$id/skip', data: const {});
      });

  /// Undo a Not for me.
  Future<void> restore(int id) => guardFetchCall(() async {
        await _dio.post<Map<String, dynamic>>('/weekly/exploration/$id/restore', data: const {});
      });

  /// Turn the weekly list on or off, and set how many kept songs may be downloaded a week.
  Future<WeeklyExploration> setPrefs({bool? enabled, int? cap}) => guardFetchCall(() async {
        final r = await _dio.put<Map<String, dynamic>>('/weekly/exploration/prefs', data: {
          'enabled': ?enabled,
          'cap': ?cap,
        });
        return WeeklyExploration.fromJson(r.data!);
      });
}
