// Política del proxy móvil → API Qhub. Pura (sin red) para poder probarla.
// El móvil es público: solo puede hacer lo que haría una PERSONA que saca turno. Nada de atender,
// finalizar, no-show, crear/editar colas, empresas ni auth.

export type ProxyRequest = {
  organizacion_id?: unknown;
  method?: unknown;
  path?: unknown;
  query?: unknown;
  body?: unknown;
};

export type Kind =
  | "queues_list" | "queue_get" | "queue_schedule" | "queue_slots" | "queue_state" | "queue_now"
  | "ticket_create" | "ticket_mine" | "ticket_get" | "ticket_cancel" | "ticket_postpone"
  | "notif_list" | "notif_read" | "notif_delete";

export type Decision =
  | { ok: true; kind: Kind; method: string; path: string; query: Record<string, string>; body?: Record<string, unknown>; ticketId?: string; queueId?: string }
  | { ok: false; status: number; message: string };

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ID = "([0-9a-fA-F-]{36})";

const ROUTES: { method: string; re: RegExp; kind: Kind }[] = [
  { method: "GET", re: /^\/colas$/, kind: "queues_list" },
  { method: "GET", re: new RegExp(`^/colas/${ID}$`), kind: "queue_get" },
  { method: "GET", re: new RegExp(`^/colas/${ID}/horario$`), kind: "queue_schedule" },
  { method: "GET", re: new RegExp(`^/colas/${ID}/franjas$`), kind: "queue_slots" },
  { method: "GET", re: new RegExp(`^/colas/${ID}/estado$`), kind: "queue_state" },
  // No es una ruta de la API: la resuelve el proxy (¿se puede sacar turno ahora?, ¿cuánto se espera?).
  { method: "GET", re: new RegExp(`^/colas/${ID}/ahora$`), kind: "queue_now" },
  { method: "POST", re: /^\/turnos$/, kind: "ticket_create" },
  { method: "GET", re: /^\/turnos\/mios$/, kind: "ticket_mine" },
  { method: "GET", re: new RegExp(`^/turnos/${ID}$`), kind: "ticket_get" },
  { method: "PATCH", re: new RegExp(`^/turnos/${ID}/cancelar$`), kind: "ticket_cancel" },
  { method: "PATCH", re: new RegExp(`^/turnos/${ID}/posponer$`), kind: "ticket_postpone" },
  { method: "GET", re: /^\/notificaciones$/, kind: "notif_list" },
  { method: "PATCH", re: new RegExp(`^/notificaciones/${ID}/leida$`), kind: "notif_read" },
  { method: "DELETE", re: new RegExp(`^/notificaciones/${ID}$`), kind: "notif_delete" },
];

const deny = (status: number, message: string): Decision => ({ ok: false, status, message });

function cleanQuery(q: unknown): Record<string, string> | string {
  if (q == null) return {};
  if (typeof q !== "object" || Array.isArray(q)) return "query inválida";
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(q as Record<string, unknown>)) {
    if (v === null || v === undefined) continue;
    const s = String(v);
    switch (k) {
      case "activa":
        if (s !== "true" && s !== "false") return "activa inválida";
        break;
      case "fecha":
        if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return "fecha inválida";
        break;
      case "limite": {
        const n = Number(s);
        if (!Number.isInteger(n) || n < 1 || n > 100) return "limite inválido";
        break;
      }
      case "desde": {
        const n = Number(s);
        if (!Number.isInteger(n) || n < 0) return "desde inválido";
        break;
      }
      default:
        return `parámetro no permitido: ${k}`;
    }
    out[k] = s;
  }
  return out;
}

export function decide(req: ProxyRequest): Decision {
  if (typeof req.organizacion_id !== "string" || !UUID.test(req.organizacion_id)) return deny(400, "organizacion_id inválido");
  const method = typeof req.method === "string" ? req.method.toUpperCase() : "";
  const path = typeof req.path === "string" ? req.path : "";
  if (!path.startsWith("/") || path.includes("..") || path.includes("//") || path.includes("?")) return deny(400, "ruta inválida");

  const route = ROUTES.find((r) => r.method === method && r.re.test(path));
  if (!route) return deny(403, "Operación no permitida desde la app");

  const query = cleanQuery(req.query);
  if (typeof query === "string") return deny(400, query);

  const idMatch = path.match(route.re);
  const ticketId = route.kind.startsWith("ticket_") && idMatch?.[1] ? idMatch[1] : undefined;
  const queueId = route.kind.startsWith("queue_") && idMatch?.[1] ? idMatch[1] : undefined;
  if (idMatch?.[1] && !UUID.test(idMatch[1])) return deny(400, "id inválido");

  let body: Record<string, unknown> | undefined;
  if (route.kind === "ticket_create") {
    const b = req.body;
    if (b == null || typeof b !== "object" || Array.isArray(b)) return deny(400, "cuerpo inválido");
    const { cola_id, franja_inicio, ...rest } = b as Record<string, unknown>;
    if (Object.keys(rest).length > 0) return deny(400, "campos no permitidos en el cuerpo");
    if (typeof cola_id !== "string" || !UUID.test(cola_id)) return deny(400, "cola_id inválido");
    if (franja_inicio !== undefined && franja_inicio !== null && (typeof franja_inicio !== "string" || Number.isNaN(Date.parse(franja_inicio)))) {
      return deny(400, "franja_inicio inválida");
    }
    body = { cola_id, ...(franja_inicio ? { franja_inicio } : {}) };
  } else if (req.body != null) {
    return deny(400, "esta operación no admite cuerpo");
  }

  return { ok: true, kind: route.kind, method, path, query, body, ticketId, queueId };
}

/** La API filtra por cuenta, no por persona: la pertenencia del turno se verifica aquí. */
export function ownsTicket(ticket: unknown, userId: string): boolean {
  return typeof ticket === "object" && ticket !== null && (ticket as Record<string, unknown>).usuario_id === userId;
}

export function historyRow(userId: string, orgId: string, t: Record<string, unknown>, queueName?: string) {
  return {
    usuario_id: userId,
    organizacion_id: orgId,
    qhub_turno_id: t.id,
    qhub_cola_id: t.cola_id,
    cola_nombre: queueName ?? null,
    numero: t.numero ?? null,
    estado: t.estado,
    franja_inicio: t.franja_inicio ?? null,
  };
}

/** Qué turnos de una respuesta hay que sincronizar con el historial. */
export function ticketsIn(kind: Kind, body: unknown): Record<string, unknown>[] {
  if (kind === "ticket_mine" && Array.isArray(body)) return body as Record<string, unknown>[];
  if (["ticket_create", "ticket_get", "ticket_cancel", "ticket_postpone"].includes(kind) && body && typeof body === "object") {
    return [body as Record<string, unknown>];
  }
  return [];
}

/** Ver las colas de una organización y sacar turno exige estar vinculado a ella (o haber sido su cliente antes). Lo propio —mis turnos, avisos— no. */
const NEEDS_LINK: ReadonlySet<Kind> = new Set<Kind>(["queues_list", "queue_get", "queue_schedule", "queue_slots", "queue_state", "queue_now", "ticket_create"]);
export const requiresLink = (kind: Kind): boolean => NEEDS_LINK.has(kind);
