import 'dart:convert';

import 'package:dio/dio.dart';

/// Answers Dio requests from a script instead of the network.
class FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  final requests = <RequestOptions>[];
  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async {
    requests.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {'content-type': ['application/json']},
    );

Dio fakeDio(FakeAdapter adapter) => Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = adapter;
