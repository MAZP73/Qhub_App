import type { Result } from '@qhub/core';

export interface AppUser { id: string; email: string; displayName?: string }

export interface UserRepository {
  onAuthChange(cb: (u: AppUser | null) => void): () => void;
  signIn(email: string, password: string): Promise<Result<AppUser>>;
  /** `null` = el proyecto exige confirmar el correo antes de entrar. */
  signUp(input: { email: string; password: string; firstName: string; lastName: string }): Promise<Result<AppUser | null>>;
  signOut(): Promise<Result<void>>;
  /** Manda el correo para elegir una contraseña nueva. Siempre responde igual: no revela si el correo existe. */
  requestPasswordReset(email: string): Promise<Result<void>>;
  /** Abre la sesión que trae el enlace del correo (confirmación o recuperación). */
  openLinkSession(link: { accessToken: string; refreshToken: string }): Promise<Result<void>>;
  /** Cambia la contraseña de la sesión abierta (tras el enlace de recuperación). */
  updatePassword(password: string): Promise<Result<void>>;
}
