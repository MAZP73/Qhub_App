import 'package:qhub_core/qhub_core.dart';

import 'entities.dart';
import 'repositories.dart';

/// Casos de uso pequeños y reutilizables por las dos apps. Las reglas puras viven aquí.

/// Valida el horario antes de ir a la red (misma regla que la API) para dar errores claros.
class ValidateSchedule {
  const ValidateSchedule();

  /// Devuelve el mensaje de error o `null` si es válido.
  String? call(ScheduleInput s) {
    int mins(String t) {
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    if (s.days.isEmpty) return 'Elige al menos un día de atención.';
    if (s.days.any((d) => d < 1 || d > 7)) return 'Los días deben ir de 1 (lunes) a 7 (domingo).';
    if (mins(s.closes) <= mins(s.opens)) return 'El cierre debe ser posterior a la apertura.';
    if (s.slotMinutes < 5 || s.slotMinutes > 480) return 'La franja debe durar entre 5 y 480 minutos.';
    if (s.turnMinutes < 1) return 'El trámite debe durar al menos 1 minuto.';
    if (s.turnMinutes > s.slotMinutes) return 'El trámite no puede ser más largo que la franja.';
    if (s.stations < 1) return 'Los cupos deben ser mayores que 0.';
    if (s.maxDaysAhead < 0 || s.maxDaysAhead > 365) return 'La anticipación máxima va de 0 a 365 días.';
    return null;
  }
}

/// Crea una cola validando el horario si viene.
class CreateQueue {
  const CreateQueue(this._queues, [this._validate = const ValidateSchedule()]);
  final QueueRepository _queues;
  final ValidateSchedule _validate;

  Future<Result<Queue>> call(CreateQueueInput input) async {
    if (input.name.trim().isEmpty) return const Result.err(ValidationFailure('Escribe el nombre de la cola.'));
    final schedule = input.schedule;
    if (schedule != null) {
      final error = _validate(schedule);
      if (error != null) return Result.err(ValidationFailure(error));
    }
    return _queues.create(input);
  }
}

/// Define el horario de una cola validándolo primero.
class ReplaceSchedule {
  const ReplaceSchedule(this._queues, [this._validate = const ValidateSchedule()]);
  final QueueRepository _queues;
  final ValidateSchedule _validate;

  Future<Result<Schedule>> call(String queueId, ScheduleInput input) async {
    final error = _validate(input);
    if (error != null) return Result.err(ValidationFailure(error));
    return _queues.replaceSchedule(queueId, input);
  }
}

/// Orden de la fila de atención: atendiendo primero, luego por franja y posición.
List<Ticket> sortWaitingRoom(Iterable<Ticket> tickets) {
  final list = tickets.where((t) => t.status.isActive).toList();
  list.sort((a, b) {
    if (a.status != b.status) return a.status == TicketStatus.atendiendo ? -1 : 1;
    final bySlot = a.slotStart.compareTo(b.slotStart);
    return bySlot != 0 ? bySlot : a.position.compareTo(b.position);
  });
  return list;
}

/// Siguiente turno a llamar: el primero `en_espera` de la franja más próxima.
Ticket? nextToCall(Iterable<Ticket> tickets) {
  for (final t in sortWaitingRoom(tickets)) {
    if (t.status == TicketStatus.enEspera) return t;
  }
  return null;
}

/// Aplica un evento en vivo a la lista de turnos de una cola (reducer puro).
List<Ticket> applyQueueEvent(List<Ticket> current, QueueEvent event) {
  final t = event.ticket;
  if (t == null) return current;
  final next = [...current];
  final i = next.indexWhere((x) => x.id == t.id);
  if (i >= 0) {
    next[i] = t;
  } else {
    next.add(t);
  }
  return next;
}

/// Personas delante de [mine] en su cola: activos de la misma o anterior franja con menor posición.
int peopleAhead(Ticket mine, Iterable<Ticket> queue) => queue
    .where((t) =>
        t.id != mine.id &&
        t.status.isActive &&
        (t.slotStart.isBefore(mine.slotStart) ||
            (t.slotStart.isAtSameMomentAs(mine.slotStart) && t.position < mine.position)))
    .length;
