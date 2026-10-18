/// Número de turno como lo muestra el design system: prefijo, guion y tres dígitos (`A-023`).
String formatTurnNumber(int number, {String prefix = 'A'}) =>
    '$prefix-${number.toString().padLeft(3, '0')}';

/// Prefijo por defecto de una cola: su primera letra A–Z (`Caja 1` → `C`), o `A`.
String defaultQueuePrefix(String queueName) {
  for (final rune in queueName.toUpperCase().runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'^[A-Z]$').hasMatch(ch)) return ch;
  }
  return 'A';
}

/// Hora en 24 h (`09:30`).
String formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// Recorta `08:00:00` a `08:00`.
String trimSeconds(String time) => time.length >= 5 ? time.substring(0, 5) : time;

/// Espera estimada en minutos para [peopleAhead] personas delante.
/// `ceil(personasDelante / puestos) * duracionTurno`. Es aritmética del horario, no predicción.
int estimateWaitMinutes({required int peopleAhead, required int turnMinutes, int slots = 1}) {
  if (peopleAhead <= 0) return 0;
  final lanes = slots < 1 ? 1 : slots;
  return ((peopleAhead + lanes - 1) ~/ lanes) * turnMinutes;
}
