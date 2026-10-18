// Entrega a un integrante de la organización un token de la API Qhub usando la credencial guardada en el servidor.
// Así la conexión se hace UNA vez (al registrarse) y la contraseña de Qhub nunca vuelve al navegador.
import { createClient } from "npm:@supabase/supabase-js@2";
import { apiBase, tokenFor } from "../_shared/qhub.ts";

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
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json(401, { error: "Inicia sesión" });

  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const orgId = typeof b?.organizacion_id === "string" ? b.organizacion_id : "";
  if (!/^[0-9a-f-]{36}$/i.test(orgId)) return json(400, { error: "organizacion_id inválido" });

  // Solo integrantes activos de esa organización (la regla vive en la base).
  const { data: member } = await asUser.rpc("es_miembro", { org: orgId });
  if (member !== true) return json(403, { error: "No tienes permiso para hacer esto." });

  const base = apiBase();
  if (!base) return json(503, { error: "El servicio no está disponible por ahora. Inténtalo más tarde." });

  const { data: cred } = await createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!)
    .from("organizacion_credenciales").select("qhub_identificador, qhub_password, qhub_api_key").eq("organizacion_id", orgId).maybeSingle();
  if (!cred) return json(404, { error: "sin_conexion" });

  const t = await tokenFor(orgId, base, { identificador: cred.qhub_identificador, password: cred.qhub_password, api_key: cred.qhub_api_key });
  if ("status" in t) return json(t.status === 401 ? 409 : 502, { error: t.status === 401 ? "credencial_invalida" : "No pudimos conectar con Qhub" });
  return json(200, { access_token: t.token, expires_in: t.expiresIn });
});
