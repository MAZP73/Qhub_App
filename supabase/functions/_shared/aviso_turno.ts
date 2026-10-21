// Texto del aviso que recibe la persona al sacar un turno o reservar una cita. Puro: sin red.
export interface TurnoCreado { orgName: string; queueName: string; prefix: string; number: number; scheduled: boolean; slotStart: string; zona: string | null }

export const etiquetaTurno = (prefix: string, number: number): string => `${prefix}-${String(number).padStart(3, "0")}`;

/** «mié 4 nov, 10:30» en la zona de la cola (o en la del servidor si no se conoce). */
export function fechaLegible(iso: string, zona: string | null): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  try {
    return new Intl.DateTimeFormat("es-CO", { timeZone: zona ?? undefined, weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d).replace(/\./g, "");
  } catch { return ""; }
}

export function avisoDeTurno(t: TurnoCreado): { tipo: string; titulo: string; mensaje: string } {
  const n = etiquetaTurno(t.prefix, t.number), donde = `${t.orgName} · ${t.queueName}`;
  if (t.scheduled) {
    const cuando = fechaLegible(t.slotStart, t.zona);
    return { tipo: "cita_creada", titulo: `Reservaste tu cita ${n}`, mensaje: `${donde}${cuando ? `. Tu cita es el ${cuando}` : ""}. Puedes cancelarla desde la app cuando quieras.` };
  }
  return { tipo: "turno_creado", titulo: `Tu turno es ${n}`, mensaje: `${donde}. Te avisaremos cuando se acerque tu turno.` };
}
