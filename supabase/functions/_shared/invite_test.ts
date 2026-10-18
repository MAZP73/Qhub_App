import { assertEquals } from "jsr:@std/assert@1";
import { generatePassword, parseInvite, redirectFor } from "./invite.ts";

Deno.test("parseInvite: normaliza el correo y acepta el perfil opcional", () => {
  const r = parseInvite({ email: "  Carla@Mail.COM ", rol: "agente", nombre: " Carla  María ", apellido: "Mena", cargo: "" });
  assertEquals(r, { ok: true, value: { email: "carla@mail.com", rol: "agente", nombre: "Carla María", apellido: "Mena", cargo: null, password: null } });
});
Deno.test("parseInvite: rechaza correos, roles y nombres inválidos", () => {
  for (const email of ["", "sin-arroba", "a@b", "a@@b.co", "a b@x.co"]) assertEquals(parseInvite({ email, rol: "agente" }).ok, false);
  assertEquals(parseInvite({ email: "a@x.co", rol: "propietario" }).ok, false);
  assertEquals(parseInvite({ email: "a@x.co", rol: "admin", nombre: "R2D2" }).ok, false);
  assertEquals(parseInvite(null).ok, false);
});
Deno.test("redirectFor: solo http(s) y con el código codificado", () => {
  assertEquals(redirectFor("http://localhost:8080", "a b"), "http://localhost:8080/invitacion?token=a%20b");
  assertEquals(redirectFor("javascript:alert(1)", "x"), undefined);
  assertEquals(redirectFor(null, "x"), undefined);
});
Deno.test("parseInvite: contraseña inicial opcional, con reglas mínimas", () => {
  const ok = parseInvite({ email: "a@x.co", rol: "agente", password: "Taza-azul-77" });
  assertEquals(ok.ok && ok.value.password, "Taza-azul-77");
  for (const password of ["corta1", "sinnumeros", "12345678", "x".repeat(73) + "1", "carlos-123"]) assertEquals(parseInvite({ email: "carlos@x.co", rol: "agente", password }).ok, false);
});
Deno.test("generatePassword: cumple las reglas de contraseña y cambia cada vez", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 40; i++) {
    const p = generatePassword();
    assertEquals(p.length, 14);
    assertEquals(parseInvite({ email: "zz@x.co", rol: "agente", password: p }).ok, true);
    seen.add(p);
  }
  assertEquals(seen.size, 40);
});
