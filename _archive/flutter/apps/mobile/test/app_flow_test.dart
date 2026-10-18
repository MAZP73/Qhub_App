import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import 'package:qhub_mobile/features/auth/domain/user.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

const camila = AppUser(id: 'u1', email: 'camila@x.co', displayName: 'Camila Ríos');

void main() {
  group('acceso', () {
    testWidgets('sin sesión muestra el acceso y valida', (t) async {
      final env = Env();
      await pumpApp(t, env);
      expect(find.text('Tu turno, sin filas.'), findsOneWidget);
      await t.tap(find.text('Continuar'));
      await settle(t);
      expect(find.text('Escribe un correo válido.'), findsOneWidget);
      expect(env.user.calls, isEmpty);
    });

    testWidgets('error de credenciales', (t) async {
      final env = Env(user: FakeUserRepository()..signInFailure = const UnauthorizedFailure('Correo o contraseña incorrectos.'));
      await pumpApp(t, env);
      await t.enterText(find.byType(TextField).at(0), 'camila@x.co');
      await t.enterText(find.byType(TextField).at(1), 'secreto123');
      await t.tap(find.text('Continuar'));
      await settle(t);
      expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    });

    testWidgets('iniciar sesión lleva a "Mi turno" vacío', (t) async {
      final env = Env();
      await pumpApp(t, env);
      await t.enterText(find.byType(TextField).at(0), 'camila@x.co');
      await t.enterText(find.byType(TextField).at(1), 'secreto123');
      await t.tap(find.text('Continuar'));
      await settle(t);
      expect(find.text('No tienes turnos activos'), findsOneWidget);
      expect(find.text('Explorar'), findsWidgets);
    });

    testWidgets('crear cuenta avisa que hay que confirmar el correo', (t) async {
      final env = Env();
      await pumpApp(t, env);
      await t.tap(find.text('Crear cuenta'));
      await settle(t);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), 'Camila');
      await t.enterText(fields.at(1), 'Ríos');
      await t.enterText(fields.at(2), 'camila@x.co');
      await t.enterText(fields.at(3), 'secreto123');
      await t.tap(find.text('Crear cuenta').last);
      await settle(t);
      expect(env.user.calls, ['signUp:camila@x.co']);
      expect(find.textContaining('confirmar tu cuenta'), findsOneWidget);
    });
  });

  group('con sesión', () {
    Env signedIn({FakeHistoryRepository? history, FakeGateway? gateway, FakeOrganizationRepository? orgs}) =>
        Env(user: FakeUserRepository(user: camila), history: history, gateway: gateway, orgs: orgs);

    testWidgets('explorar lista organizaciones y busca', (t) async {
      final env = signedIn();
      await pumpApp(t, env);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      expect(find.text('Notaría 12'), findsOneWidget);
      expect(find.text('Banco Cooperativo'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'banco');
      await t.pump(const Duration(milliseconds: 500));
      await settle(t);
      expect(find.text('Banco Cooperativo'), findsOneWidget);
      expect(find.text('Notaría 12'), findsNothing);
      expect(env.orgs.searches, containsAllInOrder(['', 'banco']));
    });

    testWidgets('sin resultados y error de red con reintento', (t) async {
      final env = signedIn(orgs: FakeOrganizationRepository(orgs: const []));
      await pumpApp(t, env);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      expect(find.text('Aún no hay organizaciones'), findsOneWidget);

      final failing = signedIn(orgs: FakeOrganizationRepository()..searchFailure = const NetworkFailure());
      await pumpApp(t, failing);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      expect(find.text('No pudimos cargar esto'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('sacar un turno ahora: organización → cola → turno → Mi turno', (t) async {
      final gw = FakeGateway();
      final env = signedIn(gateway: gw);
      await pumpApp(t, env);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      await t.tap(find.text('Notaría 12'));
      await settle(t);
      expect(find.text('Colas abiertas'), findsOneWidget);
      expect(find.text('Escrituras'), findsOneWidget);
      expect(find.text('Archivo'), findsNothing); // las archivadas no se ofrecen
      expect(find.text('5 en espera · 1 atendiendo'), findsOneWidget);

      await t.tap(find.text('Escrituras'));
      await settle(t);
      expect(find.text('Sacar turno ahora'), findsOneWidget);
      await t.tap(find.text('Sacar turno ahora'));
      await settle(t);

      expect(gw.ticketRepo.created.single.queue, 'q1');
      expect(gw.ticketRepo.created.single.slot, isNull); // en vivo: sin franja
      expect(find.textContaining('E-023'), findsWidgets); // prefijo del Supabase
    });

    testWidgets('reservar una franja: llena deshabilitada, la elegida viaja en UTC', (t) async {
      final gw = FakeGateway();
      final env = signedIn(gateway: gw);
      await pumpApp(t, env);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      await t.tap(find.text('Notaría 12'));
      await settle(t);
      await t.tap(find.text('Escrituras'));
      await settle(t);

      await t.tap(find.text('Reservar franja'));
      await settle(t);
      expect(find.text('Elige día y franja'), findsOneWidget);

      await t.tap(find.text('${DateTime.now().day}').first);
      await settle(t);
      expect(find.text('Llena'), findsOneWidget);
      expect(find.text('2 cupos'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget); // 13:30Z en la zona de la cola (UTC-5), no la del dispositivo

      await t.tap(find.text('2 cupos'));
      await settle(t);
      expect(find.textContaining('Reservar'), findsWidgets);
      await t.tap(find.textContaining(RegExp(r'^Reservar \S+ \d+, 08:30')));
      await settle(t);

      final slot = gw.ticketRepo.created.single.slot!;
      expect(slot.isUtc, isTrue);
      expect(slot.hour, 13);
      expect(slot.minute, 30);
    });

    testWidgets('franja llena (409) se explica y se puede reintentar', (t) async {
      final gw = FakeGateway(tickets: FakeTickets()..createFailure = const ConflictFailure('Esa franja ya no tiene cupos. Elige otra.'));
      final env = signedIn(gateway: gw);
      await pumpApp(t, env);
      await t.tap(find.text('Explorar').last);
      await settle(t);
      await t.tap(find.text('Notaría 12'));
      await settle(t);
      await t.tap(find.text('Escrituras'));
      await settle(t);
      await t.tap(find.text('Sacar turno ahora'));
      await settle(t);
      expect(find.text('Esa franja ya no tiene cupos. Elige otra.'), findsOneWidget);
      expect(find.text('Sacar turno ahora'), findsWidgets); // sigue en la pantalla
    });

    testWidgets('Mi turno muestra posición, estimado y permite cancelar con confirmación', (t) async {
      final gw = FakeGateway();
      gw.ticketRepo.stored['t1'] = ticket('t1', 7, TicketStatus.enEspera, pos: 4);
      final env = signedIn(gateway: gw, history: FakeHistoryRepository([entry('t1', 7, TicketStatus.enEspera)]));
      await pumpApp(t, env);

      expect(find.text('E-007'), findsOneWidget);
      expect(find.text('Personas delante'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('~20 min'), findsOneWidget);
      expect(find.text('En espera'), findsOneWidget);

      await t.ensureVisible(find.text('Cancelar'));
      await t.tap(find.text('Cancelar'));
      await settle(t);
      expect(find.text('Cancelar turno'), findsNWidgets(2)); // título + botón del diálogo
      await t.tap(find.text('Volver'));
      await settle(t);
      expect(gw.ticketRepo.calls, isEmpty);

      await t.tap(find.text('Cancelar'));
      await settle(t);
      await t.tap(find.text('Cancelar turno').last);
      await settle(t);
      expect(gw.ticketRepo.calls, ['cancel:t1']);
    });

    testWidgets('cuando lo atienden se avisa "Es tu turno"', (t) async {
      final gw = FakeGateway();
      gw.ticketRepo.stored['t1'] = ticket('t1', 7, TicketStatus.atendiendo, pos: 0);
      final env = signedIn(gateway: gw, history: FakeHistoryRepository([entry('t1', 7, TicketStatus.enEspera)]));
      await pumpApp(t, env);
      expect(find.text('Es tu turno'), findsOneWidget);
      expect(find.text('Atendiendo'), findsOneWidget);
    });

    testWidgets('avisos: sin leer, marcar como leído', (t) async {
      final notes = FakeNotifications([
        AppNotification(id: 'n1', userId: 'u1', message: 'Tu turno E-007 está siendo atendido', read: false, createdAt: DateTime.now(), kind: 'turno_llamado'),
        AppNotification(id: 'n2', userId: 'u1', message: 'Recordatorio: tu turno empieza en 45 minutos', read: true, createdAt: DateTime.now().subtract(const Duration(hours: 1)), kind: 'recordatorio'),
      ]);
      final gw = FakeGateway(notifications: notes);
      final env = signedIn(gateway: gw, history: FakeHistoryRepository([entry('t1', 7, TicketStatus.finalizado)]));
      await pumpApp(t, env);
      await t.tap(find.text('Avisos').last);
      await settle(t);
      expect(find.text('Sin leer (1)'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);

      await t.tap(find.text('Sin leer (1)'));
      await settle(t);
      expect(find.text('Tu turno E-007 está siendo atendido'), findsOneWidget);
      expect(find.textContaining('Recordatorio'), findsNothing);

      await t.tap(find.text('Tu turno E-007 está siendo atendido'));
      await settle(t);
      expect(notes.read, ['n1']);
      expect(find.text('Estás al día'), findsOneWidget);
    });

    testWidgets('historial agrupa por día y muestra el estado con palabra', (t) async {
      final env = signedIn(history: FakeHistoryRepository([
        entry('a', 5, TicketStatus.finalizado),
        entry('b', 4, TicketStatus.noShow, at: DateTime.now().subtract(const Duration(days: 1))),
      ]));
      await pumpApp(t, env);
      await t.tap(find.text('Historial').last);
      await settle(t);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Finalizado'), findsOneWidget);
      expect(find.text('No-show'), findsOneWidget);
    });

    testWidgets('cerrar sesión desde el perfil vuelve al acceso', (t) async {
      final env = signedIn();
      await pumpApp(t, env);
      await t.tap(find.byTooltip('Perfil'));
      await settle(t);
      expect(find.text('camila@x.co'), findsOneWidget);
      await t.tap(find.text('Cerrar sesión').first);
      await settle(t);
      await t.tap(find.text('Cerrar sesión').last);
      await settle(t);
      expect(env.user.calls, ['signOut']);
      expect(find.text('Tu turno, sin filas.'), findsOneWidget);
    });
  });
}
