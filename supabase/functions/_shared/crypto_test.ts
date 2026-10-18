import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import { decrypt, encrypt, importKey, type Envelope } from "./crypto.ts";

const keyB64 = () => btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))));

Deno.test("encrypt/decrypt: ida y vuelta devuelve el mismo texto", async () => {
  const key = keyB64();
  const env = await encrypt("Taza-azul-77", key);
  assertEquals(env.v, 1);
  assertEquals(await decrypt(env, key), "Taza-azul-77");
  assertEquals(await decrypt(JSON.stringify(env), key), "Taza-azul-77");   // acepta el JSON en texto
});

Deno.test("encrypt: el IV cambia en cada cifrado", async () => {
  const key = keyB64();
  const a = await encrypt("misma clave", key);
  const b = await encrypt("misma clave", key);
  assertNotEquals(a.iv, b.iv);
  assertNotEquals(a.d, b.d);
});

Deno.test("decrypt: con la clave equivocada falla", async () => {
  const env = await encrypt("secreto", keyB64());
  await assertRejects(() => decrypt(env, keyB64()));
});

Deno.test("decrypt: rechaza un sobre inválido", async () => {
  await assertRejects(() => decrypt({ v: 2, iv: "x", d: "y" } as unknown as Envelope, keyB64()));
});

Deno.test("importKey: rechaza una clave que no decodifica a 32 bytes", async () => {
  await assertRejects(() => importKey(btoa("corta")));
  await assertRejects(() => importKey(btoa(String.fromCharCode(...new Uint8Array(16)))));
});
