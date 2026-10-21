import { assertEquals } from "jsr:@std/assert@1";
import { avisoDeTurno, etiquetaTurno, fechaLegible } from "./aviso_turno.ts";

Deno.test("etiquetaTurno: prefijo y número de 3 dígitos", () => { assertEquals(etiquetaTurno("A", 7), "A-007"); assertEquals(etiquetaTurno("PR", 123), "PR-123"); });
Deno.test("fechaLegible: en la zona de la cola y tolera fechas inválidas", () => {
  assertEquals(fechaLegible("2026-11-04T15:30:00Z", "America/Bogota").includes("10:30"), true);
  assertEquals(fechaLegible("no-fecha", "America/Bogota"), "");
  assertEquals(fechaLegible("2026-11-04T15:30:00Z", "Zona/Inexistente"), "");
});
Deno.test("avisoDeTurno: turno ahora y cita", () => {
  const base = { orgName: "Notaría 12", queueName: "Escrituras", prefix: "E", number: 5, slotStart: "2026-11-04T15:30:00Z", zona: "America/Bogota" };
  const ahora = avisoDeTurno({ ...base, scheduled: false });
  assertEquals([ahora.tipo, ahora.titulo], ["turno_creado", "Tu turno es E-005"]);
  const cita = avisoDeTurno({ ...base, scheduled: true });
  assertEquals([cita.tipo, cita.titulo], ["cita_creada", "Reservaste tu cita E-005"]);
  assertEquals(cita.mensaje.includes("10:30"), true);
});
