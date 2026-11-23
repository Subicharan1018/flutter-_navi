import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../online_fetch/data/online_fetch_api.dart' show guardFetchCall;
import 'data_queue_models.dart';

/// Client for the shuffle server's admin-only `/data-queue` routes. Built on the fetch Dio (slow answers
/// are waited for, a POST is never replayed): the upload fits a model and can take a few seconds.
class DataQueueApi {
  final Dio _dio;
  const DataQueueApi(this._dio);

  Future<QueueStatus> status() => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/data-queue/status');
        return QueueStatus.fromJson(r.data!);
      });

  /// Makes this week's batch, or returns the one that is still open. Null when nothing waits.
  Future<QueueBatch?> makeBatch() => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/data-queue/batches', data: const {});
        final b = r.data?['batch'];
        return b is Map ? QueueBatch.fromJson(b.cast<String, dynamic>()) : null;
      });

  Future<List<QueueBatch>> history() => guardFetchCall(() async {
        final r = await _dio.get<Map<String, dynamic>>('/data-queue/batches');
        return [for (final j in (r.data?['batches'] as List?) ?? const []) QueueBatch.fromJson((j as Map).cast<String, dynamic>())];
      });

  /// The transfer file ([format] `csv` or `txt`).
  Future<Uint8List> file(int batchId, String format) => guardFetchCall(() async {
        final r = await _dio.get<List<int>>('/data-queue/batches/$batchId/file.$format',
            options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data ?? const []);
      });

  /// Sends the Exportify CSV's text for [batchId]. The same file twice answers with `repeated`.
  Future<UploadSummary> upload(int batchId, String name, String csv) => guardFetchCall(() async {
        final r = await _dio.post<Map<String, dynamic>>('/data-queue/batches/$batchId/upload',
            data: {'name': name, 'csv': csv});
        return UploadSummary.fromJson(r.data!);
      });

  Future<void> release(int batchId) => guardFetchCall(() async {
        await _dio.post<Map<String, dynamic>>('/data-queue/batches/$batchId/release', data: const {});
      });
}
