import type { Result } from '@qhub/core';

export interface OrganizationSummary {
  id: string; name: string; slug: string; description?: string | null; address?: string | null; city?: string | null; country?: string | null;
  phone?: string | null; latitude?: number | null; longitude?: number | null;
}

/** Iniciales para la marca (`Notaría 12` → `N1`). */
export function orgMark(name: string): string {
  const words = name.split(/\s+/).filter(Boolean);
  if (words.length === 0) return '?';
  if (words.length === 1) return words[0]!.slice(0, 3).toUpperCase();
  return words.slice(0, 3).map((w) => w[0]).join('').toUpperCase();
}
export const orgLocation = (o: OrganizationSummary): string => [o.address, o.city].filter((s): s is string => !!s).join(' · ');

export interface OrganizationRepository {
  /** Organizaciones visibles al público (publicadas y activas), filtradas por nombre/ciudad. */
  search(query: string): Promise<Result<OrganizationSummary[]>>;
  get(id: string): Promise<Result<OrganizationSummary>>;
  /** Prefijo visible de cada cola (`C` → `C-023`); el público también puede leerlo. */
  queuePrefixes(organizationId: string): Promise<Result<Record<string, string>>>;
  favoriteIds(): Promise<Result<Set<string>>>;
  setFavorite(organizationId: string, favorite: boolean): Promise<Result<void>>;
}
