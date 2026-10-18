import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.query, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> query;
  final Object? body;
}

/// Adaptador HTTP en memoria: responde según `METHOD /path`.
class FakeAdapter implements HttpClientAdapter {
  final Map<String, ({int status, Object? body})> routes = {};
  final List<RecordedRequest> requests = [];

  void on(String route, Object? body, {int status = 200}) => routes[route] = (status: status, body: body);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(RecordedRequest(options.method, options.path, Map.of(options.headers), Map.of(options.queryParameters), options.data));
    final hit = routes['${options.method} ${options.path}'];
    if (hit == null) {
      return ResponseBody.fromString(jsonEncode({'detail': 'sin ruta'}), 404,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    final payload = hit.body == null ? '' : jsonEncode(hit.body);
    return ResponseBody.fromString(payload, hit.status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}
