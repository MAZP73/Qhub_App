import type { SupabaseClient } from '@supabase/supabase-js';
import { err, failureFromSupabase, ok, type Result } from '@qhub/core';
import type { EditRequest, EditRequestRepository } from './edit-requests';

type Row = Record<string, unknown>;

export class SupabaseEditRequestRepository implements EditRequestRepository {
  constructor(private readonly sb: SupabaseClient) {}
  private async run<T>(body: () => Promise<T>): Promise<Result<T>> { try { return ok(await body()); } catch (e) { return err(failureFromSupabase(e)); } }

  pending() {
    return this.run(async () => {
      const { data, error } = await this.sb.rpc('mis_solicitudes_edicion');
      if (error) throw error;
      return ((data ?? []) as Row[]).map((r): EditRequest => ({ id: String(r.id), organization: String(r.organizacion), reason: typeof r.motivo === 'string' ? r.motivo : null, expiresAt: new Date(String(r.vence_en)) }));
    });
  }
  respond(id: string, approve: boolean) {
    return this.run(async () => { const { error } = await this.sb.rpc('responder_edicion_cliente', { p_id: id, p_aprobar: approve }); if (error) throw error; });
  }
}
