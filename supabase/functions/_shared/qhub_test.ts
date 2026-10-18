import { assertEquals } from "jsr:@std/assert@1";
import { forgetToken, tokenFor } from "./qhub.ts";

const fakeLogin = (calls: { n: number }, expires = 3600): typeof fetch =>
  (() => { calls.n++; return Promise.resolve(new Response(JSON.stringify({ access_token: `tok${calls.n}`, expires_in: expires }), { status: 200 })); }) as typeof fetch;

Deno.test("tokenFor: inicia sesión una vez y devuelve cuánto le queda al token", async () => {
  forgetToken("o1");
  const calls = { n: 0 };
  const a = await tokenFor("o1", "http://api", { identificador: "x", password: "y" }, fakeLogin(calls), 1_000_000);
  assertEquals(a, { token: "tok1", expiresIn: 3600 });
  const b = await tokenFor("o1", "http://api", { identificador: "x", password: "y" }, fakeLogin(calls), 1_000_000 + 600_000);   // 10 min después: sigue vigente, sin otra llamada
  assertEquals(calls.n, 1);
  assertEquals("token" in b && b.token, "tok1");
  assertEquals("expiresIn" in b && b.expiresIn, 3000);
});

Deno.test("tokenFor: renueva cuando faltan menos de 60 s y reporta el error de la API", async () => {
  forgetToken("o2");
  const calls = { n: 0 };
  await tokenFor("o2", "http://api", { identificador: "x", password: "y" }, fakeLogin(calls, 100), 0);
  const r = await tokenFor("o2", "http://api", { identificador: "x", password: "y" }, fakeLogin(calls, 100), 50_000);   // quedan 50 s < 60 s → renueva
  assertEquals(calls.n, 2); assertEquals("token" in r && r.token, "tok2");
  forgetToken("o3");
  const bad = await tokenFor("o3", "http://api", { identificador: "x", password: "mala" }, (() => Promise.resolve(new Response(JSON.stringify({ detail: "Credenciales inválidas" }), { status: 401 }))) as typeof fetch, 0);
  assertEquals(bad, { status: 401, detail: "Credenciales inválidas" });
});
