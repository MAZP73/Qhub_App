// Manda por push (Expo) los avisos nuevos de Qhub a los teléfonos registrados. Lo llama pg_cron cada ~30 s (ver tool/push_schedule.py).
// Solo revisa a quien tiene un turno vigente reciente: los avisos de Qhub viven en la API y el proxy no expone WebSocket.
// Protegida por el secreto PUSH_CRON_SECRET (cabecera x-push-secret): no la llama la app.
import { createClient } from "npm:@supabase/supabase-js@2";
import { chunk, deadTokens, freshNotifications, pushMessages, type PushMessage } from "../_shared/push.ts";
import { apiBase, forgetToken, tokenFor } from "../_shared/qhub.ts";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const EXPO = "https://exp.host/--/api/v2/push/send";
const WINDOW_MS = 12 * 3600_000;

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_CRON_SECRET");
  if (req.method !== "POST" || !secret || req.headers.get("x-push-secret") !== secret) return json(401, { error: "No autorizado" });
  const base = apiBase();
  if (!base) return json(503, { error: "Sin API" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: devices } = await admin.from("dispositivos_push").select("usuario_id, token");
  const tokensByUser = new Map<string, string[]>();
  for (const d of devices ?? []) tokensByUser.set(d.usuario_id, [...(tokensByUser.get(d.usuario_id) ?? []), d.token]);
  if (tokensByUser.size === 0) return json(200, { enviados: 0 });

  const since = new Date(Date.now() - WINDOW_MS).toISOString();
  const { data: turnos } = await admin.from("historial_turnos").select("usuario_id, organizacion_id")
    .in("usuario_id", [...tokensByUser.keys()]).in("estado", ["en_espera", "atendiendo"]).gte("creado_en", since);
  const pairs = new Map<string, { userId: string; orgId: string }>();
  for (const t of turnos ?? []) pairs.set(`${t.usuario_id}/${t.organizacion_id}`, { userId: t.usuario_id, orgId: t.organizacion_id });
  const orgIds = [...new Set([...pairs.values()].map((p) => p.orgId))];
  if (orgIds.length === 0) return json(200, { enviados: 0 });

  const { data: orgs } = await admin.from("organizaciones").select("id, nombre").in("id", orgIds);
  const { data: creds } = await admin.from("organizacion_credenciales").select("organizacion_id, qhub_identificador, qhub_password, qhub_api_key").in("organizacion_id", orgIds);
  const names = new Map((orgs ?? []).map((o) => [o.id, o.nombre as string]));
  const credOf = new Map((creds ?? []).map((c) => [c.organizacion_id, { identificador: c.qhub_identificador, password: c.qhub_password, api_key: c.qhub_api_key }]));

  const messages: PushMessage[] = [];
  for (const { userId, orgId } of pairs.values()) {
    const cred = credOf.get(orgId);
    if (!cred) continue;
    try {
      const call = async (retry = true): Promise<unknown> => {
        const t = await tokenFor(orgId, base, cred);
        if ("status" in t) return null;
        const res = await fetch(`${base}/notificaciones?limit=20`, { headers: { Authorization: `Bearer ${t.token}`, "X-Usuario-Id": userId, "X-Usuario-Rol": "cliente" } });
        if (res.status === 401 && retry) { forgetToken(orgId); return call(false); }
        return res.ok ? await res.json().catch(() => null) : null;
      };
      const list = await call();
      const ids = Array.isArray(list) ? list.map((a) => String((a as { id?: unknown })?.id)) : [];
      const { data: sentRows } = ids.length ? await admin.from("avisos_push_enviados").select("aviso_id").eq("usuario_id", userId).eq("organizacion_id", orgId).in("aviso_id", ids) : { data: [] };
      const fresh = freshNotifications(list, new Set((sentRows ?? []).map((r) => r.aviso_id as string)), Date.now());
      if (fresh.length === 0) continue;
      // Se marcan primero: si dos corridas se cruzan, solo la que logra insertar el aviso lo manda.
      const { data: claimed } = await admin.from("avisos_push_enviados")
        .upsert(fresh.map((a) => ({ usuario_id: userId, organizacion_id: orgId, aviso_id: a.id })), { onConflict: "usuario_id,organizacion_id,aviso_id", ignoreDuplicates: true })
        .select("aviso_id");
      const mine = new Set((claimed ?? []).map((r) => r.aviso_id as string));
      for (const a of fresh) if (mine.has(a.id)) messages.push(...pushMessages(tokensByUser.get(userId) ?? [], a, orgId, names.get(orgId) ?? ""));
    } catch (e) { console.error("qhub-push", orgId, e instanceof Error ? e.message : "error"); }
  }

  let sent = 0;
  for (const batch of chunk(messages, 100)) {
    const res = await fetch(EXPO, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json" }, body: JSON.stringify(batch) }).catch(() => null);
    if (!res?.ok) { console.error("Expo rechazó el lote", res?.status); continue; }
    const body = await res.json().catch(() => null);
    sent += batch.length;
    const dead = deadTokens(batch, body?.data);
    if (dead.length) await admin.from("dispositivos_push").delete().in("token", dead);
  }
  return json(200, { enviados: sent });
});
