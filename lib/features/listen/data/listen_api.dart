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
/// `/flow/next`, `/flow/moods`, `/flow/prefs`, `/moods/…`, `/taste/exclusions` and `/stats/month`. Build
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
    String? session,
  }) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/flow/next',
          data: {
            'count': count,
            'mood': ?mood,
            'session': ?session,
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

  /// Your "Not this mood" marks: song id → the moods you said it is not.
  Future<Map<String, Set<String>>> moodOverrides() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/moods/overrides');
        return parseMoodOverrides(r.data ?? const {});
      });

  /// Marks [songId] as not [mood] for you; it beats the server's label in
  /// Flow and Smart Playlists. [undo] takes the mark back.
  Future<void> setNotThisMood(String songId, String mood, {bool undo = false}) => _wrap(() async {
        final body = {'song_id': songId, 'mood': mood};
        final options = Options(contentType: 'application/json');
        if (undo) {
          await _dio.delete<Map<String, dynamic>>('/moods/not-this', data: body, options: options);
        } else {
          await _dio.post<Map<String, dynamic>>('/moods/not-this', data: body, options: options);
        }
      });

  /// Whether you may change songs' moods for everyone (`GET /moods/me`).
  Future<bool> moodsIsAdmin() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/moods/me');
        return r.data?['is_admin'] == true;
      });

  /// Admins only: [moods] (at most 2, most fitting first; empty = no mood)
  /// become the song's moods for everyone. Returns the moods the server kept.
  Future<List<String>> setSongMoods(String songId, List<String> moods) => _wrap(() async {
        final r = await _dio.put<Map<String, dynamic>>(
          '/moods/songs/${Uri.encodeComponent(songId)}',
          data: {'moods': moods},
          options: Options(contentType: 'application/json'),
        );
        final song = r.data?['song'];
        return song is Map && song['moods'] is List ? [for (final m in song['moods'] as List) m.toString()] : moods;
      });

  /// The Flow language setting, with the languages the library has.
  Future<FlowPrefs> flowPrefs() => _wrap(() async {
        final r = await _dio.get<Map<String, dynamic>>('/flow/prefs');
        return FlowPrefs.fromJson(r.data ?? const {});
      });

  /// Saves what is given (the rest stays as it was) and returns the setting.
  Future<FlowPrefs> saveFlowPrefs({List<String>? languages, bool? explore}) => _wrap(() async {
        final r = await _dio.put<Map<String, dynamic>>(
          '/flow/prefs',
          data: {'languages': ?languages, 'explore': ?explore},
          options: Options(contentType: 'application/json'),
        );
        return FlowPrefs.fromJson(r.data ?? const {});
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
        403 => 'Only an admin can change that for everyone.',
        503 => 'The server is still starting up. Try again in a minute.',
        _ => 'The server couldn’t answer that right now.',
      });
    }
  }
}
