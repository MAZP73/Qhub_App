// Manda por Brevo los avisos pendientes de las acciones importantes (equipo de la web y cuenta del cliente móvil).
// Lo llama pg_cron cada ~30 s (ver tool/push_schedule.py). Los eventos solo guardan una fila; aquí se reclaman y se envían.
// Protegida por PUSH_CRON_SECRET (cabecera x-push-secret): no la llama ninguna app.
import { createClient } from "npm:@supabase/supabase-js@2";
import { avisoHtml, enlaceDeRuta, enviarBrevo } from "../_shared/aviso_email.ts";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_CRON_SECRET");
  if (req.method !== "POST" || !secret || req.headers.get("x-push-secret") !== secret) return json(401, { error: "No autorizado" });
  const key = Deno.env.get("BREVO_API_KEY"), from = Deno.env.get("EMAIL_FROM");
  if (!key || !from) return json(503, { error: "Falta configurar Brevo" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("reclamar_avisos_correo", { p_limite: 30 });
  if (error) { console.error("qhub-correo reclamar", error.message); return json(500, { error: "No se pudo leer la cola" }); }

  const site = Deno.env.get("SITE_URL");
  let enviados = 0;
  for (const a of (data ?? []) as { origen: string; id: string; email: string; titulo: string; mensaje: string; ruta: string | null }[]) {
    const url = a.origen === "staff" ? enlaceDeRuta(a.ruta, site) : null;
    const html = avisoHtml({ titulo: a.titulo, mensaje: a.mensaje, boton: url ? { texto: "Abrir en Qhub", url } : null });
    const ok = await enviarBrevo(a.email, a.titulo, html, { key, from, name: Deno.env.get("EMAIL_FROM_NAME") ?? "Qhub" });
    if (ok) enviados++;
    else { console.error("Brevo rechazó el aviso", a.origen); await admin.rpc("devolver_aviso_correo", { p_origen: a.origen, p_id: a.id }); }
  }
  return json(200, { enviados });
});
