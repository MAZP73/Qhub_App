import { assertEquals } from "jsr:@std/assert@1";
import { encrypt } from "./crypto.ts";
import { loadKey, readInitialPassword, sealInitialPassword } from "./clave.ts";

const keyB64 = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));

Deno.test("loadKey: ausente -> null; inválida -> null; válida -> la devuelve", async () => {
  assertEquals(await loadKey(() => undefined), null);
  assertEquals(await loadKey(() => btoa("corta")), null);
  const k = keyB64();
  assertEquals(await loadKey(() => k), k);
});

Deno.test("sealInitialPassword: sin clave no cifra (el invite omite el upsert, nunca texto plano)", async () => {
  assertEquals(await sealInitialPassword("Taza-azul-77", null), null);
});

Deno.test("sealInitialPassword: con clave devuelve un sobre cifrado (no texto plano)", async () => {
  const env = await sealInitialPassword("Taza-azul-77", keyB64());
  assertEquals(env?.v, 1);
  assertEquals(typeof env?.d, "string");
});

Deno.test("readInitialPassword: sin sobre autorizado -> 200 { clave: null }", async () => {
  const r = await readInitialPassword(null, keyB64());
  assertEquals(r, { status: 200, body: { clave: null } });
});

Deno.test("readInitialPassword: con sobre y clave válida -> 200 { clave }", async () => {
  const k = keyB64();
  const env = await encrypt("Taza-azul-77", k);
  assertEquals(await readInitialPassword(env, k), { status: 200, body: { clave: "Taza-azul-77" } });
});

Deno.test("readInitialPassword: falta la clave con sobre presente -> 500 controlado", async () => {
  const env = await encrypt("Taza-azul-77", keyB64());
  const r = await readInitialPassword(env, null);
  assertEquals(r.status, 500);
});

Deno.test("readInitialPassword: descifrado falla (clave equivocada) -> 500 controlado", async () => {
  const env = await encrypt("Taza-azul-77", keyB64());
  const r = await readInitialPassword(env, keyB64());
  assertEquals(r.status, 500);
});
