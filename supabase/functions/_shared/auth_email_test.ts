import { assertEquals } from "jsr:@std/assert@1";
import { mailsFor, render, verifyLink } from "./auth_email.ts";

const base = { user: { email: "a@x.co" }, email_data: { token_hash: "h1", redirect_to: "https://app.co/", email_action_type: "signup" } };
Deno.test("verifyLink: arma el enlace de verificación", () => {
  assertEquals(verifyLink("https://p.supabase.co/", "h", "signup", "https://app.co/"), "https://p.supabase.co/auth/v1/verify?token=h&type=signup&redirect_to=https%3A%2F%2Fapp.co%2F");
});
Deno.test("mailsFor: un correo para confirmar cuenta", () => {
  const m = mailsFor(base, "https://p.supabase.co");
  assertEquals(m.length, 1); assertEquals(m[0].to, "a@x.co");
});
Deno.test("mailsFor: cambio de correo seguro manda al actual y al nuevo", () => {
  const m = mailsFor({ user: { email: "a@x.co", new_email: "b@x.co" }, email_data: { token_hash: "h1", token_hash_new: "h2", email_action_type: "email_change" } }, "https://p.supabase.co");
  assertEquals(m.map((x) => x.to), ["a@x.co", "b@x.co"]);
});
Deno.test("mailsFor: el enlace vuelve al sitio público, no a una vista previa", () => {
  const m = mailsFor({ ...base, email_data: { ...base.email_data, redirect_to: "https://x-git-main.vercel.app/invitacion?token=t" } }, "https://p.supabase.co", "https://qhub-web-psi.vercel.app");
  assertEquals(new URL(m[0].link).searchParams.get("redirect_to"), "https://qhub-web-psi.vercel.app/invitacion?token=t");
});
Deno.test("render: sustituye el enlace", () => assertEquals(render("<a href=\"{{ .ConfirmationURL }}\">", "L"), "<a href=\"L\">"));
