import type { SupabaseClient, User } from '@supabase/supabase-js';
import {
  conflictFailure, err, failureFromSupabase, forbiddenFailure, networkFailure, ok,
  rateLimitedFailure, serverFailure, validationFailure, type Result,
} from '@qhub/core';
import type { AppUser, UserRepository } from './user';

/** La app móvil es solo para clientes. Si el correo es del staff (web) o no está registrado como cliente, se cierra la sesión. */
export const CLIENT_GATE_MESSAGE = 'Este correo es de la plataforma web de Qhub. La app y la web son cuentas independientes: usa un correo diferente para la app.';
/** Registro con un correo que ya es de la plataforma web. */
export const PLATFORM_EMAIL_MESSAGE = 'Ese correo ya se usa en la plataforma web de Qhub. La app es independiente: regístrate con un correo diferente al de la web.';

const GATE_TTL_MS = 10_000;

/** Error de red de las Edge Functions: su nombre es FunctionsFetchError (no hay red / no se pudo invocar). */
const isFetchError = (e: unknown): boolean => (e as { name?: string } | null)?.name === 'FunctionsFetchError';

export class SupabaseUserRepository implements UserRepository {
  // Cache de un solo uso y vida corta: evita repetir la verificación entre getSession() y el primer onAuthStateChange.
  private lastGate: { userId: string; cliente: boolean; at: number } | null = null;

  constructor(private readonly sb: SupabaseClient) {}

  private toUser(u: User | null | undefined): AppUser | null {
    if (!u) return null;
    const meta = u.user_metadata as Record<string, unknown> | undefined;
    const name = [meta?.nombre, meta?.apellido].filter((x): x is string => typeof x === 'string' && x.length > 0).join(' ').trim();
    return { id: u.id, email: u.email ?? '', ...(name ? { displayName: name } : {}) };
  }
  private async run<T>(body: () => Promise<T>): Promise<Result<T>> { try { return ok(await body()); } catch (e) { return err(failureFromSupabase(e)); } }

  /** Pregunta a la Edge Function si la sesión actual es de un cliente. Falla cerrado: ante cualquier error, NO es cliente. */
  private async isClient(): Promise<boolean> {
    const { data, error } = await this.sb.functions.invoke('qhub-sesion-cliente', { method: 'POST' });
    if (error) throw error;
    return (data as { cliente?: boolean } | null)?.cliente === true;
  }

  /** Verifica (con cache de 10 s) y, si no es cliente, cierra la sesión. Devuelve si el usuario quedó dentro. */
  private async gate(userId: string): Promise<boolean> {
    const now = Date.now();
    if (this.lastGate && this.lastGate.userId === userId && now - this.lastGate.at < GATE_TTL_MS) {
      const cached = this.lastGate.cliente;
      this.lastGate = null;   // un solo uso
      if (!cached) await this.sb.auth.signOut();
      return cached;
    }
    let cliente: boolean;
    try {
      cliente = await this.isClient();
    } catch (e) {
      await this.sb.auth.signOut();   // fail-closed
      throw isFetchError(e) ? networkFailure() : serverFailure();
    }
    if (!cliente) await this.sb.auth.signOut();
    return cliente;
  }

  onAuthChange(cb: (u: AppUser | null) => void) {
    // La puerta vive en la capa de sesión: un no-cliente NUNCA se reporta al store (si no, la UI autenticada parpadearía).
    const gateAndReport = async (u: User | null | undefined) => {
      if (!u) { this.lastGate = null; cb(null); return; }
      try {
        const cliente = await this.gate(u.id);
        cb(cliente ? this.toUser(u) : null);
      } catch { cb(null); }   // ya cerró sesión en gate(); nunca reporta un usuario sin verificar
    };
    void this.sb.auth.getSession().then(({ data }) => gateAndReport(data.session?.user));
    const { data } = this.sb.auth.onAuthStateChange((_e, s) => { void gateAndReport(s?.user); });
    return () => data.subscription.unsubscribe();
  }

