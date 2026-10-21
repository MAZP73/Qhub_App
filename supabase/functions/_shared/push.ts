// Reglas puras de las notificaciones push (sin red): qué avisos son nuevos, cómo se arma el mensaje y qué dispositivos ya no sirven.
export interface Aviso { id: string; mensaje: string; leida: boolean; creada_en: string; tipo_aviso?: string | null; turno_id?: string | null }

/** Un aviso nuevo es uno sin leer, que no se mandó ya y que es reciente (al activar el push no se vuelcan los viejos). */
export function freshNotifications(list: unknown, sent: ReadonlySet<string>, now: number, maxAgeMs = 10 * 60_000): Aviso[] {
  if (!Array.isArray(list)) return [];
  return list.filter((a): a is Aviso => {
    if (!a || typeof a !== "object") return false;
    const n = a as Partial<Aviso>;
    if (typeof n.id !== "string" || typeof n.mensaje !== "string" || n.leida === true || sent.has(n.id)) return false;
    const at = Date.parse(String(n.creada_en));
    return Number.isFinite(at) && now - at <= maxAgeMs && at - now < 60_000;
  });
}

export interface PushMessage { to: string; title: string; body: string; sound: "default"; priority: "high"; channelId: "turnos"; data: Record<string, string> }

export function pushMessages(tokens: readonly string[], aviso: Aviso, orgId: string, orgName: string): PushMessage[] {
  return tokens.map((to) => ({
    to, title: orgName || "Qhub", body: aviso.mensaje.slice(0, 200), sound: "default", priority: "high", channelId: "turnos",
    data: { organizacionId: orgId, avisoId: aviso.id, tipo: aviso.tipo_aviso ?? "" },
  }));
}

/** Tokens que Expo dice que ya no existen (app desinstalada): se borran. `tickets` viene en el mismo orden que `messages`. */
export function deadTokens(messages: readonly { to: string }[], tickets: unknown): string[] {
  if (!Array.isArray(tickets)) return [];
  const out: string[] = [];
  tickets.forEach((t, i) => {
    const r = t as { status?: string; details?: { error?: string } } | null;
    if (r?.status === "error" && r.details?.error === "DeviceNotRegistered" && messages[i]) out.push(messages[i].to);
  });
  return out;
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}
