import 'package:dio/dio.dart';

import 'listen_models.dart';

/// A personal-music request failed. [message] is safe to show as is.
class ListenException implements Exception {
  final String message;
  const ListenException(this.message);

  @override
  String toString() => message;
}

/// Client for the shuffle server's personal routes: `/mix/weekly`,
/// `/flow/next`, `/flow/moods`, `/taste/exclusions` and `/stats/month`. Build
/// it with `createShuffleDio` so it shares the shuffle client's auth and retries.
class ListenApi {
  final Dio _dio;
  const ListenApi(this._dio);

  Future<WeeklyMix> weeklyMix() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/mix/weekly');
        return WeeklyMix.fromJson(r.data ?? const {});
      });

  /// The next [count] Flow songs. [seen] are the ids already used, [feedback]
  /// what you did with the last ones.
  Future<FlowBatch> flowNext({
    int count = 8,
    String? mood,
    List<String> seen = const [],
    List<FlowFeedback> feedback = const [],
  }) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/flow/next',
          data: {
            'count': count,
            'mood': ?mood,
            'seen': seen,
            'feedback': [for (final f in feedback) f.toJson()],
          },
          options: Options(contentType: 'application/json'),
        );
        return FlowBatch.fromJson(r.data ?? const {});
      });

  Future<List<FlowMood>> flowMoods() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/flow/moods');
        return parseFlowMoods(r.data ?? const {});
      });

  Future<List<TasteExclusion>> exclusions() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/taste/exclusions');
        return TasteExclusion.parseAll(r.data ?? const {});
      });

  /// Adds one and returns the whole list. [label] is how it reads on screen.
  Future<List<TasteExclusion>> addExclusion(TasteKind kind, String value, {String? label}) => _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/taste/exclusions',
          data: {'kind': kind.name, 'value': value, 'label': ?label},
          options: Options(contentType: 'application/json'),
        );
        return TasteExclusion.parseAll(r.data ?? const {});
      });

  /// Takes one back and returns the whole list.
  Future<List<TasteExclusion>> removeExclusion(TasteKind kind, String value) => _wrap(() async {
        final r = await _dio.delete<Map<String, dynamic>>(
          '/taste/exclusions',
          queryParameters: {'kind': kind.name, 'value': value},
        );
        return TasteExclusion.parseAll(r.data ?? const {});
      });

  /// A month of listening; this month when [month] is null.
  Future<MonthStats> month([MonthKey? month]) => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '/stats/month',
          queryParameters: {if (month != null) 'year': month.year, if (month != null) 'month': month.month},
        );
        return MonthStats.fromJson(r.data ?? const {});
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