  signIn(email: string, password: string) {
    return this.run(async () => {
      this.lastGate = null;   // entrada de login: no reutilizar una verificación vieja
      const { data, error } = await this.sb.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
      let cliente: boolean;
      try {
        cliente = await this.isClient();
      } catch (e) {
        await this.sb.auth.signOut();   // fail-closed: sin verificación no entra
        throw isFetchError(e) ? networkFailure() : serverFailure();
      }
      if (!cliente) {
        await this.sb.auth.signOut();
        throw forbiddenFailure(CLIENT_GATE_MESSAGE);
      }
      this.lastGate = { userId: data.user!.id, cliente: true, at: Date.now() };
      return this.toUser(data.user)!;
    });
  }

  signUp(i: { email: string; password: string; firstName: string; lastName: string }) {
    return this.run(async () => {
      const body = { email: i.email.trim().toLowerCase(), password: i.password, nombre: i.firstName.trim(), apellido: i.lastName.trim() };
      const { data, error } = await this.sb.functions.invoke('qhub-registro-cliente', { body });
      if (error) throw await mapRegistroError(error);
      if ((data as { needsConfirmation?: boolean } | null)?.needsConfirmation) return null;
      // Confirmación desactivada: se establece la sesión (que pasa la puerta por ser cliente) y se devuelve el usuario.
      this.lastGate = null;
      const signedIn = await this.sb.auth.signInWithPassword({ email: body.email, password: body.password });
      if (signedIn.error) throw signedIn.error;
      this.lastGate = { userId: signedIn.data.user!.id, cliente: true, at: Date.now() };
      return this.toUser(signedIn.data.user);
    });
  }

  signOut() { return this.run(async () => { this.lastGate = null; const { error } = await this.sb.auth.signOut(); if (error) throw error; }); }

  requestPasswordReset(email: string) {
    return this.run(async () => {
      const { error } = await this.sb.functions.invoke('qhub-recover', { body: { email: email.trim().toLowerCase(), movil: true } });
      if (error) throw await mapRecoverError(error);
    });
  }

  openLinkSession(link: { accessToken: string; refreshToken: string }) {
    return this.run(async () => {
      this.lastGate = null;   // sesión nueva: la puerta de solo-clientes se vuelve a verificar
      const { error } = await this.sb.auth.setSession({ access_token: link.accessToken, refresh_token: link.refreshToken });
      if (error) throw error;
    });
  }

  updatePassword(password: string) {
    return this.run(async () => { const { error } = await this.sb.auth.updateUser({ password }); if (error) throw error; });
  }
}

/** Errores de la Edge Function de recuperación: nunca revela si el correo existe. */
async function mapRecoverError(error: unknown): Promise<unknown> {
  if (isFetchError(error)) return networkFailure();
  const status = (error as { context?: { status?: number } }).context?.status;
  if (status === 400) return validationFailure('Escribe un correo válido.', { email: 'Escribe un correo válido.' });
  if (status === 429) return rateLimitedFailure();
  return serverFailure();
}

/** Mapea los errores de la Edge Function de registro a Failure. No reutiliza supabase-invoker: lee error.context.status/json(). */
async function mapRegistroError(error: unknown): Promise<unknown> {
  if (isFetchError(error)) return networkFailure();
  const ctx = (error as { context?: { status?: number; json?: () => Promise<unknown> } }).context;
  const status = ctx?.status;
  if (status === 400) {
    let fields: Record<string, string> = {};
    try {
      const body = (await ctx?.json?.()) as { fields?: Record<string, string> } | null;
      if (body?.fields) fields = Object.fromEntries(Object.entries(body.fields).filter(([, v]) => typeof v === 'string'));
    } catch { /* cuerpo no legible: validación sin campos */ }
    return validationFailure('Revisa los datos ingresados.', fields);
  }
  if (status === 409) {
    let code: string | undefined;
    try { code = ((await ctx?.json?.()) as { error?: string } | null)?.error; } catch { /* cuerpo no legible: se trata como correo ya registrado */ }
    return conflictFailure(code === 'correo_de_plataforma' ? PLATFORM_EMAIL_MESSAGE : 'Ese correo ya está registrado. Inicia sesión o recupera tu contraseña.');
  }
  if (status === 429) return rateLimitedFailure();
  return serverFailure();
}
