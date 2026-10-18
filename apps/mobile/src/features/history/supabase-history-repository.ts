import type { SupabaseClient } from '@supabase/supabase-js';
import { err, failureFromSupabase, ok, serverFailure, type Result } from '@qhub/core';
import { parseTicketStatus } from '@qhub/api-client';
import type { HistoryEntry, HistoryRepository } from './history';

export class SupabaseHistoryRepository implements HistoryRepository {
  constructor(private readonly sb: SupabaseClient) {}
  async list(limit = 100): Promise<Result<HistoryEntry[]>> {
    try {
      const { data, error } = await this.sb.from('historial_turnos')
        .select('qhub_turno_id, organizacion_id, qhub_cola_id, cola_nombre, numero, estado, franja_inicio, creado_en, organizaciones(nombre)')
        .order('creado_en', { ascending: false }).limit(limit);
      if (error) return err(serverFailure());
      return ok((data as Array<Record<string, unknown>>).map((r) => ({
        ticketId: String(r.qhub_turno_id), organizationId: String(r.organizacion_id), queueId: String(r.qhub_cola_id), queueName: (r.cola_nombre as string) ?? null,
        organizationName: ((r.organizaciones as { nombre?: string } | null)?.nombre) ?? null, number: Number(r.numero ?? 0), status: parseTicketStatus(String(r.estado)),
        createdAt: new Date(String(r.creado_en)), slotStart: r.franja_inicio ? new Date(String(r.franja_inicio)) : null,
      })));
    } catch (e) {
      return err(failureFromSupabase(e));
    }
  }
}
