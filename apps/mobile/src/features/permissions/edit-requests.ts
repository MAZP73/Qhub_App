import type { Result } from '@qhub/core';

/** Una organización pide permiso para cambiar mis datos (nombre, apellido, teléfono). Solo se hace si yo lo apruebo. */
export interface EditRequest { id: string; organization: string; reason: string | null; expiresAt: Date }

export interface EditRequestRepository {
  pending(): Promise<Result<EditRequest[]>>;
  /** Aprobar da a la organización UN cambio dentro de las 24 h siguientes; rechazar lo cierra. */
  respond(id: string, approve: boolean): Promise<Result<void>>;
}

/** Cuánto falta para que venza, en palabras («vence en 5 h», «vence en 40 min», «vencida»). */
export function expiresIn(e: EditRequest, now = new Date()): string {
  const min = Math.round((e.expiresAt.getTime() - now.getTime()) / 60000);
  if (min <= 0) return 'Vencida';
  if (min < 60) return `Vence en ${min} min`;
  return `Vence en ${Math.round(min / 60)} h`;
}
