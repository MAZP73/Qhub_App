import { optionalEnv, requireEnv, type EnvSource } from '@qhub/core';

/** Variables públicas (`EXPO_PUBLIC_*`). El móvil NO guarda credenciales de la API Qhub: habla con la Edge Function `qhub-proxy`. */
export interface AppEnv { appEnv: string; supabaseUrl: string; supabaseKey: string }

export const parseEnv = (m: EnvSource): AppEnv => ({
  appEnv: optionalEnv(m, 'EXPO_PUBLIC_APP_ENV', 'production'),
  supabaseUrl: requireEnv(m, 'EXPO_PUBLIC_SUPABASE_URL'),
  supabaseKey: requireEnv(m, 'EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY'),
});
