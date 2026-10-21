// Send Email Hook de Supabase Auth: todos los correos de autenticación (confirmar cuenta, invitación, recuperar contraseña,
// enlace mágico, cambio de correo) salen por Brevo, no por el SMTP de Supabase (limitado y lento).
// Secretos: SEND_EMAIL_HOOK_SECRET (el `v1,whsec_…` que da Supabase al crear el hook), BREVO_API_KEY, EMAIL_FROM, EMAIL_FROM_NAME (opcional).
import { Webhook } from "npm:standardwebhooks@1.0.0";
import { type HookPayload, mailsFor, render } from "../_shared/auth_email.ts";
import { TEMPLATES } from "./templates.ts";

const reply = (status: number, error?: string) =>
  new Response(JSON.stringify(error ? { error: { http_code: status, message: error } } : {}), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, "Método no permitido");
  const raw = await req.text();
  const secret = (Deno.env.get("SEND_EMAIL_HOOK_SECRET") ?? "").replace("v1,whsec_", "");
  let payload: HookPayload;
  try { payload = new Webhook(secret).verify(raw, Object.fromEntries(req.headers)) as HookPayload; }
  catch { return reply(401, "Firma inválida"); }

  const key = Deno.env.get("BREVO_API_KEY"), from = Deno.env.get("EMAIL_FROM");
  if (!key || !from) return reply(500, "Falta configurar Brevo");
  const mobile = (payload.email_data.redirect_to ?? "").startsWith("qhub:");
  console.log("auth-email", payload.email_data.email_action_type, "redirect_to=", payload.email_data.redirect_to ?? "(vacío)");
  const mails = mailsFor(payload, Deno.env.get("SUPABASE_URL")!, Deno.env.get("SITE_URL"));
  for (const m of mails) {
    // Si el correo nace en la app móvil (redirect qhub://), se manda la versión pensada para el móvil.
    const t = (mobile && TEMPLATES[`${m.type}_movil`]) || TEMPLATES[m.type];
    if (!t) return reply(400, `Tipo de correo no soportado: ${m.type}`);
    const res = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": key, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ sender: { email: from, name: Deno.env.get("EMAIL_FROM_NAME") ?? "Qhub" }, to: [{ email: m.to }], subject: t.subject, htmlContent: render(t.html, m.link) }),
    }).catch(() => null);
    if (!res || !res.ok) { console.error("Brevo rechazó el envío", res?.status); return reply(502, "No se pudo enviar el correo"); }
  }
  return reply(200);
});
