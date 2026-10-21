import { assertEquals } from "jsr:@std/assert@1";
import { chunk, deadTokens, freshNotifications, pushMessages } from "./push.ts";

const NOW = Date.parse("2026-11-01T12:00:00Z");
const aviso = (id: string, o: Record<string, unknown> = {}) => ({ id, mensaje: "Es tu turno", leida: false, creada_en: "2026-11-01T11:58:00Z", ...o });

Deno.test("freshNotifications: solo sin leer, no enviados y recientes", () => {
  const list = [aviso("a"), aviso("b", { leida: true }), aviso("c"), aviso("d", { creada_en: "2026-11-01T11:00:00Z" }), aviso("e", { creada_en: "no-fecha" }), null, { id: 5 }];
  assertEquals(freshNotifications(list, new Set(["c"]), NOW).map((a) => a.id), ["a"]);
});
Deno.test("freshNotifications: tolera lo que no es lista", () => {
  assertEquals(freshNotifications(null, new Set(), NOW), []);
  assertEquals(freshNotifications({ detail: "x" }, new Set(), NOW), []);
});
Deno.test("pushMessages: un mensaje por dispositivo, con el nombre de la organización", () => {
  const m = pushMessages(["t1", "t2"], { ...aviso("a"), tipo_aviso: "turno_llamado" }, "org1", "Notaría 12");
  assertEquals(m.length, 2);
  assertEquals(m[0], { to: "t1", title: "Notaría 12", body: "Es tu turno", sound: "default", priority: "high", channelId: "turnos", data: { organizacionId: "org1", avisoId: "a", tipo: "turno_llamado" } });
  assertEquals(pushMessages(["t"], aviso("a"), "o", "")[0].title, "Qhub");
});
Deno.test("deadTokens: solo DeviceNotRegistered", () => {
  const msgs = [{ to: "t1" }, { to: "t2" }, { to: "t3" }];
  const tickets = [{ status: "ok" }, { status: "error", details: { error: "DeviceNotRegistered" } }, { status: "error", details: { error: "MessageRateExceeded" } }];
  assertEquals(deadTokens(msgs, tickets), ["t2"]);
  assertEquals(deadTokens(msgs, null), []);
});
Deno.test("chunk: parte en lotes", () => assertEquals(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]));
