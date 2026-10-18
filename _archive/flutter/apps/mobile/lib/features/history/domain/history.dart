import 'package:qhub_api_client/qhub_api_client.dart';
import 'package:qhub_core/qhub_core.dart';

/// Copia local de un turno del usuario (la escribe el backend al sacar/cambiar un turno).
class HistoryEntry {
  const HistoryEntry({
    required this.ticketId,
    required this.organizationId,
    required this.queueId,
    required this.number,
    required this.status,
    required this.createdAt,
    this.queueName,
    this.organizationName,
    this.slotStart,
  });
  final String ticketId;
  final String organizationId;
  final String queueId;
  final String? queueName;
  final String? organizationName;
  final int number;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime? slotStart;

  bool get isActive => status.isActive;
}

abstract interface class HistoryRepository {
  Future<Result<List<HistoryEntry>>> list({int limit = 100});
}

/// Agrupa por día para la pantalla de historial. Orden: más reciente primero.
Map<DateTime, List<HistoryEntry>> groupByDay(Iterable<HistoryEntry> entries) {
  final sorted = entries.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final out = <DateTime, List<HistoryEntry>>{};
  for (final e in sorted) {
    final l = e.createdAt.toLocal();
    out.putIfAbsent(DateTime(l.year, l.month, l.day), () => []).add(e);
  }
  return out;
}

/// Etiqueta de día: Hoy / Ayer / `20 oct`.
String dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(day.year, day.month, day.day)).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${day.day} ${m[day.month - 1]}';
}
