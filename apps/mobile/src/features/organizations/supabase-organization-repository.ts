import type { SupabaseClient } from '@supabase/supabase-js';
import { err, forbiddenFailure, isFailure, networkFailure, ok, serverFailure, unauthorizedFailure, unknownFailure, type Failure, type Result } from '@qhub/core';
import type { OrganizationRepository, OrganizationSummary } from './organizations';

type Row = Record<string, unknown>;

export class SupabaseOrganizationRepository implements OrganizationRepository {
  constructor(private readonly sb: SupabaseClient) {}

  private fail(e: unknown): Failure {
    if (isFailure(e)) return e;
    const x = e as { code?: string; message?: string } | null;
    if (x?.code === '42501') return forbiddenFailure();
    if (x?.code) return serverFailure();
    return /fetch|network/i.test(x?.message ?? '') ? networkFailure() : unknownFailure();
  }
  private async run<T>(body: () => Promise<T>): Promise<Result<T>> { try { return ok(await body()); } catch (e) { return err(this.fail(e)); } }
  private async q<T>(p: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> { const { data, error } = await p; if (error) throw error; return data as T; }

  private row(j: Row): OrganizationSummary {
    return {
      id: String(j.id), name: String(j.nombre), slug: String(j.slug), code: (j.codigo as string) ?? null, description: (j.descripcion as string) ?? null, address: (j.direccion as string) ?? null,
      city: (j.ciudad as string) ?? null, country: (j.pais as string) ?? null, phone: (j.telefono as string) ?? null, latitude: (j.latitud as number) ?? null, longitude: (j.longitud as number) ?? null,
      ...(j.vinculada === undefined ? {} : { linked: Boolean(j.vinculada) }),
    };
  }

  search(query: string) { return this.run(async () => (await this.q<Row[]>(this.sb.rpc('buscar_organizaciones', { p_q: query.trim() }))).map((r) => this.row(r))); }
  get(id: string) { return this.run(async () => this.row(await this.q<Row>(this.sb.from('organizaciones').select().eq('id', id).single()))); }
  queuePrefixes(organizationId: string) {
    return this.run(async () => Object.fromEntries((await this.q<Row[]>(this.sb.from('cola_prefijos').select('qhub_cola_id, prefijo').eq('organizacion_id', organizationId))).map((r) => [String(r.qhub_cola_id), String(r.prefijo)])));
  }
  linked() { return this.run(async () => (await this.q<Row[]>(this.sb.rpc('mis_organizaciones'))).map((r) => this.row(r))); }
  link(organizationId: string) {
    return this.run(async () => {
      try { await this.q(this.sb.rpc('vincular_organizacion', { p_org: organizationId })); }
      catch (e) {
        const code = (e as { code?: string } | null)?.code;
        if (code === '42501') throw forbiddenFailure('No puedes vincularte a esta organización.');
        if (code === 'P0002') throw forbiddenFailure('Esta organización ya no está disponible.');
        throw e;
      }
    });
  }
  unlink(organizationId: string) { return this.run(async () => { await this.q(this.sb.rpc('desvincular_organizacion', { p_org: organizationId })); }); }
}
