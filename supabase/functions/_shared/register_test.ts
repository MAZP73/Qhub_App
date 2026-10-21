import { assertEquals } from "jsr:@std/assert@1";
import { confirmLink, parseRegister, qhubBody, qhubUsername } from "./register.ts";

const ok = { email: " Ana@X.CO ", password: "secreto123", nombre: "Ana", apellido: "Gómez", cuenta: { tipo: "empresa", nombre: "Notaría 12", pais: "Ecuador", ciudad: "Quito", zona_horaria: "America/Guayaquil" } };
Deno.test("parseRegister: normaliza y valida", () => {
  const p = parseRegister(ok); assertEquals(p.ok && p.value.email, "ana@x.co");
  assertEquals(parseRegister({ ...ok, password: "corta" }).ok, false);
  assertEquals(parseRegister({ ...ok, password: "sololetras" }).ok, false);
  assertEquals(parseRegister({ ...ok, cuenta: { ...ok.cuenta, ciudad: "" } }).ok, false);
  assertEquals(parseRegister({ ...ok, email: "x" }).ok, false);
});
Deno.test("qhubBody: persona = usuario, empresa lleva nombre_empresa", () => {
  const p = parseRegister(ok); if (!p.ok) throw new Error();
  assertEquals(qhubBody(p.value, "ana").nombre_empresa, "Notaría 12");
  const q = parseRegister({ ...ok, cuenta: { ...ok.cuenta, tipo: "persona" } }); if (!q.ok) throw new Error();
  assertEquals(qhubBody(q.value, "ana").tipo_cuenta, "usuario");
});
Deno.test("qhubUsername y confirmLink", () => {
  assertEquals(qhubUsername("zamiguelangel.zam@gmail.com"), "zamiguelangel.zam");
  assertEquals(qhubUsername("a@x.co", 1, () => 0), "axx1000");
  assertEquals(confirmLink("https://app.co", "t"), "https://app.co/confirmar?token=t");
  assertEquals(confirmLink("javascript:1", "t"), undefined);
  assertEquals(confirmLink("https://x-git-main.vercel.app", "t", "https://qhub-web-psi.vercel.app"), "https://qhub-web-psi.vercel.app/confirmar?token=t");   // vista previa protegida: se usa el sitio público
  assertEquals(confirmLink("http://localhost:5173", "t", "https://qhub-web-psi.vercel.app"), "http://localhost:5173/confirmar?token=t");
});
