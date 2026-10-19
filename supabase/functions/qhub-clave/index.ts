// Lee la clave inicial cifrada y la descifra con CLAVE_INICIAL_KEY (clave del servidor). Dos ramas:
// - invitado: { token } autoriza por el correo invitado (misma condición que la SQL) para verla una sola vez;
// - admin: { orgId, userId } deja al administrador de la organización ver la clave asignada a un miembro de su equipo.
import { createClient } from "npm:@supabase/supabase-js@2";
import { loadKey, readInitialPassword } from "../_shared/clave.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json(401, { error: "Inicia sesión" });

  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const token = typeof b?.token === "string" ? b.token.trim() : "";
  const orgId = typeof b?.orgId === "string" ? b.orgId.trim() : "";
  const userId = typeof b?.userId === "string" ? b.userId.trim() : "";

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let sealed: unknown, error: unknown;
  if (token) {
    ({ data: sealed, error } = await admin.rpc("clave_inicial_cifrada", { p_token: token }));
  } else if (UUID.test(orgId) && UUID.test(userId)) {
    ({ data: sealed, error } = await admin.rpc("clave_inicial_de_miembro", { p_org: orgId, p_usuario: userId }));
  } else {
    return json(400, { error: "Revisa los datos." });
  }
  if (error) { console.error("qhub-clave: fallo al leer la clave cifrada", error); return json(500, { error: "No pudimos leer la clave." }); }

  const r = await readInitialPassword(typeof sealed === "string" && sealed ? sealed : null, await loadKey((k) => Deno.env.get(k)));
  if (r.status === 500) console.error("qhub-clave: no se pudo descifrar la clave inicial (clave ausente/inválida o sobre corrupto).");
  return json(r.status, r.body);
});
