import type { Result } from '@qhub/core';

export interface AppUser { id: string; email: string; displayName?: string }

export interface UserRepository {
  onAuthChange(cb: (u: AppUser | null) => void): () => void;
  signIn(email: string, password: string): Promise<Result<AppUser>>;
  /** `null` = el proyecto exige confirmar el correo antes de entrar. */
  signUp(input: { email: string; password: string; firstName: string; lastName: string }): Promise<Result<AppUser | null>>;
  signOut(): Promise<Result<void>>;
}
