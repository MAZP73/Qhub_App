import { parseEnv } from '@/app/env';
import { testEnv } from '@/testing/fakes';

describe('env', () => {
  it('lee valores y exige los obligatorios', () => {
    expect(testEnv.supabaseKey).toBe('sb_publishable_test');
    expect(() => parseEnv({ EXPO_PUBLIC_SUPABASE_URL: 'x' })).toThrow(/EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  });
  it('el .env del móvil no pide ninguna credencial de la API Qhub', () => {
    expect(JSON.stringify(parseEnv({ EXPO_PUBLIC_SUPABASE_URL: 'x', EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: 'y' })).toLowerCase()).not.toMatch(/api_key|qhub_api/);
  });
});
