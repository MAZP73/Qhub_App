import type { SupabaseClient } from '@supabase/supabase-js';
import { CLIENT_GATE_MESSAGE, SupabaseUserRepository } from './supabase-user-repository';
import type { AppUser } from './user';

type InvokeResult = { data: unknown; error: unknown };
const user = (id = 'u1', email = 'cli@x.co') => ({ id, email, user_metadata: { nombre: 'Ana', apellido: 'Paz' } });

class FunctionsFetchError extends Error { constructor() { super('fetch'); this.name = 'FunctionsFetchError'; } }
const fnError = (status: number, body: unknown) => ({
  name: 'FunctionsHttpError',
  context: { status, json: () => Promise.resolve(body) },
});

interface FakeConfig {
  signIn?: InvokeResult;
  setSession?: InvokeResult;
  updateUser?: InvokeResult;
  invoke?: Partial<Record<string, InvokeResult | (() => InvokeResult)>>;
}

function fakeClient(cfg: FakeConfig = {}) {
  const calls = { signOut: 0, signIn: 0, invoke: [] as string[], setSession: [] as unknown[], updateUser: [] as unknown[], bodies: [] as unknown[] };
  let authListener: ((e: string, s: unknown) => void) | null = null;
  let session: unknown = null;

  const sb = {
    auth: {
      signInWithPassword: (_c: unknown) => {
        calls.signIn += 1;
        const r = cfg.signIn ?? { data: { user: user() }, error: null };
        if (!r.error) session = { user: (r.data as { user: unknown }).user };
        return Promise.resolve(r);
      },
      setSession: (t: unknown) => { calls.setSession.push(t); return Promise.resolve(cfg.setSession ?? { data: {}, error: null }); },
      updateUser: (a: unknown) => { calls.updateUser.push(a); return Promise.resolve(cfg.updateUser ?? { data: {}, error: null }); },
      signOut: () => { calls.signOut += 1; session = null; return Promise.resolve({ error: null }); },
      getSession: () => Promise.resolve({ data: { session } }),
      onAuthStateChange: (cb: (e: string, s: unknown) => void) => {
        authListener = cb;
        return { data: { subscription: { unsubscribe: () => {} } } };
      },
    },
    functions: {
      invoke: (name: string, opts?: unknown) => {
        calls.invoke.push(name); calls.bodies.push(opts);
        const r = cfg.invoke?.[name] ?? { data: { cliente: true }, error: null };
        return Promise.resolve(typeof r === 'function' ? r() : r);
      },
    },
  } as unknown as SupabaseClient;

  return { sb, calls, emit: (e: string, s: unknown) => authListener?.(e, s), setSession: (s: unknown) => { session = s; } };
}

const flush = () => new Promise<void>((r) => setTimeout(() => r(), 0));

describe('SupabaseUserRepository: puerta de solo-clientes', () => {
  it('signIn de un cliente devuelve el usuario', async () => {
    const { sb, calls } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: { cliente: true }, error: null } } });
    const r = await new SupabaseUserRepository(sb).signIn('cli@x.co', 'abcd1234');
    expect(r.ok && r.value.id).toBe('u1');
    expect(calls.invoke).toContain('qhub-sesion-cliente');
    expect(calls.signOut).toBe(0);
  });

  it('signIn de un no-cliente cierra sesión y devuelve forbidden con el mensaje de la puerta', async () => {
    const { sb, calls } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: { cliente: false }, error: null } } });
    const r = await new SupabaseUserRepository(sb).signIn('staff@x.co', 'abcd1234');
    expect(!r.ok && r.failure.kind).toBe('forbidden');
    expect(!r.ok && r.failure.message).toBe(CLIENT_GATE_MESSAGE);
    expect(calls.signOut).toBe(1);
  });

  it('signIn con fallo de red en la verificación falla cerrado (network) y cierra sesión', async () => {
    const { sb, calls } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: null, error: new FunctionsFetchError() } } });
    const r = await new SupabaseUserRepository(sb).signIn('cli@x.co', 'abcd1234');
    expect(!r.ok && r.failure.kind).toBe('network');
    expect(calls.signOut).toBe(1);
  });

  it('signIn con error de servidor en la verificación falla cerrado (server) y cierra sesión', async () => {
    const { sb, calls } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: null, error: fnError(500, {}) } } });
    const r = await new SupabaseUserRepository(sb).signIn('cli@x.co', 'abcd1234');
    expect(!r.ok && r.failure.kind).toBe('server');
    expect(calls.signOut).toBe(1);
  });

  it('gateAndReport nunca reporta un usuario no-cliente y cierra sesión en un evento SIGNED_IN', async () => {
    const { sb, calls, emit } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: { cliente: false }, error: null } } });
    const reported: Array<AppUser | null> = [];
    new SupabaseUserRepository(sb).onAuthChange((u) => reported.push(u));
    await flush();                 // getSession() inicial (sin sesión) -> null
    emit('SIGNED_IN', { user: user() });
    await flush();
    expect(reported.every((u) => u === null)).toBe(true);
    expect(calls.signOut).toBeGreaterThanOrEqual(1);
  });

  it('gateAndReport reporta al cliente en un evento SIGNED_IN', async () => {
    const { sb, emit } = fakeClient({ invoke: { 'qhub-sesion-cliente': { data: { cliente: true }, error: null } } });
    const reported: Array<AppUser | null> = [];
    new SupabaseUserRepository(sb).onAuthChange((u) => reported.push(u));
    await flush();
    emit('SIGNED_IN', { user: user() });
    await flush();
    expect(reported.some((u) => u?.id === 'u1')).toBe(true);
  });
});

