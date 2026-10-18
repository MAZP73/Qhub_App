import 'package:qhub_api_client/qhub_api_client.dart' show TicketStatus;
import 'package:qhub_core/qhub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/history.dart';

class SupabaseHistoryRepository implements HistoryRepository {
  SupabaseHistoryRepository(this._client);
  final sb.SupabaseClient _client;

  @override
  Future<Result<List<HistoryEntry>>> list({int limit = 100}) async {
    try {
      final rows = await _client
          .from('historial_turnos')
          .select('qhub_turno_id, organizacion_id, qhub_cola_id, cola_nombre, numero, estado, franja_inicio, creado_en, organizaciones(nombre)')
          .order('creado_en', ascending: false)
          .limit(limit);
      return Result.ok([
        for (final r in rows)
          HistoryEntry(
            ticketId: r['qhub_turno_id'] as String,
            organizationId: r['organizacion_id'] as String,
            queueId: r['qhub_cola_id'] as String,
            queueName: r['cola_nombre'] as String?,
            organizationName: (r['organizaciones'] as Map?)?['nombre'] as String?,
            number: (r['numero'] ?? 0) as int,
            status: TicketStatus.parse(r['estado'] as String),
            createdAt: DateTime.parse(r['creado_en'] as String),
            slotStart: r['franja_inicio'] == null ? null : DateTime.parse(r['franja_inicio'] as String),
          ),
      ]);
    } on sb.PostgrestException {
      return const Result.err(ServerFailure());
    } catch (e) {
      final s = e.toString();
      return Result.err(s.contains('SocketException') || s.contains('ClientException') ? const NetworkFailure() : const UnknownFailure());
    }
  }
}
