// Entrar con solo el código de una invitación. El código (24 bytes aleatorios) es un secreto igual de fuerte que el botón del correo:
// quien lo tiene recibió la invitación. Si es vigente, se le devuelve un token de un solo uso para abrir sesión con el correo invitado.
// La respuesta es la misma (404) para un código que no existe, ya se aceptó o venció.
import { createClient } from "npm:@supabase/supabase-js@2";

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
  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const codigo = typeof b?.codigo === "string" ? b.codigo.trim() : "";
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(codigo)) return json(404, { error: "Ese código no es válido o ya venció." });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: inv } = await admin.from("invitaciones").select("email").eq("token", codigo).is("aceptada_en", null).gt("expira_en", new Date().toISOString()).maybeSingle();
  if (!inv) return json(404, { error: "Ese código no es válido o ya venció." });

  const link = await admin.auth.admin.generateLink({ type: "magiclink", email: String(inv.email) });
  const hash = link.data?.properties?.hashed_token;
  if (link.error || !hash) return json(502, { error: "No pudimos abrir la invitación. Inténtalo de nuevo." });
  return json(200, { token_hash: hash });
});
