import { assertEquals } from "jsr:@std/assert@1";
import { parseRegistro } from "./registro.ts";

Deno.test("parseRegistro: acepta y normaliza un registro válido", () => {
  const r = parseRegistro({ email: "  Ana@Correo.CO ", password: "clave1234", nombre: "  Ana  ", apellido: " Pérez " });
  assertEquals(r, { ok: true, value: { email: "ana@correo.co", password: "clave1234", nombre: "Ana", apellido: "Pérez" } });
});

Deno.test("parseRegistro: errores usan las claves first/last (no nombre/apellido)", () => {
  const r = parseRegistro({ email: "no-valido", password: "123", nombre: "", apellido: "A" });
  if (r.ok) throw new Error("debería fallar");
  assertEquals(Object.keys(r.fields).sort(), ["email", "first", "last", "password"]);
});

Deno.test("parseRegistro: rechaza contraseña corta, sin números o con el correo dentro", () => {
  assertEquals((parseRegistro({ email: "ana@x.co", password: "corta", nombre: "Ana", apellido: "Paz" }) as { ok: false }).ok, false);
  assertEquals((parseRegistro({ email: "ana@x.co", password: "sololetras", nombre: "Ana", apellido: "Paz" }) as { ok: false }).ok, false);
  const r = parseRegistro({ email: "anita@x.co", password: "anita12345", nombre: "Ana", apellido: "Paz" });
  assertEquals(r.ok, false);
});

Deno.test("parseRegistro: acepta contraseña válida mixta", () => {
  assertEquals(parseRegistro({ email: "ana@x.co", password: "abcd1234", nombre: "Ana", apellido: "Paz" }).ok, true);
});

Deno.test("parseRegistro: nombres solo letras, con tildes, apóstrofos y guiones", () => {
  assertEquals(parseRegistro({ email: "ana@x.co", password: "abcd1234", nombre: "O'Neil", apellido: "De-la Cruz" }).ok, true);
  assertEquals((parseRegistro({ email: "ana@x.co", password: "abcd1234", nombre: "An4", apellido: "Paz" }) as { ok: false }).ok, false);
});

Deno.test("parseRegistro: body nulo falla con todos los campos", () => {
  const r = parseRegistro(null);
  if (r.ok) throw new Error("debería fallar");
  assertEquals(Object.keys(r.fields).sort(), ["email", "first", "last", "password"]);
});
