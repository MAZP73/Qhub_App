// Reglas de las colas que la API no conoce (descansos, margen del turno «ahora», citas). Puras: sin red ni reloj propio.
// Todas las horas se razonan en la ZONA DE LA COLA (la API da los instantes en UTC). Copia en packages/core/src/queue-rules.ts: mantener igual.

export interface Descanso { desde: string; hasta: string }
export interface Reglas { descansos: Descanso[]; margenAhoraMin: number; anticipacionCitaMin: number; maxCitasActivas: number }
export interface Horario { zona: string; abre: string; cierra: string; dias: number[]; franjaMin: number; turnoMin: number; puestos: number }

export const REGLAS_POR_DEFECTO: Reglas = { descansos: [], margenAhoraMin: 3, anticipacionCitaMin: 5, maxCitasActivas: 3 };

const HM = /^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$/;
export const hmToMin = (v: string): number => { const m = HM.exec(v); return m ? Number(m[1]) * 60 + Number(m[2]) : NaN; };
export const minToHm = (m: number): string => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const clamp = (v: unknown, lo: number, hi: number, d: number) => (typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : d);

/** Reglas de una fila de `cola_reglas` (o `null`: valores por defecto). Descansos mal formados se descartan. */
export function parseReglas(row: Record<string, unknown> | null | undefined): Reglas {
  if (!row) return { ...REGLAS_POR_DEFECTO, descansos: [] };
  const raw = Array.isArray(row.descansos) ? row.descansos : [];
  const descansos = raw.flatMap((d) => {
    const x = d as Partial<Descanso> | null;
    const a = hmToMin(String(x?.desde)), b = hmToMin(String(x?.hasta));
    return Number.isNaN(a) || Number.isNaN(b) || b <= a ? [] : [{ desde: minToHm(a), hasta: minToHm(b) }];
  }).sort((p, q) => hmToMin(p.desde) - hmToMin(q.desde));
  return {
    descansos,
    margenAhoraMin: clamp(row.margen_ahora_min, 0, 60, REGLAS_POR_DEFECTO.margenAhoraMin),
    anticipacionCitaMin: clamp(row.anticipacion_cita_min, 0, 240, REGLAS_POR_DEFECTO.anticipacionCitaMin),
    maxCitasActivas: clamp(row.max_citas_activas, 1, 20, REGLAS_POR_DEFECTO.maxCitasActivas),
  };
}

/** Horario de `GET /colas/{id}/horario` de la API. `null` si falta algo esencial. */
export function parseHorario(j: unknown): Horario | null {
  const o = j as Record<string, unknown> | null;
  if (!o || typeof o !== "object") return null;
  const abre = hmToMin(String(o.hora_apertura)), cierra = hmToMin(String(o.hora_cierre));
  if (Number.isNaN(abre) || Number.isNaN(cierra) || typeof o.zona_horaria !== "string") return null;
  return {
    zona: o.zona_horaria, abre: minToHm(abre), cierra: minToHm(cierra),
    dias: Array.isArray(o.dias_atencion) ? (o.dias_atencion as unknown[]).map(Number).filter((n) => n >= 1 && n <= 7) : [],
    franjaMin: Math.max(1, Number(o.duracion_franja_minutos) || 30), turnoMin: Math.max(1, Number(o.duracion_turno_minutos) || 3), puestos: Math.max(1, Number(o.puestos) || 1),
  };
}

/** Descansos válidos para guardar: dentro del horario, desde < hasta y sin cruzarse. Devuelve el mensaje de error o `null`. */
export function validarDescansos(list: readonly Descanso[], abre: string, cierra: string): string | null {
  if (list.length > 6) return "Máximo 6 descansos.";
  const a0 = hmToMin(abre), c0 = hmToMin(cierra);
  const sorted = list.map((d) => ({ a: hmToMin(d.desde), b: hmToMin(d.hasta) })).sort((x, y) => x.a - y.a);
  for (const [i, d] of sorted.entries()) {
    if (Number.isNaN(d.a) || Number.isNaN(d.b)) return "Elige la hora de inicio y de fin de cada descanso.";
    if (d.b <= d.a) return "El descanso debe terminar después de empezar.";
    if (d.a < a0 || d.b > c0) return `Cada descanso debe estar dentro del horario de atención (${abre}–${cierra}).`;
    if (i > 0 && d.a < sorted[i - 1]!.b) return "Los descansos no pueden cruzarse.";
  }
  return null;
}

export interface Local { fecha: string; min: number; diaIso: number }
/** Fecha, minuto del día y día ISO (1=lunes…7=domingo) de un instante en la zona de la cola. */
export function local(at: Date, zona: string): Local {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: zona, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", weekday: "short" })
    .formatToParts(at).map((x) => [x.type, x.value]));
  const dia = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(String(p.weekday)) + 1;
  return { fecha: `${p.year}-${p.month}-${p.day}`, min: Number(p.hour) * 60 + Number(p.minute), diaIso: dia };
}

