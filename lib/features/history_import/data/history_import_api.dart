import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'history_import_models.dart';

/// Client for the shuffle server's `/history-import` routes. Build it on the fetch Dio, so a slow answer
/// is waited for and a POST is never replayed.
class HistoryImportApi {
  final Dio _dio;
  const HistoryImportApi(this._dio);

  /// Starts an import, or returns the unfinished one for the same account (that is the resume).
  /// [full] reads the whole history again instead of only what is new since the last import.
  Future<HistoryJob> create(HistorySource source, String account, {bool full = false}) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/history-import/jobs',
      data: {'source': source.wire, 'account': account, if (full) 'full': true},
    );
    return HistoryJob.fromJson(r.data!)!;
  });

  /// The user's imports, newest first.
  Future<List<HistoryJob>> jobs() => guardFetchCall(() async {
    final r = await _dio.get<List<dynamic>>('/history-import/jobs');
    return [for (final j in r.data ?? const []) ?HistoryJob.fromJson(j as Map<String, dynamic>)];
  });

  /// Reads one page. [secret] (the Last.fm API key) goes with this request only; the server does not keep it.
  Future<HistoryStep> step(int id, {String? secret}) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/history-import/jobs/$id/step',
      data: {if (secret != null && secret.isNotEmpty) 'secret': secret},
    );
    final j = r.data!;
    return HistoryStep(
      HistoryJob.fromJson(j)!,
      done: j['done'] == true,
      waitS: j['wait_s'] is num ? (j['wait_s'] as num).ceil() : 0,
      fatal: j['fatal'] == true,
    );
  });

  Future<void> cancel(int id) => guardFetchCall(() async {
    await _dio.post<Map<String, dynamic>>('/history-import/jobs/$id/cancel', data: const {});
  });

  /// Takes back every play and Wishlist song this source's imports added. Returns the plays removed.
  Future<int> undo(int id) => guardFetchCall(() async {
    final r = await _dio.post<Map<String, dynamic>>('/history-import/jobs/$id/undo', data: const {});
    final n = r.data?['removed_plays'];
    return n is num ? n.toInt() : 0;
  });
}
