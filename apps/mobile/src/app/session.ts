import { friendlyError } from '@qhub/core';
import { parseAuthLink } from '@/features/auth/auth-link';
import type { AppUser, UserRepository } from '@/features/auth/user';

export type Loadable<T> = { status: 'loading' } | { status: 'ready'; value: T };
/** Aviso que deja un enlace del correo (p. ej. «el enlace venció») para mostrarlo en la pantalla de acceso. */
export interface LinkNotice { kind: 'error' | 'info'; text: string }

/** Estado de sesión de la app móvil: quién es la persona y si está eligiendo contraseña nueva tras el enlace del correo. */
export class AppSession {
  private snap: Loadable<AppUser | null> = { status: 'loading' };
  private recovering = false;
  private notice: LinkNotice | null = null;
  private lastUser: AppUser | null = null;
  private readonly listeners = new Set<() => void>();
  private stop: (() => void) | null = null;
  constructor(private readonly users: UserRepository) {}
  subscribe = (l: () => void) => { this.listeners.add(l); return () => { this.listeners.delete(l); }; };
  getSnapshot = () => this.snap;
  isRecovering = () => this.recovering;
  getNotice = () => this.notice;
  private emit() { this.listeners.forEach((l) => l()); }

  start() {
    this.stop?.();
    this.stop = this.users.onAuthChange((u) => {
      // Si se pierde la sesión (puerta de solo-clientes, cierre), ya no hay nada que restablecer.
      if (u === null && this.lastUser !== null) this.recovering = false;
      this.lastUser = u;
      this.snap = { status: 'ready', value: u };
      this.emit();
    });
  }
  dispose() { this.stop?.(); this.stop = null; }

  /** Enlace entrante (correo de confirmación o de recuperación). Lo que no es de autenticación se ignora. */
  async handleUrl(url: string | null | undefined) {
    const link = parseAuthLink(url);
    if (!link) return;
    if (link.kind === 'error') { this.notice = { kind: 'error', text: link.message }; this.emit(); return; }
    this.notice = null;
    // La marca va ANTES de abrir la sesión: así la app nunca llega a mostrar las pestañas antes de pedir la contraseña nueva.
    if (link.type === 'recovery') { this.recovering = true; this.emit(); }
    const r = await this.users.openLinkSession(link);
    if (!r.ok) { this.recovering = false; this.notice = { kind: 'error', text: friendlyError(r.failure) }; this.emit(); }
  }

  clearNotice() { if (this.notice) { this.notice = null; this.emit(); } }
  /** La contraseña nueva ya quedó guardada: se entra a la app. */
  finishRecovery() { this.recovering = false; this.emit(); }
  /** Se abandona el restablecimiento: se cierra la sesión que abrió el enlace. */
  async cancelRecovery() { this.recovering = false; this.emit(); await this.users.signOut(); }
}
