import 'package:dio/dio.dart';

import 'recognize_models.dart';

/// Recognition failed. [message] is safe to show as is.
class RecognizeException implements Exception {
  final String message;
  final int? statusCode;
  const RecognizeException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Client for the shuffle server's `POST /recognize`: uploads a short mic
/// recording; the server fingerprints it, looks it up and matches the answer
/// against the library. Build the Dio with `createShuffleDio`.
class RecognizeApi {
  final Dio _dio;
  const RecognizeApi(this._dio);

  Future<RecognizeResult> recognize(String audioPath) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/recognize',
        data: FormData.fromMap({
          'audio': await MultipartFile.fromFile(
            audioPath,
            filename: 'clip.wav',
          ),
        }),
        options: Options(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      return RecognizeResult.fromJson(r.data ?? const {});
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final serverMessage = body is Map && body['error'] is String
          ? body['error'] as String
          : null;
      throw RecognizeException(switch (code) {
        null => 'Can’t reach the server. Check your connection.',
        401 => 'Sign in again to identify songs.',
        404 => 'Your server doesn’t support song recognition yet.',
        503 =>
          serverMessage ?? 'Song recognition isn’t set up on your server yet.',
        _ => serverMessage ?? 'Song recognition isn’t available right now.',
      }, statusCode: code);
    }
  }
}
