import 'package:mocktail/mocktail.dart';
import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';
import 'package:test/test.dart';

class _MockQueues extends Mock implements QueueRepository {}

Ticket t(String id, TicketStatus s, {int pos = 1, DateTime? slot}) => Ticket(
      id: id, queueId: 'q', ownerName: 'o', userId: 'u',
      slotStart: slot ?? DateTime.utc(2026, 10, 20, 15), scheduled: false, number: pos,
      status: s, position: pos, createdAt: DateTime.utc(2026, 10, 20, 14),
    );

const okInput = ScheduleInput(
    opens: '08:00', closes: '18:00', slotMinutes: 30, days: [1, 2], turnMinutes: 10, maxDaysAhead: 7);

void main() {
  setUpAll(() => registerFallbackValue(const CreateQueueInput(name: 'x')));

  group('ValidateSchedule', () {
    const v = ValidateSchedule();
    test('acepta un horario coherente', () => expect(v(okInput), isNull));
    test('cierre antes de apertura', () {
      expect(v(const ScheduleInput(opens: '18:00', closes: '08:00', slotMinutes: 30, days: [1], turnMinutes: 10, maxDaysAhead: 1)),
          contains('posterior'));
    });
    test('trámite más largo que la franja', () {
      expect(v(const ScheduleInput(opens: '08:00', closes: '18:00', slotMinutes: 15, days: [1], turnMinutes: 20, maxDaysAhead: 1)),
          contains('más largo'));
    });
    test('sin días / día inválido', () {
      expect(v(const ScheduleInput(opens: '08:00', closes: '18:00', slotMinutes: 30, days: [], turnMinutes: 10, maxDaysAhead: 1)), isNotNull);
      expect(v(const ScheduleInput(opens: '08:00', closes: '18:00', slotMinutes: 30, days: [8], turnMinutes: 10, maxDaysAhead: 1)), isNotNull);
    });
    test('cupos por franja = floor(franja/trámite) × puestos', () {
      expect(okInput.capacityPerSlot, 3);
      expect(const ScheduleInput(opens: '08:00', closes: '18:00', slotMinutes: 30, days: [1], turnMinutes: 10, stations: 2, maxDaysAhead: 1).capacityPerSlot, 6);
      expect(const ScheduleInput(opens: '08:00', closes: '18:00', slotMinutes: 30, days: [1], turnMinutes: 20, maxDaysAhead: 1).capacityPerSlot, 1);
    });
  });

  group('CreateQueue / ReplaceSchedule', () {
    test('no llama a la red si el horario es inválido', () async {
      final repo = _MockQueues();
      final r = await CreateQueue(repo)(const CreateQueueInput(
          name: 'Caja', schedule: ScheduleInput(opens: '18:00', closes: '08:00', slotMinutes: 30, days: [1], turnMinutes: 10, maxDaysAhead: 1)));
      expect(r.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repo.create(any()));
    });

    test('rechaza nombre vacío', () async {
      final r = await CreateQueue(_MockQueues())(const CreateQueueInput(name: '  '));
      expect(r.failureOrNull, isA<ValidationFailure>());
    });

    test('delega en el repositorio cuando es válido', () async {
      final repo = _MockQueues();
      const q = Queue(id: 'q', ownerName: 'o', name: 'Caja', active: true);
      when(() => repo.create(any())).thenAnswer((_) async => const Result.ok(q));
      expect((await CreateQueue(repo)(const CreateQueueInput(name: 'Caja', schedule: okInput))).valueOrNull, q);
      verify(() => repo.create(any())).called(1);
    });
  });

  group('fila de atención', () {
    final a = t('a', TicketStatus.enEspera, pos: 2);
    final b = t('b', TicketStatus.enEspera, pos: 1);
    final c = t('c', TicketStatus.atendiendo, pos: 0);
    final d = t('d', TicketStatus.finalizado);
    final later = t('e', TicketStatus.enEspera, pos: 1, slot: DateTime.utc(2026, 10, 20, 16));

    test('atendiendo primero, luego franja y posición; excluye cerrados', () {
      expect(sortWaitingRoom([a, later, d, b, c]).map((x) => x.id), ['c', 'b', 'a', 'e']);
    });
    test('siguiente a llamar', () {
      expect(nextToCall([a, b, c, later])?.id, 'b');
      expect(nextToCall([c, d]), isNull);
    });
    test('reducer de eventos inserta y reemplaza', () {
      final ev = QueueEvent(type: QueueEventType.ticketCalled, queueId: 'q', ticket: t('a', TicketStatus.atendiendo));
      final out = applyQueueEvent([a, b], ev);
      expect(out.length, 2);
      expect(out.firstWhere((x) => x.id == 'a').status, TicketStatus.atendiendo);
      final added = applyQueueEvent([a], QueueEvent(type: QueueEventType.ticketCreated, queueId: 'q', ticket: t('z', TicketStatus.enEspera)));
      expect(added.length, 2);
      expect(applyQueueEvent([a], const QueueEvent(type: QueueEventType.queueUpdated, queueId: 'q')), [a]);
    });
    test('personas delante', () {
      final mine = t('m', TicketStatus.enEspera, pos: 3);
      expect(peopleAhead(mine, [a, b, c, d, mine, later]), 3); // c (atendiendo), b y a van delante
    });
  });

  test('TicketStatus: solo cancelado y no-show liberan cupo', () {
    expect(TicketStatus.values.where((s) => s.releasesSlot), [TicketStatus.cancelado, TicketStatus.noShow]);
    expect(TicketStatus.parse('no_show'), TicketStatus.noShow);
  });
}
