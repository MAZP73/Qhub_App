import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:qhub_api_client/qhub_api_client.dart';

import '../domain/gateway.dart';

class ProxyRequest {
  const ProxyRequest({required this.method, required this.path, this.query = const {}, this.body});
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;

  Map<String, Object?> toJson(String organizationId) => {
        'organizacion_id': organizationId,
        'method': method,
        'path': path,
        'query': query,
        if (body != null) 'body': body,
      };
}

class ProxyResult {
  const ProxyResult(this.status, this.body);
  final int status;
  final Object? body;
}

/// Envía la petición a la Edge Function y devuelve el sobre `{status, body}`.
typedef ProxyInvoker = Future<ProxyResult> Function(String organizationId, ProxyRequest request);

/// Hace que los repositorios de `qhub_api_client` funcionen igual a través del proxy:
/// convierte cada request de Dio en una llamada a la función y su sobre en una respuesta HTTP.
class ProxyHttpClientAdapter implements HttpClientAdapter {
  ProxyHttpClientAdapter(this.organizationId, this.invoke);
  final String organizationId;
  final ProxyInvoker invoke;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final ProxyResult res;
    try {
      res = await invoke(
        organizationId,
        ProxyRequest(
          method: options.method,
          path: options.path,
          query: {for (final e in options.queryParameters.entries) e.key: e.value},
          body: options.data,
        ),
      );
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException.connectionError(requestOptions: options, reason: '$e');
    }
    final payload = res.body == null ? '' : jsonEncode(res.body);
    return ResponseBody.fromString(payload, res.status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Gateway que reutiliza los repositorios del cliente de la API sobre el proxy, uno por organización.
class ProxyQhubGateway implements QhubGateway {
  ProxyQhubGateway(this._invoke);
  final ProxyInvoker _invoke;
  final _dios = <String, Dio>{};

  Dio _dio(String orgId) => _dios.putIfAbsent(
        orgId,
        () => createQhubDio(baseUrl: 'http://qhub.proxy', context: ApiContext(), adapter: ProxyHttpClientAdapter(orgId, _invoke)),
      );

  @override
  QueueRepository queues(String organizationId) => QueueRepositoryImpl(_dio(organizationId));
  @override
  TicketRepository tickets(String organizationId) => TicketRepositoryImpl(_dio(organizationId));
  @override
  NotificationRepository notifications(String organizationId) => NotificationRepositoryImpl(_dio(organizationId));
}
