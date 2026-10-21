// Registro con confirmación: crear la cuenta NO crea nada. Los datos (con la contraseña cifrada) esperan en `registros_pendientes`
// y se manda un correo por Brevo. Al pulsar el botón del correo se crean las DOS cuentas (la de la web y la de Qhub) y se borra lo pendiente.
//   solicitar   { email, password, nombre, apellido, cuenta: { tipo, nombre, pais, ciudad, zona_horaria } }  -> guarda y envía el correo
//   confirmar   { token }                                                                                    -> crea la cuenta web y la de Qhub
import { createClient } from "npm:@supabase/supabase-js@2";
import { decrypt, encrypt } from "../_shared/crypto.ts";
import { loadKey } from "../_shared/clave.ts";
import { apiBase } from "../_shared/qhub.ts";
import { confirmLink, parseRegister, qhubBody, qhubUsername, sha256Hex, type RegisterInput } from "../_shared/register.ts";
import { render } from "../_shared/auth_email.ts";
import { TEMPLATES } from "../auth-email/templates.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const DIA = 24 * 3600 * 1000;
const NOEXISTE = "00000000-0000-0000-0000-000000000000";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });
  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const key = await loadKey((k) => Deno.env.get(k));
  if (!key) return json(503, { error: "El registro no está disponible por ahora. Inténtalo más tarde." });

  if (b?.accion === "confirmar") {
    const token = typeof b.token === "string" ? b.token.trim() : "";
    if (!/^[0-9a-f]{64}$/.test(token)) return json(404, { error: "Este enlace no es válido o ya venció." });
    const { data: pend } = await admin.from("registros_pendientes").select("id, datos").eq("token_hash", await sha256Hex(token)).gt("expira_en", new Date().toISOString()).maybeSingle();
    if (!pend) return json(404, { error: "Este enlace no es válido o ya venció. Crea tu cuenta de nuevo." });
    let r: RegisterInput;
    try { r = JSON.parse(await decrypt(String(pend.datos), key)) as RegisterInput; } catch { return json(500, { error: "No pudimos abrir tu registro. Crea tu cuenta de nuevo." }); }

    const created = await admin.auth.admin.createUser({
      email: r.email, password: r.password, email_confirm: true,
      user_metadata: { nombre: r.nombre, apellido: r.apellido, cuenta: { tipo: r.cuenta.tipo, nombre: r.cuenta.nombre, pais: r.cuenta.pais, ciudad: r.cuenta.ciudad, zona_horaria: r.cuenta.zona_horaria } },
    });
    if (created.error) {
      await admin.from("registros_pendientes").delete().eq("id", pend.id);
      return json(409, { error: "Ese correo ya está registrado. Inicia sesión o recupera tu contraseña." });
    }
    // La cuenta Qhub, junto con la web. Si la API no responde o ese correo ya existe allá, al entrar se resuelve (la web lo reintenta).
    const base = apiBase();
    if (base) {
      for (let i = 0; i < 3; i++) {
        const res = await fetch(`${base}/auth/registro`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(qhubBody(r, qhubUsername(r.email, i))) }).catch(() => null);
        if (!res || res.status !== 409) { if (!res || !res.ok) console.error("qhub-register: Qhub no creó la cuenta", res?.status); break; }
      }
    }
    await admin.from("registros_pendientes").delete().eq("id", pend.id);
    return json(200, { ok: true });
  }

  // solicitar
  const p = parseRegister(b);
  if (!p.ok) return json(400, { error: p.error });
  const r = p.value;
  const { data: est } = await admin.rpc("estado_de_correo", { p_email: r.email, p_org: NOEXISTE }) as { data: { existe?: boolean } | null };
  if (est?.existe) return json(409, { error: "Ese correo ya está registrado. Inicia sesión o recupera tu contraseña." });
  const { data: prev } = await admin.from("registros_pendientes").select("creado_en").ilike("email", r.email).maybeSingle();
  if (prev && Date.now() - new Date(String(prev.creado_en)).getTime() < 60_000) return json(429, { error: "Ya te enviamos un correo. Espera un minuto para pedir otro." });

  const raw = [...crypto.getRandomValues(new Uint8Array(32))].map((x) => x.toString(16).padStart(2, "0")).join("");
  const link = confirmLink(req.headers.get("Origin"), raw, Deno.env.get("SITE_URL"));
  const brevo = Deno.env.get("BREVO_API_KEY"), from = Deno.env.get("EMAIL_FROM");
  if (!link || !brevo || !from) return json(503, { error: "El registro no está disponible por ahora. Inténtalo más tarde." });

  await admin.from("registros_pendientes").delete().ilike("email", r.email);
  const { data: row, error } = await admin.from("registros_pendientes").insert({
    email: r.email, token_hash: await sha256Hex(raw), datos: JSON.stringify(await encrypt(JSON.stringify(r), key)), expira_en: new Date(Date.now() + DIA).toISOString(),
  }).select("id").single();
  if (error || !row) return json(500, { error: "No pudimos crear tu cuenta. Inténtalo de nuevo." });

  const t = TEMPLATES.signup;
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST", headers: { "api-key": brevo, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ sender: { email: from, name: Deno.env.get("EMAIL_FROM_NAME") ?? "Qhub" }, to: [{ email: r.email }], subject: t.subject, htmlContent: render(t.html, link) }),
  }).catch(() => null);
  if (!res || !res.ok) {
    console.error("qhub-register: Brevo rechazó el envío", res?.status);
    await admin.from("registros_pendientes").delete().eq("id", row.id);
    return json(502, { error: "No pudimos enviar el correo de confirmación. Inténtalo de nuevo." });
  }
  return json(200, { ok: true });
});
