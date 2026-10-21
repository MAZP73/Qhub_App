import type { Result } from '@qhub/core';

export interface OrganizationSummary {
  id: string; name: string; slug: string; description?: string | null; address?: string | null; city?: string | null; country?: string | null;
  phone?: string | null; latitude?: number | null; longitude?: number | null;
  /** ID público corto (QH-XXXXXX): se puede buscar y compartir. */
  code?: string | null;
  /** La persona ya está vinculada (es cliente de esta organización). */
  linked?: boolean;
  /** Empresa (con equipo) o cuenta personal (una persona natural). */
  kind?: OrganizationKind;
}

export type OrganizationKind = 'empresa' | 'persona';
export const KIND_LABEL: Record<OrganizationKind, string> = { empresa: 'Empresa', persona: 'Persona' };

/** Iniciales para la marca (`Notaría 12` → `N1`). */
export function orgMark(name: string): string {
  const words = name.split(/\s+/).filter(Boolean);
  if (words.length === 0) return '?';
  if (words.length === 1) return words[0]!.slice(0, 3).toUpperCase();
  return words.slice(0, 3).map((w) => w[0]).join('').toUpperCase();
}
export const orgLocation = (o: OrganizationSummary): string => [o.address, o.city].filter((s): s is string => !!s).join(' · ');

export interface OrganizationRepository {
  /** Organizaciones publicadas, por nombre, ciudad, dirección o ID (QH-XXXXXX). */
  search(query: string): Promise<Result<OrganizationSummary[]>>;
  get(id: string): Promise<Result<OrganizationSummary>>;
  /** Prefijo visible de cada cola (`C` → `C-023`); el público también puede leerlo. */
  queuePrefixes(organizationId: string): Promise<Result<Record<string, string>>>;
  /** Las organizaciones a las que estoy vinculado (soy su cliente). Puedo estar vinculado a varias. */
  linked(): Promise<Result<OrganizationSummary[]>>;
  /** Vincularse da acceso a sus colas y a sacar turno; se aparece como cliente en su plataforma. */
  link(organizationId: string): Promise<Result<void>>;
  unlink(organizationId: string): Promise<Result<void>>;
}
