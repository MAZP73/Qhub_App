// Intermediario entre la app móvil (pública) y la API Qhub.
// La app autentica a la PERSONA con Supabase Auth; esta función usa la credencial de la ORGANIZACIÓN
// (que nunca sale del servidor) y actúa como esa persona: X-Usuario-Id = id de Supabase, rol "cliente".
import { createClient } from "npm:@supabase/supabase-js@2";
import { decide, historyRow, ownsTicket, requiresLink, ticketsIn } from "../_shared/policy.ts";
import { apiBase, forgetToken, tokenFor } from "../_shared/qhub.ts";
import {
  alcanzaHoy, bloqueoDeFranja, conflictoAlCrear, esperaAhora, estadoAhora, inicioDeFranja, local, MENSAJE_BLOQUEO, parseHorario, parseReglas, type Horario, type Reglas, type TurnoActivo,
} from "../_shared/queue_rules.ts";

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

  // Ver las colas y sacar turno exige estar vinculado a la organización (o haber sido ya su cliente).
  if (requiresLink(d.kind)) {
    const { data: linked } = await admin.from("favoritos").select("usuario_id").eq("organizacion_id", orgId).eq("usuario_id", user.id).limit(1).maybeSingle();
    const { data: past } = linked ? { data: null } : await admin.from("historial_turnos").select("id").eq("organizacion_id", orgId).eq("usuario_id", user.id).limit(1).maybeSingle();
    if (!linked && !past) return envelope(403, { detail: "Vincúlate a esta organización para ver sus colas y sacar turno." });
  }

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

    // Reglas propias de la cola (descansos, margen del turno «ahora», citas): no las conoce la API, se aplican aquí.
    const rulesOf = async (queueId: string): Promise<Reglas> => {
      const { data } = await admin.from("cola_reglas").select("*").eq("organizacion_id", orgId).eq("qhub_cola_id", queueId).maybeSingle();
      return parseReglas(data);
    };
    const scheduleOf = async (queueId: string): Promise<Horario | null> => {
      const r = await call("GET", `/colas/${queueId}/horario`, {});
      return r.status === 200 ? parseHorario(r.data) : null;
    };
    const myActive = async (): Promise<TurnoActivo[]> => {
      const r = await call("GET", "/turnos/mios", {});
      return r.status === 200 && Array.isArray(r.data) ? (r.data as TurnoActivo[]) : [];
    };
    /** Cuántas personas hay delante de un turno «ahora»: lo más bajo entre los en espera de la cola y los ocupados de la franja actual. */
    const peopleAhead = async (queueId: string, h: Horario, now: Date): Promise<number> => {
      const [st, fr] = await Promise.all([call("GET", `/colas/${queueId}/estado`, {}), call("GET", `/colas/${queueId}/franjas`, { fecha: local(now, h.zona).fecha })]);
      const waiting = Number((st.data as Record<string, unknown> | null)?.turnos_en_espera ?? 0) || 0;
      const current = Array.isArray(fr.data) ? (fr.data as Record<string, unknown>[]).find((f) => Date.parse(String(f.inicio)) <= now.getTime() && now.getTime() < Date.parse(String(f.fin))) : undefined;
      return current ? Math.min(waiting, Number(current.ocupados) || 0) : waiting;
    };

    if (d.kind === "queue_now") {
      const qid = d.queueId!, now = new Date();
      const [h, rules, mine] = await Promise.all([scheduleOf(qid), rulesOf(qid), myActive()]);
      if (!h) return envelope(503, { detail: "No pudimos consultar el horario de esta cola." });
      const est = estadoAhora(h, rules, now);
      const delante = est.abierta ? await peopleAhead(qid, h, now) : 0;
      const espera = est.abierta ? esperaAhora(h, rules, delante) : null;
      const alcanza = espera === null ? false : alcanzaHoy(h, rules, now, espera);
      return envelope(200, {
        cola_id: qid, abierta: est.abierta && alcanza,
        motivo: est.motivo ?? (alcanza ? null : "Ya no alcanzamos a atenderte hoy. Reserva una cita para otro día."),
        reabre_a: est.reabreA, descanso: est.descanso, delante, espera_min: est.abierta && alcanza ? espera : null,
        ya_tiene_ahora: conflictoAlCrear(mine, qid, null, rules) !== null, descansos: rules.descansos, margen_ahora_min: rules.margenAhoraMin,
      });
    }

    if (d.kind === "ticket_create") {
      const qid = d.body!.cola_id as string, franja = (d.body!.franja_inicio as string | undefined) ?? null, now = new Date();
      const [h, rules, mine] = await Promise.all([scheduleOf(qid), rulesOf(qid), myActive()]);
      let inicio: string | null = franja;
      if (h) {
        if (franja === null) {
          const est = estadoAhora(h, rules, now);
          if (!est.abierta) return envelope(400, { detail: est.motivo });
          if (!alcanzaHoy(h, rules, now, esperaAhora(h, rules, await peopleAhead(qid, h, now)))) return envelope(400, { detail: "Ya no alcanzamos a atenderte hoy. Reserva una cita para otro día." });
        } else {
          const start = inicioDeFranja(new Date(franja), h);
          inicio = start.toISOString();
          const b = bloqueoDeFranja(start, new Date(start.getTime() + h.franjaMin * 60_000), h, rules, now);
          if (b) return envelope(400, { detail: MENSAJE_BLOQUEO[b] });
        }
      }
      const conflicto = conflictoAlCrear(mine.map((t) => ({ ...t, franja_inicio: Number.isNaN(Date.parse(t.franja_inicio)) ? t.franja_inicio : new Date(t.franja_inicio).toISOString() })), qid, inicio, rules);
      if (conflicto) return envelope(409, { detail: conflicto });
    }

    const res = await call(d.method, d.path, d.query, d.body);

    // Las franjas que no se pueden reservar por tiempo o descanso se marcan para que la app las muestre deshabilitadas con el motivo.
    if (d.kind === "queue_slots" && res.status === 200 && Array.isArray(res.data) && d.queueId) {
      const [h, rules] = await Promise.all([scheduleOf(d.queueId), rulesOf(d.queueId)]);
      if (h) {
        const now = new Date();
        return envelope(200, (res.data as Record<string, unknown>[]).map((f) => ({ ...f, bloqueada: bloqueoDeFranja(new Date(String(f.inicio)), new Date(String(f.fin)), h, rules, now) })));
      }
    }

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
