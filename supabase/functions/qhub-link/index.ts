// Un administrador gestiona la conexión de su organización con Qhub y su publicación en la app móvil.
//   conectar     valida la cuenta Qhub (iniciando sesión en la API) y guarda la credencial SOLO en el servidor (no publica)
//   publicar     hace visible la organización en la app móvil (exige estar conectada)
//   despublicar  la oculta del móvil y conserva la conexión
//   desvincular  olvida la credencial (y la oculta)
//   vincular     conectar + publicar (compatibilidad)
import { createClient } from "npm:@supabase/supabase-js@2";
import { apiBase, forgetToken, login } from "../_shared/qhub.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const asUser = createClient(url, anon, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json(401, { error: "Inicia sesión" });

  const b = await req.json().catch(() => null) as Record<string, unknown> | null;
  const orgId = typeof b?.organizacion_id === "string" ? b.organizacion_id : "";
  const ACCIONES = ["conectar", "publicar", "despublicar", "desvincular", "vincular"] as const;
  const accion = ACCIONES.find((a) => a === b?.accion) ?? "vincular";
  if (!/^[0-9a-f-]{36}$/i.test(orgId)) return json(400, { error: "organizacion_id inválido" });

  // Solo un administrador de esa organización (la regla vive en la base: es_admin_org).
  const { data: isAdmin } = await asUser.rpc("es_admin_org", { org: orgId });
  if (isAdmin !== true) return json(403, { error: "Solo un administrador puede publicar la organización" });

  const admin = createClient(url, service);

  if (accion === "publicar" || accion === "despublicar") {
    if (accion === "publicar") {
      const { data: cred } = await admin.from("organizacion_credenciales").select("organizacion_id").eq("organizacion_id", orgId).maybeSingle();
      if (!cred) return json(400, { error: "Primero conecta tu cuenta Qhub" });
    }
    await admin.from("organizaciones").update({ publica: accion === "publicar" }).eq("id", orgId);
    await admin.from("auditoria").insert({ organizacion_id: orgId, usuario_id: user.id, accion: accion === "publicar" ? "organizacion.publicar" : "organizacion.despublicar", entidad: "organizacion", entidad_id: orgId });
    return json(200, { publica: accion === "publicar" });
  }

  if (accion === "desvincular") {
    await admin.from("organizacion_credenciales").delete().eq("organizacion_id", orgId);
    await admin.from("organizaciones").update({ publica: false, vinculada: false }).eq("id", orgId);
    forgetToken(orgId);
    return json(200, { vinculada: false });
  }

  const identificador = typeof b?.identificador === "string" ? b.identificador.trim() : "";
  const password = typeof b?.password === "string" ? b.password : "";
  if (!identificador || !password) return json(400, { error: "Escribe el usuario y la contraseña de Qhub" });

  const base = apiBase();
  if (!base) return json(503, { error: "El servicio no está disponible por ahora. Inténtalo más tarde." });

  const res = await login(base, { identificador, password });
  if ("status" in res) {
    return json(res.status === 401 ? 400 : 502, { error: res.status === 401 ? "Usuario o contraseña de Qhub incorrectos" : "No pudimos conectar con Qhub" });
  }

  const { error } = await admin.from("organizacion_credenciales").upsert({
    organizacion_id: orgId,
    qhub_identificador: identificador,
    qhub_password: password,
    qhub_api_key: null,
    actualizado_en: new Date().toISOString(),
  });
  if (error) return json(500, { error: "No pudimos guardar la vinculación" });
  await admin.from("organizaciones").update(accion === "vincular" ? { publica: true, vinculada: true } : { vinculada: true }).eq("id", orgId);
  forgetToken(orgId);
  return json(200, { vinculada: true, publica: accion === "vincular" });
});
