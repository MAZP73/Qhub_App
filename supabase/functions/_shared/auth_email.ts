import { withSite } from "./site.ts";
// Reglas puras del correo de autenticación (sin red): a quién va, con qué enlace y con qué plantilla.
export interface HookPayload {
  user: { email: string; new_email?: string };
  email_data: { token_hash: string; token_hash_new?: string; redirect_to?: string; email_action_type: string };
}
export interface Mail { to: string; type: string; link: string }

/** Enlace de verificación de Supabase Auth: confirma y redirige a la app. */
export function verifyLink(supabaseUrl: string, tokenHash: string, type: string, redirectTo?: string): string {
  const u = new URL(`${supabaseUrl.replace(/\/$/, "")}/auth/v1/verify`);
  u.searchParams.set("token", tokenHash);
  u.searchParams.set("type", type);
  if (redirectTo) u.searchParams.set("redirect_to", redirectTo);
  return u.toString();
}

/** Los correos que hay que mandar para un evento. El cambio de correo seguro manda uno al actual y otro al nuevo. */
export function mailsFor(p: HookPayload, supabaseUrl: string, site?: string | null): Mail[] {
  const { user, email_data: d } = p;
  const type = d.email_action_type;
  const link = (hash: string) => verifyLink(supabaseUrl, hash, type, withSite(d.redirect_to, site));
  if (type === "email_change") {
    const out: Mail[] = [];
    if (d.token_hash) out.push({ to: user.email, type, link: link(d.token_hash) });
    if (d.token_hash_new && user.new_email) out.push({ to: user.new_email, type, link: link(d.token_hash_new) });
    return out;
  }
  return [{ to: user.email, type, link: link(d.token_hash) }];
}

export const render = (html: string, link: string) => html.replaceAll("{{ .ConfirmationURL }}", link);
