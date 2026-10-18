/// Errores del dominio. La UI nunca ve excepciones de Dio ni de Supabase.
sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Sin conexión, timeout o servidor inalcanzable.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No hay conexión. Revisa tu internet e inténtalo de nuevo.']);
}

/// 401: token vencido o credenciales inválidas. Hay que volver a iniciar sesión.
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([super.message = 'Tu sesión venció. Inicia sesión de nuevo.']);
}

/// 403: el rol no alcanza.
final class ForbiddenFailure extends Failure {
  const ForbiddenFailure([super.message = 'No tienes permiso para hacer esto.']);
}

/// 404: no existe o es de otra cuenta (la API nunca distingue).
final class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'No encontramos lo que buscas.']);
}

/// 409: franja llena, cupo agotado, límite de colas, nombre repetido.
final class ConflictFailure extends Failure {
  const ConflictFailure(super.message);
}

/// 400: regla de negocio (fuera de horario, transición inválida, franja pasada…).
final class BadRequestFailure extends Failure {
  const BadRequestFailure(super.message);
}

/// 422: datos inválidos. [fields] mapea campo → mensaje cuando la API lo informa.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [this.fields = const {}]);
  final Map<String, String> fields;
}

/// 429: demasiados requests.
final class RateLimitedFailure extends Failure {
  const RateLimitedFailure([super.message = 'Demasiados intentos. Espera un momento.']);
}

/// 5xx o respuesta inesperada.
final class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Algo salió mal de nuestro lado. Inténtalo en un momento.']);
}

/// Cualquier otro error no previsto.
final class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Ocurrió un error inesperado.']);
}
