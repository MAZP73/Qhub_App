import 'package:flutter_test/flutter_test.dart';
import 'package:qhub_admin/features/live/presentation/live_page.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  Env build({List<Ticket>? tickets}) => Env(
        staff: FakeStaffRepository(user: ana, memberships: const [adminMembership])..prefixes['q1'] = 'C',
        tickets: FakeTicketRepository(tickets ??
            [
              makeTicket('t1', 1, TicketStatus.atendiendo, pos: 0),
              makeTicket('t2', 2, TicketStatus.enEspera, pos: 1),
              makeTicket('t3', 3, TicketStatus.enEspera, pos: 2),
              makeTicket('t0', 9, TicketStatus.finalizado),
            ]),
      );

  testWidgets('muestra lo que se atiende, la fila y los contadores', (t) async {
    useDesktopSize(t);
    final env = build();
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);
    expect(find.text('Atendiendo ahora'), findsOneWidget);
    expect(find.text('C-001'), findsOneWidget);
    expect(find.text('Llamar siguiente · C-002'), findsOneWidget);
    expect(find.text('Fila (2)'), findsOneWidget);
  });

  testWidgets('"Llamar siguiente" llama al primero en espera', (t) async {
    useDesktopSize(t);
    final env = build();
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);
    await t.tap(find.text('Llamar siguiente · C-002'));
    await settle(t);
    expect(env.tickets.calls, ['call:t2']);
    expect(find.text('Fila (1)'), findsOneWidget);
    expect(find.text('Llamar siguiente · C-003'), findsOneWidget);
  });

  testWidgets('finalizar y no-show (con confirmación)', (t) async {
    useDesktopSize(t);
    final env = build();
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);

    await t.tap(find.text('No-show'));
    await settle(t);
    expect(find.text('Marcar no-show'), findsNWidgets(2)); // título + botón del diálogo
    await t.tap(find.text('Cancelar'));
    await settle(t);
    expect(env.tickets.calls, isEmpty); // cancelar no ejecuta nada

    await t.tap(find.text('Finalizar'));
    await settle(t);
    expect(env.tickets.calls, ['finish:t1']);
  });

  testWidgets('un evento en vivo agrega un turno a la fila', (t) async {
    useDesktopSize(t);
    final env = build();
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);
    expect(find.text('Fila (2)'), findsOneWidget);

    env.realtime.events.add(QueueEvent(type: QueueEventType.ticketCreated, queueId: 'q1', ticket: makeTicket('t9', 4, TicketStatus.enEspera, pos: 3)));
    await settle(t);
    expect(find.text('Fila (3)'), findsOneWidget);
    expect(find.text('C-004'), findsOneWidget);
  });

  testWidgets('error de la API al actuar se muestra y no cambia la fila', (t) async {
    useDesktopSize(t);
    final env = build();
    env.tickets.actionFailure = const ConflictFailure('Transición inválida');
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);
    await t.tap(find.text('Finalizar'));
    await settle(t);
    // el SnackBar vive en el ScaffoldMessenger de themed()
    expect(find.text('Transición inválida'), findsOneWidget);
    expect(find.text('Fila (2)'), findsOneWidget);
  });

  testWidgets('sin turnos en espera deshabilita el botón principal', (t) async {
    useDesktopSize(t);
    final env = build(tickets: [makeTicket('t1', 1, TicketStatus.finalizado)]);
    await t.pumpWidget(themed(const LiveBoard(queueId: 'q1', queueName: 'Caja 1'), env));
    await settle(t);
    expect(find.text('No hay turnos en espera'), findsOneWidget);
    expect(find.text('Nadie en espera'), findsOneWidget);
  });
}
