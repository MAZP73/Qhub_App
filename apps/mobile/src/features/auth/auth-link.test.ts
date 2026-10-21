import { parseAuthLink } from './auth-link';

describe('parseAuthLink', () => {
  it('lee la sesión del fragmento y el tipo', () => {
    expect(parseAuthLink('qhub://auth/callback#access_token=a&refresh_token=r&expires_in=3600&type=recovery'))
      .toEqual({ kind: 'session', type: 'recovery', accessToken: 'a', refreshToken: 'r' });
    expect(parseAuthLink('qhub://auth/callback#access_token=a&refresh_token=r&type=signup'))
      .toEqual({ kind: 'session', type: 'signup', accessToken: 'a', refreshToken: 'r' });
  });
  it('también acepta la query y los enlaces de Expo Go', () => {
    expect(parseAuthLink('exp://192.168.1.5:8081/--/auth/callback?x=1#access_token=a&refresh_token=r'))
      .toEqual({ kind: 'session', type: 'other', accessToken: 'a', refreshToken: 'r' });
  });
  it('un enlace vencido se avisa sin mostrar detalles técnicos', () => {
    const l = parseAuthLink('qhub://auth/callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid');
    expect(l).toEqual({ kind: 'error', message: 'El enlace venció o ya se usó. Pide uno nuevo.' });
  });
  it('ignora lo que no es de autenticación', () => {
    for (const u of [null, undefined, '', 'https://qhub.app/#access_token=a&refresh_token=r', 'qhub://auth/callback', 'qhub://org/1?x=1']) expect(parseAuthLink(u)).toBeNull();
  });
});
