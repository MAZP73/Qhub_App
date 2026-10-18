import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:qhub_mobile/app/env.dart';
import 'package:qhub_mobile/app/router.dart';
import 'package:qhub_mobile/features/auth/presentation/auth_page.dart';
import 'package:qhub_mobile/features/gateway/data/proxy_adapter.dart';
import 'package:qhub_mobile/features/history/domain/history.dart';
import 'package:qhub_mobile/features/organizations/domain/organizations.dart';
import 'package:qhub_mobile/features/tickets/domain/active_tickets.dart';

import 'support/fakes.dart';

void main() {
  group('AppEnv', () {
    test('lee valores y exige los obligatorios', () {
      expect(testEnv.supabaseKey, 'sb_publishable_test');
      expect(() => AppEnv.fromMap({'SUPABASE_URL': 'x'}), throwsA(isA<StateError>().having((e) => e.message, 'm', contains('SUPABASE_PUBLISHABLE_KEY'))));
    });
    test('el .env del móvil no pide ninguna credencial de la API Qhub', () {
      final keys = AppEnv.fromMap({'SUPABASE_URL': 'x', 'SUPABASE_PUBLISHABLE_KEY': 'y'}).toString();
      expect(keys.toLowerCase(), isNot(contains('api_key')));
    });
  });

  group('resolveRedirect', () {
    test('cargando, sin sesión, con sesión', () {
      expect(resolveRedirect(location: '/turno', authLoading: true, signedIn: false), '/cargando');
      expect(resolveRedirect(location: '/turno', authLoading: false, signedIn: false), '/acceso');
      expect(resolveRedirect(location: '/acceso', authLoading: false, signedIn: false), isNull);
      expect(resolveRedirect(location: '/acceso', authLoading: false, signedIn: true), '/turno');
      expect(resolveRedirect(location: '/explorar', authLoading: false, signedIn: true), isNull);
    });
  });

  test('validaciones de acceso', () {
    expect(validateEmail('a@b.co'), isNull);
    expect(validateEmail('a@b'), isNotNull);
    expect(validatePassword('1234567'), isNotNull);
    expect(validatePassword('12345678'), isNull);
  });

  group('OrganizationSummary', () {
    test('marca con iniciales', () {
      expect(notaria.mark, 'N1'); // "Notaría" + "12"
      expect(banco.mark, 'BC');
      expect(const OrganizationSummary(id: '1', name: 'Registraduría', slug: 'r').mark, 'REG');
    });
    test('ubicación', () {
      expect(notaria.location, 'Cra. 13 #54-21 · Bogotá');
      expect(banco.location, 'Quito');
    });
  });

  group('historial', () {
    test('agrupa por día, más reciente primero', () {
      final now = DateTime(2026, 10, 20, 12);
      final g = groupByDay([
        entry('a', 1, TicketStatus.finalizado, at: DateTime(2026, 10, 19, 9)),
        entry('b', 2, TicketStatus.enEspera, at: now),
        entry('c', 3, TicketStatus.cancelado, at: DateTime(2026, 10, 20, 8)),
      ]);
      expect(g.keys.first, DateTime(2026, 10, 20));
      expect(g.values.first.map((e) => e.ticketId), ['b', 'c']);
      expect(dayLabel(DateTime(2026, 10, 20), now), 'Hoy');
      expect(dayLabel(DateTime(2026, 10, 19), now), 'Ayer');
      expect(dayLabel(DateTime(2026, 10, 3), now), '3 oct');
    });
  });

  group('LoadActiveTickets', () {
    late FakeGateway gw;
    late FakeHistoryRepository hist;
    LoadActiveTickets build() => LoadActiveTickets(history: hist, gateway: gw, organizations: FakeOrganizationRepository());

    setUp(() {
      gw = FakeGateway();
      hist = FakeHistoryRepository([
        entry('t1', 7, TicketStatus.enEspera),
        entry('t2', 8, TicketStatus.finalizado), // no es activo: ni se consulta
        entry('t3', 9, TicketStatus.enEspera), // la API ya lo cerró
        entry('t4', 10, TicketStatus.enEspera), // desapareció (404)
      ]);
      gw.ticketRepo.stored['t1'] = ticket('t1', 7, TicketStatus.enEspera, pos: 4);
      gw.ticketRepo.stored['t3'] = ticket('t3', 9, TicketStatus.noShow);
    });

    test('solo devuelve los vigentes, refrescados, con espera estimada', () async {
      final res = await build()();
      final list = res.valueOrNull!;
      expect(list.length, 1);
      final t = list.single;
      expect(t.label, 'E-007'); // prefijo del Supabase
      expect(t.peopleAhead, 3);
      expect(t.estimateMinutes, 20); // ceil(3/2) × 10 min
    });

    test('si la API falla en todo, propaga el error; con 404 no', () async {
      gw.ticketRepo.getFailure = const NetworkFailure();
      expect((await build()()).failureOrNull, isA<NetworkFailure>());
    });

    test('sin turnos activos → lista vacía sin llamar a la API', () async {
      hist.entries = [entry('x', 1, TicketStatus.finalizado)];
      expect((await build()()).valueOrNull, isEmpty);
    });

    test('aheadOf: 0 cuando ya lo atienden', () {
      expect(aheadOf(ticket('a', 1, TicketStatus.atendiendo, pos: 0)), 0);
      expect(aheadOf(ticket('a', 1, TicketStatus.enEspera, pos: 1)), 0);
      expect(aheadOf(ticket('a', 1, TicketStatus.enEspera, pos: 5)), 4);
    });
  });

  group('proxy (la app nunca ve la credencial de la API)', () {
    late List<(String, ProxyRequest)> sent;
    late ProxyResult Function(ProxyRequest) respond;
    late ProxyQhubGateway gateway;

    setUp(() {
      sent = [];
      respond = (_) => const ProxyResult(200, []);
      gateway = ProxyQhubGateway((org, req) async {
        sent.add((org, req));
        return respond(req);
      });
    });

    test('traduce las llamadas del cliente a sobres para la función', () async {
      respond = (_) => ProxyResult(201, {
            'id': 't1', 'cola_id': 'q1', 'propietario_nombre': 'N12', 'usuario_id': 'u1', 'franja_inicio': '2026-10-20T15:00:00Z',
            'programado': true, 'numero': 5, 'estado': 'en_espera', 'posicion': 1, 'hora_creacion': '2026-10-20T14:00:00Z',
          });
      final res = await gateway.tickets('org1').create('q1', slotStart: DateTime.utc(2026, 10, 20, 15));
      expect(res.valueOrNull!.number, 5);
      final (org, req) = sent.single;
      expect(org, 'org1');
      expect(req.method, 'POST');
      expect(req.path, '/turnos');
      expect(req.body, {'cola_id': 'q1', 'franja_inicio': '2026-10-20T15:00:00.000Z'});
      final json = req.toJson(org);
      expect(json['organizacion_id'], 'org1');
      expect(jsonEncode(json), isNot(contains('Authorization'))); // ningún header de identidad sale del móvil
    });

    test('el estado del sobre se vuelve el mismo Failure que con la API directa', () async {
      respond = (_) => const ProxyResult(409, {'detail': 'La franja está llena'});
      final res = await gateway.tickets('org1').create('q1');
      expect(res.failureOrNull, isA<ConflictFailure>());
      expect(res.failureOrNull!.message, 'La franja está llena');
    });

    test('query de franjas y listas', () async {
      respond = (r) => r.path.endsWith('/franjas')
          ? const ProxyResult(200, [{'inicio': '2026-10-20T13:00:00Z', 'fin': '2026-10-20T13:30:00Z', 'cupos': 6, 'ocupados': 1, 'disponibles': 5}])
          : const ProxyResult(200, []);
      final slots = await gateway.queues('org1').slots('q1', date: DateTime(2026, 10, 20));
      expect(slots.valueOrNull!.single.available, 5);
      expect(sent.single.$2.query['fecha'], '2026-10-20');
    });

    test('un fallo del invocador (sin red) es NetworkFailure', () async {
      final bad = ProxyQhubGateway((_, _) async => throw const NetworkFailure());
      final res = await bad.queues('org1').list();
      expect(res.failureOrNull, isA<NetworkFailure>());
    });

    test('cada organización tiene su propio canal', () async {
      await gateway.queues('orgA').list();
      await gateway.queues('orgB').list();
      expect(sent.map((e) => e.$1), ['orgA', 'orgB']);
    });
  });
}
