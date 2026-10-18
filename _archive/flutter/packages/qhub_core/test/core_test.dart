import 'package:qhub_core/qhub_core.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('ok expone el valor y map transforma', () {
      const r = Result<int>.ok(2);
      expect(r.isOk, isTrue);
      expect(r.map((v) => v * 3).valueOrNull, 6);
    });

    test('err conserva el failure y when lo enruta', () {
      const r = Result<int>.err(NotFoundFailure());
      expect(r.isErr, isTrue);
      expect(r.when(ok: (_) => 'ok', err: (f) => f.runtimeType.toString()), 'NotFoundFailure');
      expect(() => r.getOrThrow(), throwsA(isA<NotFoundFailure>()));
    });
  });

  group('turnos', () {
    test('formatea con prefijo y tres dígitos', () {
      expect(formatTurnNumber(23), 'A-023');
      expect(formatTurnNumber(7, prefix: 'E'), 'E-007');
      expect(formatTurnNumber(1234, prefix: 'B'), 'B-1234');
    });

    test('prefijo por defecto', () {
      expect(defaultQueuePrefix('Caja 1'), 'C');
      expect(defaultQueuePrefix('  órdenes'), 'R'); // primera A–Z tras normalizar
      expect(defaultQueuePrefix('123'), 'A');
    });

    test('estimación', () {
      expect(estimateWaitMinutes(peopleAhead: 0, turnMinutes: 3), 0);
      expect(estimateWaitMinutes(peopleAhead: 3, turnMinutes: 3), 9);
      expect(estimateWaitMinutes(peopleAhead: 3, turnMinutes: 10, slots: 2), 20);
    });

    test('horas', () {
      expect(formatHm(DateTime(2026, 1, 1, 9, 5)), '09:05');
      expect(trimSeconds('08:00:00'), '08:00');
    });
  });
}
