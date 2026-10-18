import 'package:dio/dio.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:test/test.dart';

import 'fake_adapter.dart';
import 'fixtures.dart';

void main() {
  late FakeAdapter adapter;
  late ApiContext context;
  late Dio dio;
  var unauthorizedCalls = 0;

  setUp(() {
    adapter = FakeAdapter();
    unauthorizedCalls = 0;
    context = ApiContext(
      token: 'tok',
      actor: const Actor(userId: 'admin-1', role: ActorRole.admin),
      onUnauthorized: () => unauthorizedCalls++,
    );
    dio = createQhubDio(baseUrl: 'http://api.test', context: context, adapter: adapter);
  });

  group('auth', () {
    test('login devuelve el token y no manda headers de identidad', () async {
      adapter.on('POST /auth/token', {'access_token': 'abc', 'token_type': 'bearer', 'expires_in': 3600});
      final repo = AuthRepositoryImpl(dio, now: () => DateTime.utc(2026, 1, 1));
      final r = await repo.login(identifier: 'ana', password: 'x');
      expect(r.valueOrNull?.accessToken, 'abc');
      expect(r.valueOrNull?.expiresAt, DateTime.utc(2026, 1, 1, 1));
      final req = adapter.requests.single;
      expect(req.body, {'identificador': 'ana', 'password': 'x'});
      expect(req.headers.containsKey('Authorization'), isFalse);
    });

    test('login inválido no dispara onUnauthorized (es un endpoint público)', () async {
      adapter.on('POST /auth/token', {'detail': 'Credenciales inválidas'}, status: 401);
      final r = await AuthRepositoryImpl(dio).login(identifier: 'a', password: 'b');
      expect(r.failureOrNull, isA<UnauthorizedFailure>());
      expect(r.failureOrNull!.message, 'Credenciales inválidas');
      expect(unauthorizedCalls, 0);
    });

    test('registro serializa al contrato de la API', () async {
      adapter.on('POST /auth/registro', {
        'propietario_tipo': 'empresa', 'propietario_id': 'o1', 'nombre_usuario': 'ana',
        'email': 'a@b.c', 'nombre_empresa': 'Clínica', 'limite_colas': 6, 'creada_en': '2026-10-17T10:00:00Z',
      }, status: 201);
      final r = await AuthRepositoryImpl(dio).register(const RegisterInput(
        accountType: AccountType.empresa, companyName: 'Clínica', firstName: 'Ana', lastName: 'Gómez',
        username: 'ana', email: 'a@b.c', password: '12345678', country: 'Ecuador', city: 'Quito', acceptedTerms: true));
      expect(r.valueOrNull?.queueLimit, 6);
      final body = adapter.requests.single.body as Map;
      expect(body['tipo_cuenta'], 'empresa');
      expect(body['acepto_terminos'], true);
      expect(body['nombre_empresa'], 'Clínica');
    });
  });

  group('errores', () {
    final cases = <int, Type>{
      400: BadRequestFailure, 401: UnauthorizedFailure, 403: ForbiddenFailure, 404: NotFoundFailure,
      409: ConflictFailure, 422: ValidationFailure, 429: RateLimitedFailure, 500: ServerFailure, 503: ServerFailure,
    };
    cases.forEach((status, type) {
      test('HTTP $status → $type', () async {
        adapter.on('GET /colas', {'detail': 'x'}, status: status);
        final r = await QueueRepositoryImpl(dio).list();
        expect(r.failureOrNull.runtimeType, type);
      });
    });

    test('401 en endpoint de negocio avisa a la app (no hay refresh)', () async {
      adapter.on('GET /colas', {'detail': 'vencido'}, status: 401);
      await QueueRepositoryImpl(dio).list();
      expect(unauthorizedCalls, 1);
    });

    test('422 de FastAPI se vuelve mensajes por campo', () async {
      adapter.on('POST /colas', {
        'detail': [{'loc': ['body', 'nombre'], 'msg': 'String should have at least 1 character'}]
      }, status: 422);
      final r = await QueueRepositoryImpl(dio).create(const CreateQueueInput(name: 'x'));
      final f = r.failureOrNull as ValidationFailure;
      expect(f.fields['nombre'], contains('at least 1'));
    });

    test('sin conexión → NetworkFailure', () async {
      final bad = createQhubDio(baseUrl: 'http://127.0.0.1:1', context: context);
      final r = await QueueRepositoryImpl(bad).list();
      expect(r.failureOrNull, isA<NetworkFailure>());
    });
  });

  group('colas', () {
    test('envía Bearer y headers de identidad en endpoints de negocio', () async {
      adapter.on('GET /colas', [queueJson()]);
      final r = await QueueRepositoryImpl(dio).list(active: true);
      expect(r.valueOrNull!.single.name, 'Caja 1');
      final req = adapter.requests.single;
      expect(req.headers['Authorization'], 'Bearer tok');
      expect(req.headers['X-Usuario-Id'], 'admin-1');
      expect(req.headers['X-Usuario-Rol'], 'admin');
      expect(req.query['activa'], true);
    });

    test('horario: parsea derivados y serializa PUT con segundos', () async {
      adapter.on('PUT /colas/q1/horario', scheduleJson());
      final r = await QueueRepositoryImpl(dio).replaceSchedule(
          'q1',
          const ScheduleInput(
              opens: '08:00', closes: '18:00', slotMinutes: 30, days: [1, 2, 3], turnMinutes: 10, stations: 2, maxDaysAhead: 7));
      expect(r.valueOrNull!.capacityPerSlot, 6);
      final body = adapter.requests.single.body as Map;
      expect(body['hora_apertura'], '08:00:00');
      expect(body['puestos'], 2);
    });

    test('franjas: fecha en YYYY-MM-DD', () async {
      adapter.on('GET /colas/q1/franjas', [
        {'inicio': '2026-10-20T15:00:00Z', 'fin': '2026-10-20T15:30:00Z', 'cupos': 6, 'ocupados': 5, 'disponibles': 1}
      ]);
      final r = await QueueRepositoryImpl(dio).slots('q1', date: DateTime(2026, 10, 20));
      expect(adapter.requests.single.query['fecha'], '2026-10-20');
      expect(r.valueOrNull!.single.isLow, isTrue);
    });

    test('delete usa 204 sin cuerpo', () async {
      adapter.on('DELETE /colas/q1', null, status: 204);
      expect((await QueueRepositoryImpl(dio).delete('q1')).isOk, isTrue);
    });

    test('límite y estado', () async {
      adapter.on('GET /colas/limite', {'propietario_tipo': 'empresa', 'limite': 6, 'activas': 2, 'disponibles': 4});
      adapter.on('GET /colas/q1/estado', {'cola_id': 'q1', 'turnos_en_espera': 3, 'turnos_atendiendo': 1});
      final repo = QueueRepositoryImpl(dio);
      expect((await repo.limit()).valueOrNull!.available, 4);
      expect((await repo.state('q1')).valueOrNull!.waiting, 3);
    });
  });

  group('turnos', () {
    test('en vivo: sin franja_inicio', () async {
      adapter.on('POST /turnos', ticketJson(), status: 201);
      final r = await TicketRepositoryImpl(dio).create('q1');
      expect(r.valueOrNull!.number, 5);
      expect((adapter.requests.single.body as Map).containsKey('franja_inicio'), isFalse);
    });

    test('programado: franja_inicio en UTC', () async {
      adapter.on('POST /turnos', ticketJson(programado: true), status: 201);
      await TicketRepositoryImpl(dio).create('q1', slotStart: DateTime.utc(2026, 11, 3, 15));
      expect((adapter.requests.single.body as Map)['franja_inicio'], '2026-11-03T15:00:00.000Z');
    });

    test('franja llena → ConflictFailure con el mensaje de la API', () async {
      adapter.on('POST /turnos', {'detail': 'La franja está llena'}, status: 409);
      final r = await TicketRepositoryImpl(dio).create('q1', slotStart: DateTime.utc(2026, 11, 3, 15));
      expect(r.failureOrNull, isA<ConflictFailure>());
      expect(r.failureOrNull!.message, 'La franja está llena');
    });

    test('ciclo de atención', () async {
      adapter.on('PATCH /turnos/t1/atender', ticketJson(estado: 'atendiendo'));
      adapter.on('PATCH /turnos/t1/finalizar', ticketJson(estado: 'finalizado'));
      adapter.on('PATCH /turnos/t1/no-show', ticketJson(estado: 'no_show'));
      final repo = TicketRepositoryImpl(dio);
      expect((await repo.call('t1')).valueOrNull!.status, TicketStatus.atendiendo);
      expect((await repo.finish('t1')).valueOrNull!.status, TicketStatus.finalizado);
      expect((await repo.noShow('t1')).valueOrNull!.status, TicketStatus.noShow);
    });

    test('listado: filtros y paginación', () async {
      adapter.on('GET /turnos', [ticketJson()]);
      await TicketRepositoryImpl(dio).list(TicketFilter(
          queueId: 'q1', status: TicketStatus.noShow, date: DateTime(2026, 10, 1), limit: 50, offset: 100));
      final q = adapter.requests.single.query;
      expect(q['cola_id'], 'q1');
      expect(q['estado'], 'no_show');
      expect(q['fecha'], '2026-10-01');
      expect(q['limite'], 50);
      expect(q['desde'], 100);
    });
  });

  group('notificaciones y salud', () {
    test('lista y marca leída', () async {
      adapter.on('GET /notificaciones', [
        {'id': 'n1', 'propietario_tipo': 'empresa', 'propietario_id': 'o1', 'usuario_id': 'cli-1',
         'turno_id': 't1', 'mensaje': 'Tu turno #4 está siendo atendido', 'leida': false, 'creada_en': '2026-10-20T15:01:00Z'}
      ]);
      adapter.on('PATCH /notificaciones/n1/leida', {
        'id': 'n1', 'propietario_tipo': 'empresa', 'propietario_id': 'o1', 'usuario_id': 'cli-1',
        'turno_id': 't1', 'mensaje': 'm', 'leida': true, 'creada_en': '2026-10-20T15:01:00Z'});
      final repo = NotificationRepositoryImpl(dio);
      expect((await repo.list()).valueOrNull!.single.read, isFalse);
      expect((await repo.markRead('n1')).valueOrNull!.read, isTrue);
    });

    test('/listo acepta 503 como respuesta válida', () async {
      adapter.on('GET /listo', {'supabase': 'error', 'rabbitmq': 'ok'}, status: 503);
      final r = await HealthRepositoryImpl(dio).ready();
      expect(r.valueOrNull!.isReady, isFalse);
    });
  });
}
