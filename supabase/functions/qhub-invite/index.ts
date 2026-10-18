// Un administrador invita a alguien por correo. La persona recibe un botón; al tocarlo entra, ve la invitación y la acepta.
//   enviar    crea (o actualiza) la invitación pendiente con el perfil que dejó configurado el administrador y manda el correo
//   reenviar  vuelve a enviar el correo de una invitación pendiente y renueva su vencimiento
// El correo sale por Supabase Auth: invitación si la persona no tiene cuenta; enlace de acceso si ya la tiene.
import { createClient } from "npm:@supabase/supabase-js@2";
import { generatePassword, parseInvite, redirectFor } from "../_shared/invite.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
const SEVEN_DAYS = 7 * 24 * 3600 * 1000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json(401, { error: "Inicia sesión" });

  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const orgId = typeof b?.organizacion_id === "string" ? b.organizacion_id : "";
  if (!/^[0-9a-f-]{36}$/i.test(orgId)) return json(400, { error: "Revisa los datos." });
  const { data: isAdmin } = await asUser.rpc("es_admin_org", { org: orgId });
  if (isAdmin !== true) return json(403, { error: "Solo un administrador puede invitar." });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: org } = await admin.from("organizaciones").select("tipo").eq("id", orgId).maybeSingle();
  if (!org || org.tipo === "persona") return json(403, { error: "Una cuenta personal no tiene equipo." });

  const accion = b?.accion === "reenviar" ? "reenviar" : "enviar";
  let inv: Record<string, unknown> | null = null;
  let passwordSet = false;
  let newPassword: string | null = null;
  let typed = false;                   // la escribió el administrador (ya la vio); si se generó sola, solo la ve la persona

  if (accion === "reenviar") {
    const id = typeof b?.invitacion_id === "string" ? b.invitacion_id : "";
    const { data } = await admin.from("invitaciones").select().eq("id", id).eq("organizacion_id", orgId).is("aceptada_en", null).maybeSingle();
    if (!data) return json(404, { error: "Esa invitación ya no existe." });
    inv = data;
  } else {
    const p = parseInvite(b);
    if (!p.ok) return json(400, { error: p.error });
    const v = p.value;
    const { data: member } = await asUser.rpc("ya_es_miembro", { p_org: orgId, p_email: v.email });
    if (member === true) return json(409, { error: "Esa persona ya es parte del equipo." });
    // Contraseña inicial: solo si la persona aún no tiene cuenta (nunca se cambia la de otra persona). No se guarda en claro en ningún lado;
    // queda marcada en app_metadata (que la persona no puede editar) para que cambiarla después requiera permiso del administrador.
    // Sin contraseña escrita se genera una: toda persona nueva entra con una contraseña que ve al aceptar (no elige la suya).
    const initial = v.password ?? generatePassword();
    {
      const created = await admin.auth.admin.createUser({ email: v.email, password: initial, email_confirm: true,
        user_metadata: { nombre: v.nombre ?? undefined, apellido: v.apellido ?? undefined }, app_metadata: { clave_asignada: true } });
      passwordSet = !created.error;
      newPassword = created.error ? null : initial;
      typed = !!v.password;
    }
    const { data: prev } = await admin.from("invitaciones").select("id").eq("organizacion_id", orgId).ilike("email", v.email).is("aceptada_en", null).maybeSingle();
    const fields = { rol: v.rol, nombre: v.nombre, apellido: v.apellido, cargo: v.cargo, expira_en: new Date(Date.now() + SEVEN_DAYS).toISOString() };
    const q = prev
      ? admin.from("invitaciones").update(fields).eq("id", prev.id).select().single()
      : admin.from("invitaciones").insert({ organizacion_id: orgId, email: v.email, invitada_por: user.id, ...fields }).select().single();
    const { data, error } = await q;
    if (error || !data) return json(500, { error: "No pudimos crear la invitación." });
    inv = data;
    // La persona la verá en la pantalla de la invitación; se borra al aceptar.
    if (newPassword) await admin.from("claves_iniciales").upsert({ invitacion_id: data.id, clave: newPassword });
  }

  // Si se reenvía, se renueva el plazo.
  if (accion === "reenviar") {
    await admin.from("invitaciones").update({ expira_en: new Date(Date.now() + SEVEN_DAYS).toISOString() }).eq("id", inv!.id as string);
    inv!.expira_en = new Date(Date.now() + SEVEN_DAYS).toISOString();
  }

  const email = String(inv!.email);
  const redirectTo = redirectFor(req.headers.get("Origin"), String(inv!.token));
  const meta = { nombre: inv!.nombre ?? undefined, apellido: inv!.apellido ?? undefined };
  let sent = false; let motivo: string | undefined;
  const first = await admin.auth.admin.inviteUserByEmail(email, { redirectTo, data: meta });
  if (!first.error) sent = true;
  else if (first.error.status === 429) motivo = "limite";
  else {
    // Ya tiene cuenta: se le manda un enlace de acceso que lo lleva a la invitación.
    const second = await createClient(url, anon).auth.signInWithOtp({ email, options: { emailRedirectTo: redirectTo, shouldCreateUser: false } });
    if (!second.error) sent = true; else motivo = second.error.status === 429 ? "limite" : "envio";
  }
  await admin.from("invitaciones").update({ enviada_en: sent ? new Date().toISOString() : null }).eq("id", inv!.id as string);
  // Queda en la auditoría (y de ahí en los avisos de la administración).
  await admin.from("auditoria").insert({ organizacion_id: orgId, usuario_id: user.id, accion: accion === "reenviar" ? "invitacion.reenviar" : "invitacion.enviar", entidad: "invitacion", entidad_id: String(inv!.id), detalle: { email, rol: inv!.rol } });
  return json(200, { invitacion: inv, enviado: sent, motivo, clave_asignada: passwordSet && typed });
});
