import type { SupabaseClient } from '@supabase/supabase-js';
import { err, failureFromSupabase, ok, unauthorizedFailure, type Result } from '@qhub/core';
import type { Profile } from '@qhub/core';
import type { ProfileRepository } from './profile';

type Row = Record<string, unknown>;

/** Adaptador Supabase del perfil móvil. Traduce errores a Failure; la pantalla no ve errores crudos. */
export class SupabaseProfileRepository implements ProfileRepository {
  constructor(private readonly sb: SupabaseClient) {}

  private async run<T>(body: () => Promise<T>): Promise<Result<T>> { try { return ok(await body()); } catch (e) { return err(failureFromSupabase(e)); } }
  private async q<T>(p: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> { const { data, error } = await p; if (error) throw error; return data as T; }
  private async uid(): Promise<string> { const { data } = await this.sb.auth.getUser(); if (!data.user) throw unauthorizedFailure(); return data.user.id; }

  private profileOf(r: Row): Profile {
    const s = (k: string) => (typeof r[k] === 'string' ? (r[k] as string) : '');
    return { firstName: s('nombre'), lastName: s('apellido'), phone: s('telefono'), jobTitle: s('cargo'), country: s('pais'), city: s('ciudad'), timeZone: s('zona_horaria') };
  }

  get() {
    return this.run(async () => {
      const uid = await this.uid();
      return this.profileOf(await this.q<Row>(this.sb.from('perfiles').select('nombre, apellido, telefono, cargo, pais, ciudad, zona_horaria').eq('id', uid).single() as unknown as PromiseLike<{ data: Row; error: unknown }>));
    });
  }

  update(p: Profile) {
    return this.run(async () => {
      const uid = await this.uid();
      const n = (v: string) => (v.trim() ? v.trim() : null);
      const row = await this.q<Row>(this.sb.from('perfiles').update({ nombre: n(p.firstName), apellido: n(p.lastName), telefono: n(p.phone), cargo: n(p.jobTitle), pais: n(p.country), ciudad: n(p.city), zona_horaria: n(p.timeZone) })
        .eq('id', uid).select('nombre, apellido, telefono, cargo, pais, ciudad, zona_horaria').single() as unknown as PromiseLike<{ data: Row; error: unknown }>);
      // El nombre también vive en los metadatos de auth (lo muestra la cabecera).
      await this.sb.auth.updateUser({ data: { nombre: p.firstName.trim(), apellido: p.lastName.trim() } });
      return this.profileOf(row);
    });
  }

  /** Replica `es_miembro_gestionado` desde el cliente (RLS deja ver las filas propias): empresa + rol distinto de admin. */
  managementStatus() {
    return this.run(async () => {
      const uid = await this.uid();
      const rows = await this.q<Row[]>(this.sb.from('miembros').select('rol, organizaciones!inner(tipo)').eq('usuario_id', uid).eq('activo', true).neq('rol', 'admin') as unknown as PromiseLike<{ data: Row[]; error: unknown }>);
      return rows.some((r) => { const o = r.organizaciones as Row | Row[] | undefined; const tipo = Array.isArray(o) ? o[0]?.tipo : o?.tipo; return tipo === 'empresa'; });
    });
  }
}
