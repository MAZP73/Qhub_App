// Cliente mínimo de la API Qhub para las Edge Functions (solo servidor).
export type QhubCredential = { identificador?: string | null; password?: string | null; api_key?: string | null };

type Cached = { token: string; exp: number };
const tokens = new Map<string, Cached>();

export function apiBase(): string | null {
  const v = Deno.env.get("QHUB_API_BASE_URL")?.trim();
  return v ? v.replace(/\/+$/, "") : null;
}

export async function login(base: string, cred: QhubCredential, fetchFn: typeof fetch = fetch): Promise<{ token: string; expiresIn: number } | { status: number; detail: string }> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  let body: string | undefined;
  if (cred.api_key) headers["X-Api-Key"] = cred.api_key;
  else body = JSON.stringify({ identificador: cred.identificador, password: cred.password });
  const res = await fetchFn(`${base}/auth/token`, { method: "POST", headers, body });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) return { status: res.status, detail: typeof json?.detail === "string" ? json.detail : "No se pudo iniciar sesión en Qhub" };
  return { token: json.access_token as string, expiresIn: Number(json.expires_in ?? 3600) };
}

/** Token de la organización, en caché hasta 60 s antes de vencer (no hay refresh en la API). */
export async function tokenFor(orgId: string, base: string, cred: QhubCredential, fetchFn: typeof fetch = fetch, now = Date.now()) {
  const hit = tokens.get(orgId);
  if (hit && hit.exp - 60_000 > now) return { token: hit.token, expiresIn: Math.floor((hit.exp - now) / 1000) };
  const res = await login(base, cred, fetchFn);
  if ("status" in res) return res;
  tokens.set(orgId, { token: res.token, exp: now + res.expiresIn * 1000 });
  return { token: res.token, expiresIn: res.expiresIn };
}

export const forgetToken = (orgId: string) => tokens.delete(orgId);
