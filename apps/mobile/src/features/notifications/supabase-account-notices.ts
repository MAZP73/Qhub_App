import type { SupabaseClient } from '@supabase/supabase-js';
import { err, failureFromSupabase, ok, serverFailure, type Result } from '@qhub/core';
import type { AccountNotice, AccountNoticeRepository } from './account-notices';

export class SupabaseAccountNoticeRepository implements AccountNoticeRepository {
  constructor(private readonly sb: SupabaseClient) {}
  async list(limit = 50): Promise<Result<AccountNotice[]>> {
    try {
      const { data, error } = await this.sb.from('avisos_cuenta').select('id, tipo, titulo, mensaje, leida, creada_en').order('creada_en', { ascending: false }).limit(limit);
      if (error) return err(serverFailure());
      return ok((data as Array<Record<string, unknown>>).map((r) => ({
        id: String(r.id), type: String(r.tipo), title: String(r.titulo), message: String(r.mensaje), read: r.leida === true, createdAt: new Date(String(r.creada_en)),
      })));
    } catch (e) { return err(failureFromSupabase(e)); }
  }
  async markRead(id: string): Promise<Result<void>> {
    try {
      const { error } = await this.sb.from('avisos_cuenta').update({ leida: true }).eq('id', id);
      return error ? err(serverFailure()) : ok(undefined);
    } catch (e) { return err(failureFromSupabase(e)); }
  }
}
