import type { Result } from '@qhub/core';

/** Aviso de la cuenta (no de una organización): bienvenida, te uniste a una organización, tu turno o cita quedó creada. Además llega por correo. */
export interface AccountNotice { id: string; type: string; title: string; message: string; read: boolean; createdAt: Date }

export interface AccountNoticeRepository {
  list(limit?: number): Promise<Result<AccountNotice[]>>;
  markRead(id: string): Promise<Result<void>>;
}
