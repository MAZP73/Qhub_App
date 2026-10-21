/** Enlace con que Supabase Auth devuelve a la app (`qhub://auth/callback#access_token=…&type=recovery`). */
export type AuthLink =
  | { kind: 'session'; type: 'recovery' | 'signup' | 'other'; accessToken: string; refreshToken: string }
  | { kind: 'error'; message: string };

const EXPIRED = 'El enlace venció o ya se usó. Pide uno nuevo.';

/** Lee un enlace entrante. `null` = no es de autenticación (se ignora). Los datos llegan en el fragmento (#) o en la query (?). */
export function parseAuthLink(url: string | null | undefined): AuthLink | null {
  if (!url || !/^(qhub|exp[a-z+]*):/i.test(url)) return null;
  const at = url.search(/[?#]/);
  if (at < 0) return null;
  const params = new URLSearchParams(url.slice(at + 1).replace(/#/g, '&'));
  if (params.get('error') || params.get('error_code')) return { kind: 'error', message: EXPIRED };
  const accessToken = params.get('access_token'), refreshToken = params.get('refresh_token');
  if (!accessToken || !refreshToken) return null;
  const t = params.get('type');
  return { kind: 'session', type: t === 'recovery' || t === 'signup' ? t : 'other', accessToken, refreshToken };
}
