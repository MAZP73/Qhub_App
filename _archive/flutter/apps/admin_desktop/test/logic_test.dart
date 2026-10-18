import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/app/env.dart';
import 'package:qhub_admin/app/router.dart';
import 'package:qhub_admin/features/auth/presentation/login_page.dart';
import 'package:qhub_admin/features/history/domain/history.dart';
import 'package:qhub_admin/features/queues/domain/schedule_form.dart';
import 'package:qhub_admin/features/staff/domain/staff.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import 'support/fakes.dart';

String? redirect({
  String location = '/',
  bool authLoading = false,
  bool signedIn = true,
  bool membershipsLoading = false,
  bool hasOrganization = true,
  bool isAdmin = true,
  bool connected = true,
}) =>
    resolveRedirect(
      location: location, authLoading: authLoading, signedIn: signedIn, membershipsLoading: membershipsLoading,
      hasOrganization: hasOrganization, isAdmin: isAdmin, connected: connected,
    );

void main() {
  group('AppEnv', () {
    test('lee los valores y aplica default de APP_ENV', () {
      expect(testEnv.appEnv, 'development');
      expect(testEnv.isProduction, isFalse);
      expect(testEnv.supabaseKey, 'sb_publishable_test');
    });
    test('falla con mensaje claro si falta una variable', () {
      expect(() => AppEnv.fromMap({'QHUB_API_BASE_URL': 'x'}), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('QHUB_WS_BASE_URL'))));
    });
  });

  group('resolveRedirect', () {
    test('cargando → /cargando', () {
      expect(redirect(authLoading: true), '/cargando');
      expect(redirect(authLoading: true, location: '/cargando'), isNull);
    });
    test('sin sesión → /login', () {
      expect(redirect(signedIn: false, location: '/colas'), '/login');
      expect(redirect(signedIn: false, location: '/login'), isNull);
    });
    test('sin organización → /setup', () => expect(redirect(hasOrganization: false), '/setup'));
    test('sin conexión Qhub → /connect', () => expect(redirect(connected: false, location: '/colas'), '/connect'));
    test('todo listo en páginas de acceso → /colas', () {
      for (final p in ['/login', '/setup', '/connect', '/cargando', '/']) {
        expect(redirect(location: p), '/colas', reason: p);
      }
    });
    test('agente no entra a equipo, ajustes ni edición de colas', () {
      for (final p in ['/equipo', '/ajustes', '/colas/nueva', '/colas/abc']) {
        expect(redirect(location: p, isAdmin: false), '/colas', reason: p);
        expect(redirect(location: p), isNull, reason: 'admin $p');
      }
      expect(redirect(location: '/en-vivo', isAdmin: false), isNull);
      expect(redirect(location: '/colas', isAdmin: false), isNull);
    });
  });

  group('validaciones de acceso', () {
    test('correo', () {
      expect(validateEmail('ana@x.co'), isNull);
      expect(validateEmail('ana@'), isNotNull);
      expect(validateEmail(''), isNotNull);
    });
    test('contraseña', () {
      expect(validatePassword('12345678'), isNull);
      expect(validatePassword('1234567'), isNotNull);
    });
  });

  group('staff', () {
    test('slugify', () {
      expect(slugify('Notaría 12 · Sede Norte'), 'notaria-12-sede-norte');
      expect(slugify('  ¡¡¡  '), 'organizacion');
      expect(slugify('Ñandú'), 'nandu');
    });
    test('iniciales', () {
      expect(const StaffUser(id: '1', email: 'a@b.c', displayName: 'Ana Gómez').initials, 'AG');
      expect(const StaffUser(id: '1', email: 'luis@b.c').initials, 'LB');
    });
    test('rol → ActorRole', () {
      expect(OrgRole.admin.actorRole, ActorRole.admin);
      expect(OrgRole.parse('agente').actorRole, ActorRole.agente);
    });
  });

  group('horario', () {
    test('hora válida y normalización', () {
      expect(isValidHm('8:00'), isTrue);
      expect(isValidHm('24:00'), isFalse);
      expect(isValidHm('08:60'), isFalse);
      expect(normalizeHm('8:05'), '08:05');
    });
    test('resumen', () {
      final s = summarize(const ScheduleInput(opens: '08:00', closes: '17:00', slotMinutes: 30, days: [1, 2, 3, 4, 5], turnMinutes: 10, stations: 2, maxDaysAhead: 7));
      expect(s.slotsPerDay, 18);
      expect(s.capacityPerSlot, 6);
      expect(s.turnsPerDay, 108);
      expect(s.turnsPerWeek, 540);
    });
    test('el tope diario recorta', () {
      final s = summarize(const ScheduleInput(opens: '08:00', closes: '17:00', slotMinutes: 30, days: [1], turnMinutes: 10, dailyCapacity: 50, maxDaysAhead: 7));
      expect(s.turnsPerDay, 50);
    });
  });

  group('historial', () {
    final t0 = DateTime.utc(2026, 10, 20, 9);
    final tickets = [
      makeTicket('a', 1, TicketStatus.finalizado, created: t0, called: t0.add(const Duration(minutes: 6)), finished: t0.add(const Duration(minutes: 10))),
      makeTicket('b', 2, TicketStatus.finalizado, created: t0, called: t0.add(const Duration(minutes: 8)), finished: t0.add(const Duration(minutes: 14))),
      makeTicket('c', 3, TicketStatus.noShow, created: t0),
      makeTicket('d', 4, TicketStatus.cancelado, created: t0),
      makeTicket('e', 5, TicketStatus.enEspera, created: t0),
    ];

    test('estadísticas', () {
      final s = computeStats(tickets);
      expect(s.total, 5);
      expect(s.attended, 2);
      expect(s.noShow, 1);
      expect(s.cancelled, 1);
      expect(s.waiting, 1);
      expect(s.avgWait, const Duration(minutes: 7));
      expect(s.avgService, const Duration(minutes: 5));
      expect(s.noShowRate, closeTo(1 / 3, 1e-9));
    });
    test('sin datos', () {
      final s = computeStats(const []);
      expect(s.avgWait, isNull);
      expect(s.noShowRate, 0);
      expect(formatDuration(null), '—');
    });
    test('formatos', () {
      expect(formatDuration(const Duration(minutes: 7, seconds: 12)), '7:12');
      expect(formatPercent(0.042), '4,2 %');
    });
    test('espera de un turno reservado se mide desde su franja', () {
      final slot = DateTime.utc(2026, 10, 20, 15);
      final t = makeTicket('s', 9, TicketStatus.finalizado, scheduled: true, slot: slot, created: DateTime.utc(2026, 10, 18), called: slot.add(const Duration(minutes: 3)), finished: slot.add(const Duration(minutes: 8)));
      expect(computeStats([t]).avgWait, const Duration(minutes: 3));
    });
    test('CSV con escape y prefijo', () {
      final csv = ticketsToCsv([makeTicket('a', 7, TicketStatus.noShow, created: t0)], queueNames: {'q1': 'Caja, "1"'}, prefixes: {'q1': 'C'});
      final lines = csv.trim().split('\n');
      expect(lines.first, startsWith('turno,cola'));
      expect(lines[1], startsWith('C-007,"Caja, ""1""",cli-7'));
      expect(lines[1], contains('no_show'));
    });
    test('loadHistory pagina y recorre los días', () async {
      final many = [for (var i = 0; i < 1500; i++) makeTicket('t$i', i, TicketStatus.finalizado)];
      final repo = FakeTicketRepository(many);
      final res = await loadHistory(repo, days: 2, today: DateTime(2026, 10, 20));
      expect(res.valueOrNull!.length, 3000); // 2 días × 1500
      expect(repo.filters.length, 4); // 2 páginas por día
      expect(repo.filters.first.date, DateTime(2026, 10, 20));
      expect(repo.filters[2].date, DateTime(2026, 10, 19));
    });
    test('loadHistory propaga el error', () async {
      final repo = _FailingTickets();
      final res = await loadHistory(repo, days: 1, today: DateTime(2026, 10, 20));
      expect(res.failureOrNull, isA<NetworkFailure>());
    });
  });
}

class _FailingTickets extends FakeTicketRepository {
  _FailingTickets() : super(const []);
  @override
  Future<Result<List<Ticket>>> list(TicketFilter filter) async => const Result.err(NetworkFailure());
}
