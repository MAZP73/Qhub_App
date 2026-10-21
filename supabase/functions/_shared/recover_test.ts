import { assertEquals } from "jsr:@std/assert@1";
import { parseRecover, recoverRedirect } from "./recover.ts";

Deno.test("parseRecover: normaliza el correo y rechaza lo inválido", () => {
  assertEquals(parseRecover({ email: "  Ana@X.CO " }), { email: "ana@x.co", movil: false });
  for (const email of ["", "sin-arroba", "a@b", 5, null]) assertEquals(parseRecover({ email }), null);
  assertEquals(parseRecover(null), null);
});
Deno.test("recoverRedirect: solo http(s)", () => {
  assertEquals(recoverRedirect("http://localhost:8080"), "http://localhost:8080/restablecer");
  assertEquals(recoverRedirect("javascript:1"), undefined);
  assertEquals(recoverRedirect(null), undefined);
});
Deno.test("parseRecover: movil solo con true exacto", () => {
  assertEquals(parseRecover({ email: "ana@x.co", movil: true }), { email: "ana@x.co", movil: true });
  assertEquals(parseRecover({ email: "ana@x.co", movil: "true" }), { email: "ana@x.co", movil: false });
});
