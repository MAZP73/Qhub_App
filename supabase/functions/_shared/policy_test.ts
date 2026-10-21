import { assert, assertEquals } from "jsr:@std/assert@1";
import { decide, historyRow, ownsTicket, requiresLink, ticketsIn } from "./policy.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const Q = "22222222-2222-4222-8222-222222222222";
const T = "33333333-3333-4333-8333-333333333333";

const ok = (r: Record<string, unknown>) => decide({ organizacion_id: ORG, ...r });

Deno.test("permite lo que hace una persona que saca turno", () => {
  for (
    const [method, path] of [
      ["GET", "/colas"], ["GET", `/colas/${Q}`], ["GET", `/colas/${Q}/horario`], ["GET", `/colas/${Q}/franjas`],
      ["GET", `/colas/${Q}/estado`], ["GET", "/turnos/mios"], ["GET", `/turnos/${T}`],
      ["PATCH", `/turnos/${T}/cancelar`], ["PATCH", `/turnos/${T}/posponer`], ["GET", "/notificaciones"],
      ["PATCH", `/notificaciones/${T}/leida`], ["DELETE", `/notificaciones/${T}`],
    ]
  ) assert(ok({ method, path }).ok, `${method} ${path}`);
});

Deno.test("niega todo lo que es de operación o de administración", () => {
  for (
    const [method, path] of [
      ["PATCH", `/turnos/${T}/atender`], ["PATCH", `/turnos/${T}/finalizar`], ["PATCH", `/turnos/${T}/no-show`],
      ["POST", "/colas"], ["PUT", `/colas/${Q}/horario`], ["DELETE", `/colas/${Q}`], ["PATCH", `/colas/${Q}`],
      ["POST", "/auth/token"], ["POST", "/auth/registro"], ["GET", "/empresas"], ["GET", "/turnos"], ["GET", "/colas/limite"],
      ["GET", "/listo"],
    ]
  ) {
    const d = ok({ method, path });
    assert(!d.ok && d.status === 403, `${method} ${path} debería ser 403`);
  }
});

Deno.test("rutas trucadas", () => {
  for (const path of ["/colas/../empresas", "//colas", "/colas?x=1", "colas", `/turnos/${T}/cancelar/`, "/colas/no-uuid"]) {
    assert(!ok({ method: "GET", path }).ok, path);
  }
  assert(!decide({ organizacion_id: "no-uuid", method: "GET", path: "/colas" }).ok);
  assert(!decide({ method: "GET", path: "/colas" }).ok);
  assert(!ok({ method: 5, path: "/colas" }).ok);
});

Deno.test("query: solo parámetros conocidos y acotados", () => {
  const d = ok({ method: "GET", path: "/turnos/mios", query: { limite: 50, desde: 0 } });
  assert(d.ok);
  assertEquals(d.ok && d.query, { limite: "50", desde: "0" });
  assert(ok({ method: "GET", path: `/colas/${Q}/franjas`, query: { fecha: "2026-10-20" } }).ok);
  assert(!ok({ method: "GET", path: "/colas", query: { cola_id: Q } }).ok);
  assert(!ok({ method: "GET", path: "/turnos/mios", query: { limite: 5000 } }).ok);
  assert(!ok({ method: "GET", path: "/turnos/mios", query: { limite: "x" } }).ok);
  assert(!ok({ method: "GET", path: `/colas/${Q}/franjas`, query: { fecha: "mañana" } }).ok);
  assert(!ok({ method: "GET", path: "/colas", query: { activa: "quizas" } }).ok);
  assert(!ok({ method: "GET", path: "/colas", query: [1] }).ok);
});

Deno.test("POST /turnos: solo cola_id y franja_inicio", () => {
  assert(ok({ method: "POST", path: "/turnos", body: { cola_id: Q } }).ok);
  const d = ok({ method: "POST", path: "/turnos", body: { cola_id: Q, franja_inicio: "2026-10-20T15:00:00.000Z" } });
  assert(d.ok && d.body?.franja_inicio === "2026-10-20T15:00:00.000Z");
  assert(!ok({ method: "POST", path: "/turnos", body: { cola_id: Q, usuario_id: "otro" } }).ok); // no se puede suplantar
  assert(!ok({ method: "POST", path: "/turnos", body: { cola_id: Q, estado: "atendiendo" } }).ok);
  assert(!ok({ method: "POST", path: "/turnos", body: { cola_id: "x" } }).ok);
  assert(!ok({ method: "POST", path: "/turnos", body: { cola_id: Q, franja_inicio: "ayer" } }).ok);
  assert(!ok({ method: "POST", path: "/turnos" }).ok);
});

Deno.test("las operaciones sin cuerpo no lo aceptan", () => {
  assert(!ok({ method: "GET", path: "/colas", body: { a: 1 } }).ok);
  assert(!ok({ method: "PATCH", path: `/turnos/${T}/cancelar`, body: { agente_id: "x" } }).ok);
});

Deno.test("identifica el turno a verificar", () => {
  const d = ok({ method: "PATCH", path: `/turnos/${T}/cancelar` });
  assert(d.ok && d.ticketId === T && d.kind === "ticket_cancel");
});

Deno.test("pertenencia: un turno de otra persona de la misma cuenta no se toca", () => {
  assert(ownsTicket({ usuario_id: "u1" }, "u1"));
  assert(!ownsTicket({ usuario_id: "u2" }, "u1"));
  assert(!ownsTicket(null, "u1"));
  assert(!ownsTicket({}, "u1"));
});

Deno.test("historial: qué turnos se sincronizan", () => {
  assertEquals(ticketsIn("ticket_mine", [{ id: 1 }, { id: 2 }]).length, 2);
  assertEquals(ticketsIn("ticket_create", { id: 1 }).length, 1);
  assertEquals(ticketsIn("queues_list", [{ id: 1 }]).length, 0);
  const row = historyRow("u1", ORG, { id: T, cola_id: Q, numero: 5, estado: "en_espera", franja_inicio: "x" }, "Caja 1");
  assertEquals(row.qhub_turno_id, T);
  assertEquals(row.cola_nombre, "Caja 1");
});

Deno.test("vincularse: ver colas y sacar turno lo exigen; lo propio no", () => {
  for (const k of ["queues_list", "queue_get", "queue_schedule", "queue_slots", "queue_state", "ticket_create"] as const) assert(requiresLink(k), k);
  for (const k of ["ticket_mine", "ticket_get", "ticket_cancel", "ticket_postpone", "notif_list", "notif_read", "notif_delete"] as const) assertEquals(requiresLink(k), false, k);
});

Deno.test("decide: /colas/{id}/ahora lo resuelve el proxy, exige vínculo y devuelve el id de la cola", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const d = decide({ organizacion_id: id, method: "GET", path: `/colas/${id}/ahora` });
  if (!d.ok) throw new Error("debía permitirse");
  assertEquals([d.kind, d.queueId, requiresLink(d.kind)], ["queue_now", id, true]);
  assertEquals(decide({ organizacion_id: id, method: "POST", path: `/colas/${id}/ahora` }).ok, false);
});
