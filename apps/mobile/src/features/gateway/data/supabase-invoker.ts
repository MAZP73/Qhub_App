import type { SupabaseClient } from '@supabase/supabase-js';
import { networkFailure, notFoundFailure, rateLimitedFailure, serverFailure, unauthorizedFailure } from '@qhub/core';
import { toProxyPayload, type ProxyInvoker } from './proxy-gateway';

/** Invoca la Edge Function `qhub-proxy`. Los errores de la API vienen dentro del sobre; un fallo de la función misma se traduce a Failure. */
export const supabaseProxyInvoker = (sb: SupabaseClient): ProxyInvoker => async (orgId, request) => {
  const { data, error } = await sb.functions.invoke('qhub-proxy', { body: toProxyPayload(orgId, request) });
  if (error) {
    const status = (error as { context?: { status?: number } }).context?.status;
    if (status === 401) throw unauthorizedFailure();
    if (status === 404) throw notFoundFailure();
    if (status === 429) throw rateLimitedFailure();
    if ((error as Error).name === 'FunctionsFetchError') throw networkFailure();
    throw serverFailure();
  }
  const env = data as { status?: unknown; body?: unknown } | null;
  if (!env || typeof env.status !== 'number') throw serverFailure();
  return { status: env.status, body: env.body ?? null };
};
