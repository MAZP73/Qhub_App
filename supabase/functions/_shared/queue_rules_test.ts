import { assertEquals } from "jsr:@std/assert@1";
import { inicioDeFranja, alcanzaHoy, bloqueoDeFranja, conflictoAlCrear, esperaAhora, estadoAhora, local, parseHorario, parseReglas, REGLAS_POR_DEFECTO, validarDescansos, type Horario } from "./queue_rules.ts";

const H: Horario = { zona: "America/Bogota", abre: "09:00", cierra: "18:00", dias: [1, 2, 3, 4, 5], franjaMin: 30, turnoMin: 10, puestos: 1 };
const R = parseReglas({ descansos: [{ desde: "13:00", hasta: "14:00" }] });
// Bogotá = UTC-5 sin horario de verano. Miércoles 2026-11-04.
const at = (hm: string, day = "2026-11-04") => new Date(`${day}T${hm}:00-05:00`);

Deno.test("local: pasa de UTC a la hora de la cola", () => {
  assertEquals(local(new Date("2026-11-04T15:18:00Z"), "America/Bogota"), { fecha: "2026-11-04", min: 10 * 60 + 18, diaIso: 3 });
  assertEquals(local(new Date("2026-11-05T02:00:00Z"), "America/Bogota").fecha, "2026-11-04");
});
Deno.test("parseReglas: valores por defecto, límites y descansos mal formados", () => {
  assertEquals(parseReglas(null), REGLAS_POR_DEFECTO);
  const r = parseReglas({ descansos: [{ desde: "14:00", hasta: "13:00" }, { desde: "x", hasta: "y" }, { desde: "12:00", hasta: "12:30" }], margen_ahora_min: 999, max_citas_activas: 0 });
  assertEquals(r.descansos, [{ desde: "12:00", hasta: "12:30" }]);
  assertEquals([r.margenAhoraMin, r.maxCitasActivas], [60, 1]);
});
Deno.test("parseHorario: lee el horario de la API", () => {
  const h = parseHorario({ zona_horaria: "America/Bogota", hora_apertura: "09:00:00", hora_cierre: "18:00:00", dias_atencion: [1, 2], duracion_franja_minutos: 30, duracion_turno_minutos: 10, puestos: 2 });
  assertEquals(h, { zona: "America/Bogota", abre: "09:00", cierra: "18:00", dias: [1, 2], franjaMin: 30, turnoMin: 10, puestos: 2 });
  assertEquals(parseHorario({ hora_apertura: "x" }), null);
});
Deno.test("validarDescansos", () => {
  assertEquals(validarDescansos([{ desde: "13:00", hasta: "14:00" }], "09:00", "18:00"), null);
  assertEquals(validarDescansos([{ desde: "14:00", hasta: "13:00" }], "09:00", "18:00"), "El descanso debe terminar después de empezar.");
  assertEquals(validarDescansos([{ desde: "08:00", hasta: "09:30" }], "09:00", "18:00")?.includes("dentro del horario"), true);
  assertEquals(validarDescansos([{ desde: "12:00", hasta: "13:30" }, { desde: "13:00", hasta: "14:00" }], "09:00", "18:00"), "Los descansos no pueden cruzarse.");
});
Deno.test("estadoAhora: abierta, descanso, antes de abrir, cerrada y día sin atención", () => {
  assertEquals(estadoAhora(H, R, at("10:18")).abierta, true);
  const d = estadoAhora(H, R, at("13:20"));
  assertEquals([d.abierta, d.reabreA], [false, "14:00"]);
  assertEquals(estadoAhora(H, R, at("08:00")).reabreA, "09:00");
  assertEquals(estadoAhora(H, R, at("18:00")).abierta, false);
  assertEquals(estadoAhora(H, R, at("10:00", "2026-11-07")).motivo, "Hoy sábado no hay atención.");
  assertEquals(estadoAhora(H, R, at("14:00")).abierta, true); // el descanso termina a las 14:00
});
Deno.test("esperaAhora: margen mínimo, turnos por persona y puestos", () => {
  assertEquals(esperaAhora(H, R, 0), 3);
  assertEquals(esperaAhora(H, R, 4), 40);
  assertEquals(esperaAhora({ ...H, puestos: 2 }, R, 4), 20);
});
Deno.test("alcanzaHoy: la espera no puede pasar la hora de cierre", () => {
  assertEquals(alcanzaHoy(H, R, at("17:30"), 20), true);
  assertEquals(alcanzaHoy(H, R, at("17:50"), 20), false);
});
Deno.test("bloqueoDeFranja: pasada, muy pronto, descanso y libre", () => {
  const fr = (hm: string, min = 30) => [at(hm), new Date(at(hm).getTime() + min * 60_000)] as const;
  assertEquals(bloqueoDeFranja(...fr("10:00"), H, R, at("10:18")), "pasada");
  assertEquals(bloqueoDeFranja(...fr("10:30"), H, R, at("10:30")), "pasada");   // reservar a la hora exacta que ya es
  assertEquals(bloqueoDeFranja(...fr("10:30"), H, R, at("10:27")), "pronto");   // faltan 3 min < 5
  assertEquals(bloqueoDeFranja(...fr("13:00"), H, R, at("10:00")), "descanso");
  assertEquals(bloqueoDeFranja(...fr("12:45", 30), H, R, at("10:00")), "descanso"); // se cruza con el descanso
  assertEquals(bloqueoDeFranja(...fr("14:00"), H, R, at("10:00")), null);
  assertEquals(bloqueoDeFranja(...fr("10:30"), H, R, at("10:18")), null);
});
Deno.test("conflictoAlCrear: un turno ahora por cola; citas distintas hasta el tope", () => {
  const t = (o: Record<string, unknown>) => ({ cola_id: "q1", estado: "en_espera", programado: false, franja_inicio: "2026-11-04T15:00:00Z", ...o }) as never;
  assertEquals(conflictoAlCrear([t({})], "q1", null, R)?.startsWith("Ya tienes un turno ahora"), true);
  assertEquals(conflictoAlCrear([t({ cola_id: "q2" })], "q1", null, R), null);          // otra cola
  assertEquals(conflictoAlCrear([t({ estado: "finalizado" })], "q1", null, R), null);   // ya terminó
  assertEquals(conflictoAlCrear([t({ programado: true })], "q1", null, R), null);       // una cita no bloquea el «ahora»
  assertEquals(conflictoAlCrear([t({ programado: true })], "q1", "2026-11-04T16:00:00Z", R), null); // otra cita: permitido
  assertEquals(conflictoAlCrear([t({ programado: true })], "q1", "2026-11-04T15:00:00Z", R), "Ya tienes un turno en esa franja. Elige otra hora.");
  const tres = [0, 1, 2].map((i) => t({ programado: true, franja_inicio: `2026-11-0${5 + i}T15:00:00Z` }));
  assertEquals(conflictoAlCrear(tres, "q1", "2026-11-10T15:00:00Z", R)?.includes("3 citas activas"), true);
});
Deno.test("inicioDeFranja: normaliza a la franja que contiene la hora", () => {
  assertEquals(inicioDeFranja(at("10:07"), H).toISOString(), at("10:00").toISOString());
  assertEquals(inicioDeFranja(at("10:30"), H).toISOString(), at("10:30").toISOString());
  assertEquals(inicioDeFranja(at("10:59"), H).toISOString(), at("10:30").toISOString());
});
