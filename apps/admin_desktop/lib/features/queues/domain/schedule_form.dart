import 'package:qhub_api_client/qhub_api_client.dart';

/// Resumen derivado del horario que se muestra mientras el admin lo edita.
class ScheduleSummary {
  const ScheduleSummary({required this.slotsPerDay, required this.capacityPerSlot, required this.turnsPerDay, required this.turnsPerWeek});
  final int slotsPerDay;
  final int capacityPerSlot;
  final int turnsPerDay;
  final int turnsPerWeek;
}

int _mins(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

final _hm = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');
bool isValidHm(String v) => _hm.hasMatch(v.trim());

/// Normaliza `8:00` → `08:00`.
String normalizeHm(String v) {
  final p = v.trim().split(':');
  return '${p[0].padLeft(2, '0')}:${p[1]}';
}

ScheduleSummary summarize(ScheduleInput s) {
  final span = _mins(s.closes) - _mins(s.opens);
  final slots = span > 0 && s.slotMinutes > 0 ? span ~/ s.slotMinutes : 0;
  final perSlot = s.capacityPerSlot;
  var perDay = slots * perSlot;
  if (s.dailyCapacity > 0 && s.dailyCapacity < perDay) perDay = s.dailyCapacity;
  return ScheduleSummary(slotsPerDay: slots, capacityPerSlot: perSlot, turnsPerDay: perDay, turnsPerWeek: perDay * s.days.length);
}

const weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
