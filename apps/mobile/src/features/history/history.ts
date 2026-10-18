import { isActiveStatus, type TicketStatus } from '@qhub/api-client';
import type { Result } from '@qhub/core';

/** Copia local de un turno del usuario (la escribe el backend al sacar/cambiar un turno). */
export interface HistoryEntry {
  ticketId: string; organizationId: string; queueId: string; queueName?: string | null; organizationName?: string | null;
  number: number; status: TicketStatus; createdAt: Date; slotStart?: Date | null;
}
export const isActiveEntry = (e: HistoryEntry) => isActiveStatus(e.status);

export interface HistoryRepository { list(limit?: number): Promise<Result<HistoryEntry[]>> }

/** Agrupa por día (`YYYY-MM-DD` local). Orden: más reciente primero. */
export function groupByDay<T extends { createdAt: Date }>(items: readonly T[]): Array<{ day: Date; items: T[] }> {
  const sorted = [...items].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  const out = new Map<string, { day: Date; items: T[] }>();
  for (const e of sorted) {
    const d = new Date(e.createdAt.getFullYear(), e.createdAt.getMonth(), e.createdAt.getDate());
    const k = d.toDateString();
    if (!out.has(k)) out.set(k, { day: d, items: [] });
    out.get(k)!.items.push(e);
  }
  return [...out.values()];
}

const MONTHS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
/** Etiqueta de día: Hoy / Ayer / `20 oct`. */
export function dayLabel(day: Date, now: Date): string {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const diff = Math.round((t - new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime()) / 864e5);
  if (diff === 0) return 'Hoy';
  if (diff === 1) return 'Ayer';
  return `${day.getDate()} ${MONTHS[day.getMonth()]}`;
}