describe('SupabaseUserRepository: registro', () => {
  const input = { email: 'ana@x.co', password: 'abcd1234', firstName: 'Ana', lastName: 'Paz' };

  it('confirmación OFF: inicia sesión y devuelve el usuario', async () => {
    const { sb, calls } = fakeClient({
      invoke: { 'qhub-registro-cliente': { data: { created: true, needsConfirmation: false }, error: null } },
    });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(r.ok && r.value?.id).toBe('u1');
    expect(calls.signIn).toBe(1);
  });

  it('confirmación ON: devuelve null y no inicia sesión', async () => {
    const { sb, calls } = fakeClient({
      invoke: { 'qhub-registro-cliente': { data: { created: true, needsConfirmation: true }, error: null } },
    });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(r.ok && r.value).toBeNull();
    expect(calls.signIn).toBe(0);
  });

  it('400 -> validation con campos first/last', async () => {
    const { sb } = fakeClient({
      invoke: { 'qhub-registro-cliente': { data: null, error: fnError(400, { error: 'validation', fields: { first: 'x', last: 'y' } }) } },
    });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(!r.ok && r.failure.kind).toBe('validation');
    expect(!r.ok && r.failure.fields).toEqual({ first: 'x', last: 'y' });
  });

  it('409 -> conflict', async () => {
    const { sb } = fakeClient({ invoke: { 'qhub-registro-cliente': { data: null, error: fnError(409, { error: 'ya_registrado' }) } } });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(!r.ok && r.failure.kind).toBe('conflict');
  });

  it('429 -> rate_limited', async () => {
    const { sb } = fakeClient({ invoke: { 'qhub-registro-cliente': { data: null, error: fnError(429, {}) } } });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(!r.ok && r.failure.kind).toBe('rate_limited');
  });

  it('fetch error -> network', async () => {
    const { sb } = fakeClient({ invoke: { 'qhub-registro-cliente': { data: null, error: new FunctionsFetchError() } } });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(!r.ok && r.failure.kind).toBe('network');
  });

  it('5xx -> server', async () => {
    const { sb } = fakeClient({ invoke: { 'qhub-registro-cliente': { data: null, error: fnError(500, {}) } } });
    const r = await new SupabaseUserRepository(sb).signUp(input);
    expect(!r.ok && r.failure.kind).toBe('server');
  });
});

describe('SupabaseUserRepository: recuperar contraseña y enlaces del correo', () => {
  it('requestPasswordReset pide el enlace para la app (movil) con el correo normalizado', async () => {
    const { sb, calls } = fakeClient({ invoke: { 'qhub-recover': { data: { ok: true }, error: null } } });
    const r = await new SupabaseUserRepository(sb).requestPasswordReset(' Cli@X.co ');
    expect(r.ok).toBe(true);
    expect(calls.bodies[0]).toEqual({ body: { email: 'cli@x.co', movil: true } });
  });
  it('requestPasswordReset traduce el límite de envíos', async () => {
    const { sb } = fakeClient({ invoke: { 'qhub-recover': { data: null, error: fnError(429, {}) } } });
    const r = await new SupabaseUserRepository(sb).requestPasswordReset('cli@x.co');
    expect(!r.ok && r.failure.kind).toBe('rate_limited');
  });
  it('openLinkSession abre la sesión con los tokens del enlace', async () => {
    const { sb, calls } = fakeClient();
    const r = await new SupabaseUserRepository(sb).openLinkSession({ accessToken: 'a', refreshToken: 'r' });
    expect(r.ok).toBe(true);
    expect(calls.setSession).toEqual([{ access_token: 'a', refresh_token: 'r' }]);
  });
  it('openLinkSession con enlace inválido falla sin detalles técnicos', async () => {
    const { sb } = fakeClient({ setSession: { data: {}, error: { name: 'AuthApiError', message: 'jwt expired', status: 401 } } });
    const r = await new SupabaseUserRepository(sb).openLinkSession({ accessToken: 'a', refreshToken: 'r' });
    expect(r.ok).toBe(false);
    expect(!r.ok && r.failure.message).not.toMatch(/jwt/i);
  });
  it('updatePassword cambia la contraseña de la sesión', async () => {
    const { sb, calls } = fakeClient();
    const r = await new SupabaseUserRepository(sb).updatePassword('nueva12345');
    expect(r.ok).toBe(true);
    expect(calls.updateUser).toEqual([{ password: 'nueva12345' }]);
  });
});
