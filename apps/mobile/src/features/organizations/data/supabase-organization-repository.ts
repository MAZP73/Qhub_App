import type { SupabaseClient } from '@supabase/supabase-js';
import { err, forbiddenFailure, isFailure, networkFailure, ok, serverFailure, unauthorizedFailure, unknownFailure, type Failure, type Result } from '@qhub/core';
import type { OrganizationRepository, OrganizationSummary } from '../domain/organizations';

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
    return { id: String(j.id), name: String(j.nombre), slug: String(j.slug), description: (j.descripcion as string) ?? null, address: (j.direccion as string) ?? null, city: (j.ciudad as string) ?? null, country: (j.pais as string) ?? null, phone: (j.telefono as string) ?? null, latitude: (j.latitud as number) ?? null, longitude: (j.longitud as number) ?? null };
  }

  search(query: string) {
    return this.run(async () => {
      let req = this.sb.from('organizaciones').select().eq('publica', true).eq('activa', true);
      const q = query.trim().replace(/[%,()]/g, ' ');
      if (q) req = req.or(`nombre.ilike.%${q}%,ciudad.ilike.%${q}%,direccion.ilike.%${q}%`);
      return (await this.q<Row[]>(req.order('nombre').limit(100))).map((r) => this.row(r));
    });
  }
  get(id: string) { return this.run(async () => this.row(await this.q<Row>(this.sb.from('organizaciones').select().eq('id', id).single()))); }
  queuePrefixes(organizationId: string) {
    return this.run(async () => Object.fromEntries((await this.q<Row[]>(this.sb.from('cola_prefijos').select('qhub_cola_id, prefijo').eq('organizacion_id', organizationId))).map((r) => [String(r.qhub_cola_id), String(r.prefijo)])));
  }
  favoriteIds() { return this.run(async () => new Set((await this.q<Row[]>(this.sb.from('favoritos').select('organizacion_id'))).map((r) => String(r.organizacion_id)))); }
  setFavorite(organizationId: string, favorite: boolean) {
    return this.run(async () => {
      const { data } = await this.sb.auth.getUser();
      if (!data.user) throw unauthorizedFailure();
      if (favorite) await this.q(this.sb.from('favoritos').upsert({ usuario_id: data.user.id, organizacion_id: organizationId }, { ignoreDuplicates: true }));
      else await this.q(this.sb.from('favoritos').delete().eq('organizacion_id', organizationId).is('qhub_cola_id', null));
    });
  }
}
