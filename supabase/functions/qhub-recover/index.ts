// Recuperar la contraseña. Quien es parte de un equipo (y no es su administrador) necesita que el administrador lo apruebe:
// sin permiso se le avisa al administrador y NO se envía el correo; con permiso aprobado se envía y el permiso se gasta.
// La respuesta es siempre la misma (no revela si el correo existe ni a qué equipo pertenece).
import { createClient } from "npm:@supabase/supabase-js@2";
import { MOBILE_REDIRECT, parseRecover, recoverRedirect } from "../_shared/recover.ts";

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
  const p = parseRecover(await req.json().catch(() => null));
  if (!p) return json(400, { error: "Escribe un correo válido." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: estado, error } = await admin.rpc("solicitar_recuperacion", { p_email: p.email });
  if (error) return json(500, { error: "No pudimos procesar la solicitud. Inténtalo de nuevo." });

  if (estado !== "pendiente") {
    const r = await createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!).auth.resetPasswordForEmail(p.email, { redirectTo: p.movil ? MOBILE_REDIRECT : recoverRedirect(req.headers.get("Origin"), Deno.env.get("SITE_URL")) });
    if (r.error?.status === 429) return json(429, { error: "Hay demasiados envíos seguidos. Espera unos minutos." });
  }
  return json(200, { ok: true });
});
