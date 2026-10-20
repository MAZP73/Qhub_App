// Puerta de la app móvil: ¿la sesión actual es de un cliente? La app es solo para clientes; el staff (web) y los correos
// inexistentes no entran. El correo NUNCA llega por el cuerpo: se lee de la propia sesión del que llama (verify_jwt=true),
// y la decisión la toma la base con service_role (es_correo_cliente), no el cliente.
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

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user?.email) return json(401, { error: "Inicia sesión" });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: cliente } = await admin.rpc("es_correo_cliente", { p_email: user.email });
  return json(200, { cliente: cliente === true });
});
