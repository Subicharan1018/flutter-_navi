import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'exportify_models.dart';

/// Client for the shuffle server's `/exportify` routes (Import a Spotify
/// playlist from an Exportify CSV). Build it on the fetch Dio, so a slow
/// answer is waited for and a POST is never replayed.
class ExportifyApi {
  final Dio _dio;
  const ExportifyApi(this._dio);

  /// Uploads the CSV's text. The server reads and matches it and answers with the result.
  Future<ExportifySummary> createImport(String name, String csv) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/exportify/imports', data: {'name': name, 'csv': csv});
        return ExportifySummary.fromJson(r.data!);
      });

  Future<List<ExportifySummary>> imports() => guardFetchCall(() async {
        final r = await _dio.get<List<dynamic>>('/exportify/imports');
        return [for (final j in r.data ?? const []) ExportifySummary.fromJson(j as Map<String, dynamic>)];
      });

  Future<ExportifySummary> importById(int id) => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/exportify/imports/$id');
        return ExportifySummary.fromJson(r.data!);
      });

  /// One page (200) of the songs in [state], in the file's order.
  Future<List<ExportifySong>> songs(int id, WishlistState state, {int page = 0}) => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/exportify/imports/$id/songs/${state.wire}/$page');
        return [for (final j in (r.data?['songs'] as List?) ?? const []) ExportifySong.fromJson(j as Map<String, dynamic>)];
      });

  /// Navidrome ids of the songs already in the library, in the file's order.
  Future<List<String>> ownedIds(int id) => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/exportify/imports/$id/owned');
        return [for (final s in (r.data?['ids'] as List?) ?? const []) '$s'];
      });

  /// "These N songs need about X GB; you have Y GB free."
  Future<ExportifyEstimate> estimate(int id, PlanDraft draft) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/exportify/imports/$id/estimate', data: planBody(draft));
        return ExportifyEstimate.fromJson(r.data!);
      });

  Future<ExportifySummary> savePlan(int id, PlanDraft draft) => guardFetchCall(() async {
        final r = await _dio.put<Map<String, dynamic>>('/exportify/imports/$id/plan', data: planBody(draft));
        return ExportifySummary.fromJson(r.data!);
      });

  /// Starts (or resumes) the fetch with these settings; the server queues the first batch at once.
  Future<ExportifySummary> start(int id, PlanDraft draft) => _action(id, 'start', planBody(draft));

  /// No new batches. The one already running finishes.
  Future<ExportifySummary> pause(int id) => _action(id, 'pause');

  /// Stops for good: the running batch is cancelled, unfetched songs go back to the wishlist.
  Future<ExportifySummary> cancel(int id) => _action(id, 'cancel');

  /// Puts the failed songs back on the wishlist.
  Future<void> retryFailed(int id) => _action(id, 'retry-failed');

  /// Records that the user's playlist [playlistId] was made from this import's songs.
  Future<void> setPlaylist(int id, String playlistId) => guardFetchCall(() async {
        await _dio.post<Map<String, dynamic>>('/exportify/imports/$id/playlist', data: {'playlist_id': playlistId});
      });

  Future<void> delete(int id) => guardFetchCall(() async {
        await _dio.delete<Map<String, dynamic>>('/exportify/imports/$id');
      });

  Future<ExportifySummary> _action(int id, String action, [Map<String, Object>? body]) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/exportify/imports/$id/$action', data: body ?? const {});
        return ExportifySummary.fromJson(r.data!);
      });
}
