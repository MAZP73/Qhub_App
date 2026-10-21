// Manda los avisos nuevos de Qhub (turno llamado, cancelado, no-show, recordatorio…) por push (Expo) y por correo (Brevo).
// Lo llama pg_cron cada ~30 s (ver tool/push_schedule.py). Revisa a quien tuvo un turno vigente o con cambios recientes:
// los avisos de turno viven en la API y el proxy no expone WebSocket. Protegida por PUSH_CRON_SECRET (cabecera x-push-secret).
import { createClient } from "npm:@supabase/supabase-js@2";
import { avisoHtml, enviarBrevo } from "../_shared/aviso_email.ts";
import { chunk, deadTokens, freshNotifications, pushMessages, type Aviso, type PushMessage } from "../_shared/push.ts";
import { apiBase, forgetToken, tokenFor } from "../_shared/qhub.ts";

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const EXPO = "https://exp.host/--/api/v2/push/send";
const WINDOW_MS = 12 * 3600_000;
const RECENT_MS = 15 * 60_000;   // un turno que cambió hace poco (p. ej. cancelado) aún puede tener un aviso por entregar

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_CRON_SECRET");
  if (req.method !== "POST" || !secret || req.headers.get("x-push-secret") !== secret) return json(401, { error: "No autorizado" });
  const base = apiBase();
  if (!base) return json(503, { error: "Sin API" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const since = new Date(Date.now() - WINDOW_MS).toISOString(), recent = new Date(Date.now() - RECENT_MS).toISOString();
  const { data: turnos } = await admin.from("historial_turnos").select("usuario_id, organizacion_id")
    .or(`and(estado.in.(en_espera,atendiendo),creado_en.gte.${since}),actualizado_en.gte.${recent}`);
  const pairs = new Map<string, { userId: string; orgId: string }>();
  for (const t of turnos ?? []) pairs.set(`${t.usuario_id}/${t.organizacion_id}`, { userId: t.usuario_id, orgId: t.organizacion_id });
  if (pairs.size === 0) return json(200, { enviados: 0, correos: 0 });

  const userIds = [...new Set([...pairs.values()].map((p) => p.userId))];
  const orgIds = [...new Set([...pairs.values()].map((p) => p.orgId))];
  const { data: devices } = await admin.from("dispositivos_push").select("usuario_id, token").in("usuario_id", userIds);
  const tokensByUser = new Map<string, string[]>();
  for (const d of devices ?? []) tokensByUser.set(d.usuario_id, [...(tokensByUser.get(d.usuario_id) ?? []), d.token]);
  const { data: orgs } = await admin.from("organizaciones").select("id, nombre").in("id", orgIds);
  const { data: creds } = await admin.from("organizacion_credenciales").select("organizacion_id, qhub_identificador, qhub_password, qhub_api_key").in("organizacion_id", orgIds);
  const names = new Map((orgs ?? []).map((o) => [o.id, o.nombre as string]));
  const credOf = new Map((creds ?? []).map((c) => [c.organizacion_id, { identificador: c.qhub_identificador, password: c.qhub_password, api_key: c.qhub_api_key }]));
  const brevo = Deno.env.get("BREVO_API_KEY") && Deno.env.get("EMAIL_FROM")
    ? { key: Deno.env.get("BREVO_API_KEY")!, from: Deno.env.get("EMAIL_FROM")!, name: Deno.env.get("EMAIL_FROM_NAME") ?? "Qhub" } : null;
  const emailOf = new Map<string, string | null>();

  /** Reclama primero (si dos corridas se cruzan, solo la que logra insertar el aviso lo manda). */
  const claim = async (table: string, userId: string, orgId: string, avisos: Aviso[]): Promise<Set<string>> => {
    const { data } = await admin.from(table).upsert(avisos.map((a) => ({ usuario_id: userId, organizacion_id: orgId, aviso_id: a.id })),
      { onConflict: "usuario_id,organizacion_id,aviso_id", ignoreDuplicates: true }).select("aviso_id");
    return new Set((data ?? []).map((r) => r.aviso_id as string));
  };
  const sentIds = async (table: string, userId: string, orgId: string, ids: string[]): Promise<Set<string>> => {
    if (!ids.length) return new Set();
    const { data } = await admin.from(table).select("aviso_id").eq("usuario_id", userId).eq("organizacion_id", orgId).in("aviso_id", ids);
    return new Set((data ?? []).map((r) => r.aviso_id as string));
  };

  const messages: PushMessage[] = [];
  let correos = 0;
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
      if (!ids.length) continue;
      const orgName = names.get(orgId) ?? "";

      const tokens = tokensByUser.get(userId) ?? [];
      if (tokens.length) {
        const fresh = freshNotifications(list, await sentIds("avisos_push_enviados", userId, orgId, ids), Date.now());
        if (fresh.length) {
          const mine = await claim("avisos_push_enviados", userId, orgId, fresh);
          for (const a of fresh) if (mine.has(a.id)) messages.push(...pushMessages(tokens, a, orgId, orgName));
        }
      }

      if (brevo) {
        const fresh = freshNotifications(list, await sentIds("avisos_correo_enviados", userId, orgId, ids), Date.now());
        if (fresh.length) {
          if (!emailOf.has(userId)) emailOf.set(userId, (await admin.auth.admin.getUserById(userId)).data.user?.email ?? null);
          const to = emailOf.get(userId);
          const mine = to ? await claim("avisos_correo_enviados", userId, orgId, fresh) : new Set<string>();
          for (const a of fresh) {
            if (!to || !mine.has(a.id)) continue;
            const titulo = orgName ? `${orgName}: ${a.mensaje}`.slice(0, 120) : a.mensaje.slice(0, 120);
            if (await enviarBrevo(to, titulo, avisoHtml({ titulo: orgName || "Tu turno en Qhub", mensaje: a.mensaje }), brevo)) correos++;
            else await admin.from("avisos_correo_enviados").delete().eq("usuario_id", userId).eq("organizacion_id", orgId).eq("aviso_id", a.id);   // se reintenta en la próxima corrida
          }
        }
      }
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
  return json(200, { enviados: sent, correos });
});