const descansoEn = (r: Reglas, desde: number, hasta: number): Descanso | undefined =>
  r.descansos.find((d) => desde < hmToMin(d.hasta) && hasta > hmToMin(d.desde));

export interface AhoraEstado { abierta: boolean; motivo: string | null; reabreA: string | null; descanso: Descanso | null }
const nombreDia = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];

/** ¿Se puede sacar un turno «ahora»? Abierta = día de atención, dentro del horario y fuera de un descanso. */
export function estadoAhora(h: Horario, r: Reglas, now: Date): AhoraEstado {
  const l = local(now, h.zona), abre = hmToMin(h.abre), cierra = hmToMin(h.cierra);
  if (!h.dias.includes(l.diaIso)) return { abierta: false, motivo: `Hoy ${nombreDia[l.diaIso]} no hay atención.`, reabreA: null, descanso: null };
  if (l.min < abre) return { abierta: false, motivo: `Abre hoy a las ${h.abre}.`, reabreA: h.abre, descanso: null };
  if (l.min >= cierra) return { abierta: false, motivo: `Hoy ya cerró (atiende de ${h.abre} a ${h.cierra}).`, reabreA: null, descanso: null };
  const d = r.descansos.find((x) => l.min >= hmToMin(x.desde) && l.min < hmToMin(x.hasta));
  if (d) return { abierta: false, motivo: `Estamos en descanso hasta las ${d.hasta}.`, reabreA: d.hasta, descanso: d };
  return { abierta: true, motivo: null, reabreA: null, descanso: null };
}

/** Espera aproximada (min) de un turno «ahora» con `delante` personas antes: nunca menos que el margen. */
export const esperaAhora = (h: Horario, r: Reglas, delante: number): number =>
  Math.max(r.margenAhoraMin, Math.ceil((Math.max(0, delante) * h.turnoMin) / h.puestos));

/** Tras la espera, ¿todavía hay atención hoy? (cierra antes de que le toque → no se ofrece). */
export function alcanzaHoy(h: Horario, r: Reglas, now: Date, esperaMin: number): boolean {
  const l = local(now, h.zona);
  return l.min + esperaMin < hmToMin(h.cierra);
}

/** Comienzo de la franja que contiene a `at` (la API normaliza igual: mandar 10:07 cae en la de las 10:00). */
export function inicioDeFranja(at: Date, h: Horario): Date {
  const abre = hmToMin(h.abre), l = local(at, h.zona);
  const desde = Math.max(0, Math.floor((l.min - abre) / h.franjaMin)) * h.franjaMin + abre;
  const minutosEnSegundos = at.getUTCSeconds() * 1000 + at.getUTCMilliseconds();
  return new Date(at.getTime() - minutosEnSegundos - (l.min - desde) * 60_000);
}

export type Bloqueo = "pasada" | "pronto" | "descanso";
/** Por qué una franja NO se puede reservar (o `null` si se puede). Solo mira tiempo y descansos; el cupo lo da la API. */
export function bloqueoDeFranja(inicio: Date, fin: Date, h: Horario, r: Reglas, now: Date): Bloqueo | null {
  if (inicio.getTime() <= now.getTime()) return "pasada";
  if (inicio.getTime() < now.getTime() + r.anticipacionCitaMin * 60_000) return "pronto";
  const l = local(inicio, h.zona);
  const dur = Math.max(1, Math.round((fin.getTime() - inicio.getTime()) / 60_000));
  return descansoEn(r, l.min, l.min + dur) ? "descanso" : null;
}

export const MENSAJE_BLOQUEO: Record<Bloqueo, string> = {
  pasada: "Esa hora ya pasó. Elige otra.",
  pronto: "Esa hora es muy pronto para reservarla. Elige una más adelante o saca un turno ahora.",
  descanso: "Esa hora cae en el descanso de la cola. Elige otra.",
};

export interface TurnoActivo { cola_id: string; estado: string; programado: boolean; franja_inicio: string }
const activo = (t: TurnoActivo) => t.estado === "en_espera" || t.estado === "atendiendo";

/** Reglas de «una persona, una cola»: máximo un turno «ahora» activo; citas distintas, sin repetir franja y hasta el tope. */
export function conflictoAlCrear(mios: readonly TurnoActivo[], colaId: string, franjaInicio: string | null, r: Reglas): string | null {
  const enCola = mios.filter((t) => t.cola_id === colaId && activo(t));
  if (franjaInicio === null) {
    return enCola.some((t) => !t.programado) ? "Ya tienes un turno ahora en esta cola. Termínalo o cancélalo para sacar otro." : null;
  }
  const at = Date.parse(franjaInicio);
  if (enCola.some((t) => Date.parse(t.franja_inicio) === at)) return "Ya tienes un turno en esa franja. Elige otra hora.";
  if (enCola.filter((t) => t.programado).length >= r.maxCitasActivas) return `Ya tienes ${r.maxCitasActivas} citas activas en esta cola. Cancela una para reservar otra.`;
  return null;
}
