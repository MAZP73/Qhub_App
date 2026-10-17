import 'package:dio/dio.dart';
import 'package:qhub_core/qhub_core.dart';

import '../domain/entities.dart';

/// Estado de sesión que leen los interceptores. Lo escribe la app (login/logout).
class ApiContext {
  ApiContext({this.token, this.actor, this.onUnauthorized});

  String? token;
  Actor? actor;

  /// Se invoca ante un 401 en un endpoint de negocio (token vencido: no hay refresh).
  void Function()? onUnauthorized;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  void clear() {
    token = null;
    actor = null;
  }
}

/// Crea el [Dio] con los headers de identidad de la API.
Dio createQhubDio({
  required String baseUrl,
  required ApiContext context,
  HttpClientAdapter? adapter,
  Duration timeout = const Duration(seconds: 20),
}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: timeout,
    receiveTimeout: timeout,
    sendTimeout: timeout,
    contentType: Headers.jsonContentType,
    responseType: ResponseType.json,
  ));
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.add(QhubAuthInterceptor(context));
  return dio;
}

class QhubAuthInterceptor extends Interceptor {
  QhubAuthInterceptor(this._context);
  final ApiContext _context;

  static bool _isPublic(String path) => path.startsWith('/auth/') || path == '/' || path == '/listo';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_isPublic(options.path)) {
      final token = _context.token;
      final actor = _context.actor;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      if (actor != null) {
        options.headers['X-Usuario-Id'] = actor.userId;
        options.headers['X-Usuario-Rol'] = actor.role.wire;
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && !_isPublic(err.requestOptions.path)) {
      _context.onUnauthorized?.call();
    }
    handler.next(err);
  }
}

/// Traduce cualquier error de red/HTTP a un [Failure] del dominio.
Failure mapError(Object error) {
  if (error is Failure) return error;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure('Operación cancelada.');
      default:
        break;
    }
    final res = error.response;
    if (res == null) return const NetworkFailure();
    final code = res.statusCode ?? 0;
    final parsed = _parseDetail(res.data);
    final msg = parsed.message;
    return switch (code) {
      400 => BadRequestFailure(msg ?? 'La solicitud no es válida.'),
      401 => UnauthorizedFailure(msg ?? 'Tu sesión venció. Inicia sesión de nuevo.'),
      403 => ForbiddenFailure(msg ?? 'No tienes permiso para hacer esto.'),
      404 => NotFoundFailure(msg ?? 'No encontramos lo que buscas.'),
      409 => ConflictFailure(msg ?? 'Esa acción choca con el estado actual.'),
      422 => ValidationFailure(msg ?? 'Revisa los datos ingresados.', parsed.fields),
      429 => const RateLimitedFailure(),
      >= 500 => const ServerFailure(),
      _ => UnknownFailure(msg ?? 'Ocurrió un error inesperado.'),
    };
  }
  return const UnknownFailure();
}

({String? message, Map<String, String> fields}) _parseDetail(Object? data) {
  if (data is! Map) return (message: null, fields: const {});
  final detail = data['detail'];
  if (detail is String) return (message: detail, fields: const {});
  if (detail is List) {
    final fields = <String, String>{};
    final lines = <String>[];
    for (final item in detail) {
      if (item is Map) {
        final loc = item['loc'];
        final field = loc is List && loc.isNotEmpty ? loc.last.toString() : '';
        final msg = '${item['msg'] ?? 'Dato inválido'}';
        if (field.isNotEmpty && field != 'body') fields[field] = msg;
        lines.add(field.isEmpty ? msg : '$field: $msg');
      }
    }
    return (message: lines.isEmpty ? null : lines.join('\n'), fields: fields);
  }
  if (detail is Map && detail['message'] is String) {
    return (message: detail['message'] as String, fields: const {});
  }
  return (message: null, fields: const {});
}

/// Ejecuta [body] y devuelve un [Result], mapeando errores.
Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Result.ok(await body());
  } catch (e) {
    return Result.err(mapError(e));
  }
}
