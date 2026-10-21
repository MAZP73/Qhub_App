import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { avisoHtml, enlaceDeRuta, enlaceSeguro, enviarBrevo, escapeHtml } from "./aviso_email.ts";

Deno.test("escapeHtml: nada del aviso puede inyectar HTML", () => {
  assertEquals(escapeHtml(`<a href="x">&'</a>`), "&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;");
});
Deno.test("avisoHtml: título, mensaje y botón escapados; sin botón si el enlace no es http(s)", () => {
  const h = avisoHtml({ titulo: "Te uniste a <b>Notaría</b>", mensaje: "Hola & bienvenido", boton: { texto: "Abrir", url: "https://qhub.app/equipo" } });
  assertStringIncludes(h, "Te uniste a &lt;b&gt;Notaría&lt;/b&gt;");
  assertStringIncludes(h, "Hola &amp; bienvenido");
  assertStringIncludes(h, 'href="https://qhub.app/equipo"');
  assertEquals(avisoHtml({ titulo: "t", mensaje: "m", boton: { texto: "x", url: "javascript:alert(1)" } }).includes("javascript"), false);
  assertEquals(avisoHtml({ titulo: "t", mensaje: "m" }).includes("<a href"), false);
});
Deno.test("enlaceSeguro y enlaceDeRuta", () => {
  assertEquals(enlaceSeguro("javascript:1"), null);
  assertEquals(enlaceSeguro(null), null);
  assertEquals(enlaceDeRuta("/equipo", "https://qhub.app/"), "https://qhub.app/equipo");
  assertEquals(enlaceDeRuta("/equipo", null), null);
  assertEquals(enlaceDeRuta("//evil.com", "https://qhub.app"), null);
  assertEquals(enlaceDeRuta("/a?b=1", "https://qhub.app"), null);   // solo rutas simples
});
Deno.test("enviarBrevo: manda al destinatario y devuelve si Brevo aceptó", async () => {
  let body: Record<string, unknown> = {};
  const ok = await enviarBrevo("a@x.co", "Asunto", "<p>x</p>", { key: "k", from: "no-reply@qhub.app" }, ((_u: unknown, init: RequestInit) => { body = JSON.parse(String(init.body)); return Promise.resolve(new Response("{}", { status: 201 })); }) as unknown as typeof fetch);
  assertEquals(ok, true);
  assertEquals((body.to as { email: string }[])[0].email, "a@x.co");
  assertEquals(body.subject, "Asunto");
  assertEquals(await enviarBrevo("a@x.co", "A", "h", { key: "k", from: "f" }, (() => Promise.resolve(new Response("{}", { status: 400 }))) as unknown as typeof fetch), false);
  assertEquals(await enviarBrevo("a@x.co", "A", "h", { key: "k", from: "f" }, (() => Promise.reject(new Error("red"))) as unknown as typeof fetch), false);
});
