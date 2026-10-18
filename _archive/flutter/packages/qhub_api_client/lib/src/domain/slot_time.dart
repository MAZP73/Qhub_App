import 'entities.dart';

/// El cliente nunca debe calcular con la hora del dispositivo: las franjas se cuentan en la zona de la cola.
/// Sin base de datos de zonas, el desfase se deduce de la API: la primera franja del día empieza
/// exactamente a la hora de apertura (hora local de la cola).
Duration? queueUtcOffset(Schedule schedule, List<Slot> slots) {
  if (slots.isEmpty) return null;
  final first = slots.map((s) => s.start.toUtc()).reduce((a, b) => a.isBefore(b) ? a : b);
  final p = schedule.opens.split(':');
  final opensMinutes = int.parse(p[0]) * 60 + int.parse(p[1]);
  var diff = opensMinutes - (first.hour * 60 + first.minute);
  // normaliza a (-12h, +14h]
  while (diff > 14 * 60) {
    diff -= 24 * 60;
  }
  while (diff <= -12 * 60) {
    diff += 24 * 60;
  }
  return Duration(minutes: diff);
}

/// Fecha con los campos en hora de la cola (marcada UTC para que no vuelva a convertirse).
DateTime inQueueTime(DateTime instant, Duration offset) => instant.toUtc().add(offset);
