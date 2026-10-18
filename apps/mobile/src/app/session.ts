import type { AppUser, UserRepository } from '@/features/auth/domain/user';

export type Loadable<T> = { status: 'loading' } | { status: 'ready'; value: T };

/** Estado de sesión de la app móvil: quién es la persona. */
export class AppSession {
  private snap: Loadable<AppUser | null> = { status: 'loading' };
  private readonly listeners = new Set<() => void>();
  private stop: (() => void) | null = null;
  constructor(private readonly users: UserRepository) {}
  subscribe = (l: () => void) => { this.listeners.add(l); return () => { this.listeners.delete(l); }; };
  getSnapshot = () => this.snap;
  start() { this.stop?.(); this.stop = this.users.onAuthChange((u) => { this.snap = { status: 'ready', value: u }; this.listeners.forEach((l) => l()); }); }
  dispose() { this.stop?.(); this.stop = null; }
}
