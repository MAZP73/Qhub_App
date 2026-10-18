// Intermediario entre la app móvil (pública) y la API Qhub.
// La app autentica a la PERSONA con Supabase Auth; esta función usa la credencial de la ORGANIZACIÓN
// (que nunca sale del servidor) y actúa como esa persona: X-Usuario-Id = id de Supabase, rol "cliente".
import { createClient } from "npm:@supabase/supabase-js@2";
import { decide, historyRow, ownsTicket, ticketsIn } from "../_shared/policy.ts";
import { apiBase, forgetToken, tokenFor } from "../_shared/qhub.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
/** Respuesta "normal" de la función: el estado de la API viaja en el sobre, así el cliente no lo confunde con un fallo de la función. */
const envelope = (status: number, body: unknown) => json(200, { status, body });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "Método no permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  const asUser = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json(401, { error: "Inicia sesión" });

  const input = await req.json().catch(() => null);
  if (!input) return json(400, { error: "JSON inválido" });
  const d = decide(input);
  if (!d.ok) return json(d.status, { error: d.message });

  const orgId = input.organizacion_id as string;
  const admin = createClient(url, service);

  // La organización debe estar publicada, activa y vinculada.
  const { data: org } = await admin.from("organizaciones").select("id, publica, activa").eq("id", orgId).maybeSingle();
  if (!org || !org.publica || !org.activa) return json(404, { error: "Organización no disponible" });
  const { data: cred } = await admin.from("organizacion_credenciales").select("qhub_identificador, qhub_password, qhub_api_key").eq("organizacion_id", orgId).maybeSingle();
  if (!cred) return json(503, { error: "Esta organización todavía no está disponible." });

  // Clientes bloqueados por la administración de la organización no pueden sacar turnos.
  if (d.kind === "ticket_create") {
    const { data: blocked } = await admin.from("clientes_bloqueados").select("usuario_id").eq("organizacion_id", orgId).eq("usuario_id", user.id).maybeSingle();
    if (blocked) return envelope(403, { detail: "No puedes sacar turnos en esta organización. Contáctala para resolverlo." });
  }

  const base = apiBase();
  if (!base) return json(503, { error: "El servicio no está disponible por ahora. Inténtalo más tarde." });

  const credential = { identificador: cred.qhub_identificador, password: cred.qhub_password, api_key: cred.qhub_api_key };

  const call = async (method: string, path: string, query: Record<string, string>, body?: unknown, retry = true): Promise<{ status: number; data: unknown }> => {
    const t = await tokenFor(orgId, base, credential);
    if ("status" in t) return { status: 503, data: { detail: "No pudimos conectar con Qhub" } };
    const qs = new URLSearchParams(query).toString();
    const res = await fetch(`${base}${path}${qs ? `?${qs}` : ""}`, {
      method,
      headers: {
        Authorization: `Bearer ${t.token}`,
        "X-Usuario-Id": user.id,
        "X-Usuario-Rol": "cliente",
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (res.status === 401 && retry) {
      forgetToken(orgId);
      return call(method, path, query, body, false);
    }
    const text = await res.text();
    let data: unknown = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = { detail: "Respuesta inesperada" }; }
    return { status: res.status, data };
  };

  try {
    // Cancelar / posponer: la API valida la cuenta, no la persona → se verifica aquí que el turno sea suyo.
    if (d.kind === "ticket_cancel" || d.kind === "ticket_postpone" || d.kind === "ticket_get") {
      const own = await call("GET", `/turnos/${d.ticketId}`, {});
      if (own.status !== 200 || !ownsTicket(own.data, user.id)) return envelope(404, { detail: "No encontramos ese turno" });
      if (d.kind === "ticket_get") {
        await syncHistory(admin, user.id, orgId, [own.data as Record<string, unknown>]);
        return envelope(200, own.data);
      }
    }

    const res = await call(d.method, d.path, d.query, d.body);

    if (res.status >= 200 && res.status < 300) {
      let queueName: string | undefined;
      if (d.kind === "ticket_create" && d.body?.cola_id) {
        const q = await call("GET", `/colas/${d.body.cola_id}`, {});
        queueName = (q.data as Record<string, unknown> | null)?.nombre as string | undefined;
      }
      const tickets = ticketsIn(d.kind, res.data).filter((t) => ownsTicket(t, user.id));
      await syncHistory(admin, user.id, orgId, tickets, queueName);
      // /turnos/mios ya viene filtrado por persona; se devuelve tal cual.
    }
    return envelope(res.status, res.data);
  } catch (e) {
    console.error("qhub-proxy", e);
    return json(502, { error: "No pudimos conectar con Qhub" });
  }
});

async function syncHistory(admin: ReturnType<typeof createClient>, userId: string, orgId: string, tickets: Record<string, unknown>[], queueName?: string) {
  if (tickets.length === 0) return;
  const rows = tickets.map((t) => historyRow(userId, orgId, t, queueName));
  const { error } = await admin.from("historial_turnos").upsert(rows, { onConflict: "organizacion_id,qhub_turno_id", ignoreDuplicates: false });
  if (error) console.error("historial", error.message);
}
