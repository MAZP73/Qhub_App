@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:test/test.dart';

/// Contra la API REAL en un contenedor (sin Supabase ni RabbitMQ): verifica el contrato HTTP/WS,
/// los códigos de error y que cada endpoint y campo que usa el cliente existe en su OpenAPI.
void main() {
  final base = Platform.environment['QHUB_API_URL'];
  if (base == null) {
    test('QHUB_API_URL no definida: se omite', () {}, skip: 'Defínela para correr las pruebas de integración.');
    return;
  }

  late Dio dio;
  late ApiContext ctx;
  var unauthorized = 0;

  setUp(() {
    unauthorized = 0;
    ctx = ApiContext(token: 'no-es-un-token', actor: const Actor(userId: 'u1', role: ActorRole.admin), onUnauthorized: () => unauthorized++);
    dio = createQhubDio(baseUrl: base, context: ctx);
  });

  test('salud: /listo informa degradación y el cliente la entiende', () async {
    final r = await HealthRepositoryImpl(dio).ready();
    expect(r.isOk, isTrue);
    expect(r.valueOrNull!.isReady, isFalse); // sin Supabase en este contenedor
  });

  test('un token inválido es 401 → UnauthorizedFailure y se avisa a la app', () async {
    final r = await QueueRepositoryImpl(dio).list();
    expect(r.failureOrNull, isA<UnauthorizedFailure>());
    expect(unauthorized, 1);
  });

  test('sin token tampoco se entra', () async {
    ctx.clear();
    final r = await TicketRepositoryImpl(dio).mine();
    expect(r.failureOrNull, isA<UnauthorizedFailure>());
  });

  test('validación: registro incompleto es 422 con mensajes por campo', () async {
    final r = await AuthRepositoryImpl(dio).register(const RegisterInput(
      accountType: AccountType.empresa, firstName: 'A', lastName: 'B', username: 'ab', email: 'no-es-correo',
      password: 'corta', country: 'Ecuador', city: 'Quito', acceptedTerms: true));
    final f = r.failureOrNull;
    expect(f, isA<ValidationFailure>());
    expect((f as ValidationFailure).fields.keys, containsAll(['nombre_usuario', 'email', 'password']));
  });

  test('los términos son obligatorios (422)', () async {
    final r = await AuthRepositoryImpl(dio).register(const RegisterInput(
      accountType: AccountType.usuario, firstName: 'Ana', lastName: 'Gómez', username: 'anagomez', email: 'ana@x.com',
      password: 'clave-segura-1', country: 'Ecuador', city: 'Quito', acceptedTerms: false));
    expect(r.failureOrNull, isA<ValidationFailure>());
  });

  test('WebSocket con token inválido se cierra con 4401 → UnauthorizedFailure', () async {
    final wsBase = base.replaceFirst('http', 'ws');
    final rt = RealtimeRepositoryImpl(wsBaseUrl: wsBase, context: ctx, backoff: (_) => const Duration(milliseconds: 50));
    final completer = Completer<Object>();
    final sub = rt.queueEvents('00000000-0000-4000-8000-000000000000').listen((_) {}, onError: (Object e) {
      if (!completer.isCompleted) completer.complete(e);
    });
    final err = await completer.future.timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect(err, isA<UnauthorizedFailure>());
  });

  group('contrato OpenAPI', () {
    late Map<String, dynamic> spec;
    setUp(() async {
      final res = await Dio().get<Map<String, dynamic>>('$base/openapi.json');
      spec = res.data!;
    });

    Set<String> props(String schema) => ((spec['components']['schemas'][schema]['properties'] as Map).keys).cast<String>().toSet();

    test('todos los endpoints que usa el cliente existen con ese método', () {
      final paths = spec['paths'] as Map<String, dynamic>;
      const used = {
        '/auth/token': 'post', '/auth/registro': 'post',
        '/colas': 'get', '/colas/limite': 'get', '/colas/{cola_id}': 'get', '/colas/{cola_id}/horario': 'put',
        '/colas/{cola_id}/franjas': 'get', '/colas/{cola_id}/estado': 'get',
        '/turnos': 'post', '/turnos/mios': 'get', '/turnos/{turno_id}': 'get',
        '/turnos/{turno_id}/posponer': 'patch', '/turnos/{turno_id}/cancelar': 'patch', '/turnos/{turno_id}/atender': 'patch',
        '/turnos/{turno_id}/finalizar': 'patch', '/turnos/{turno_id}/no-show': 'patch',
        '/notificaciones': 'get', '/notificaciones/{notificacion_id}/leida': 'patch', '/notificaciones/{notificacion_id}': 'delete',
        '/listo': 'get',
      };
      for (final e in used.entries) {
        expect(paths.containsKey(e.key), isTrue, reason: 'falta ${e.key}');
        expect((paths[e.key] as Map).containsKey(e.value), isTrue, reason: '${e.key} no admite ${e.value}');
      }
      expect((paths['/colas/{cola_id}'] as Map).keys, containsAll(['get', 'patch', 'delete']));
      expect((paths['/colas'] as Map).keys, containsAll(['get', 'post']));
    });

    test('los campos que el cliente lee existen en las respuestas', () {
      expect(props('TurnoOut'), containsAll([
        'id', 'cola_id', 'propietario_nombre', 'usuario_id', 'franja_inicio', 'programado', 'numero', 'estado',
        'posicion', 'hora_creacion', 'hora_atencion', 'hora_finalizacion', 'agente_id',
      ]));
      expect(props('ColaOut'), containsAll(['id', 'propietario_nombre', 'nombre', 'descripcion', 'activa']));
      expect(props('HorarioOut'), containsAll([
        'cola_id', 'zona_horaria', 'hora_apertura', 'hora_cierre', 'duracion_franja_minutos', 'dias_atencion',
        'duracion_turno_minutos', 'puestos', 'capacidad_diaria', 'dias_anticipacion_maxima', 'franjas_por_dia', 'cupos_por_franja', 'turnos_por_dia',
      ]));
      expect(props('FranjaOut'), containsAll(['inicio', 'fin', 'cupos', 'ocupados', 'disponibles']));
      expect(props('ColaEstado'), containsAll(['cola_id', 'turnos_en_espera', 'turnos_atendiendo']));
      expect(props('ColasLimite'), containsAll(['propietario_tipo', 'limite', 'activas', 'disponibles']));
      expect(props('NotificacionOut'), containsAll(['id', 'usuario_id', 'turno_id', 'mensaje', 'leida', 'creada_en']));
      expect(props('TokenOut'), containsAll(['access_token', 'expires_in']));
      expect(props('RegistroOut'), containsAll(['propietario_tipo', 'propietario_id', 'nombre_usuario', 'email', 'nombre_empresa', 'limite_colas', 'creada_en']));
    });

    test('los campos que el cliente ENVÍA existen en las peticiones', () {
      expect(props('HorarioActualizar'), containsAll([
        'hora_apertura', 'hora_cierre', 'duracion_franja_minutos', 'dias_atencion', 'duracion_turno_minutos', 'puestos',
        'capacidad_diaria', 'dias_anticipacion_maxima', 'zona_horaria',
      ]));
      expect(props('TurnoCrear'), containsAll(['cola_id', 'franja_inicio']));
      expect(props('ColaCrear'), containsAll(['nombre', 'descripcion', 'hora_apertura', 'puestos', 'capacidad_diaria']));
      expect(props('ColaActualizar'), containsAll(['nombre', 'descripcion', 'activa']));
      expect(props('RegistroCrear'), containsAll([
        'tipo_cuenta', 'nombre_empresa', 'nombre', 'apellido', 'nombre_usuario', 'email', 'password', 'pais', 'ciudad', 'acepto_terminos',
      ]));
      expect(props('LoginCrear'), containsAll(['identificador', 'password']));
    });

    test('los estados del turno coinciden con el enum de la API', () {
      final values = ((spec['components']['schemas']['TurnoEstado']['enum']) as List).cast<String>().toSet();
      expect(TicketStatus.values.map((s) => s.wire).toSet(), values);
    });
  });
}
