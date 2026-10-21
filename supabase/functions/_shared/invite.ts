import { siteOrigin } from "./site.ts";
// Reglas puras de la invitación por correo (sin red): validación de lo que llega y enlace al que vuelve la persona.
export const ROLES = ["admin", "supervisor", "agente", "recepcion"] as const;
export type Rol = typeof ROLES[number];
export interface InviteInput { email: string; rol: Rol; nombre: string | null; apellido: string | null; cargo: string | null; password: string | null }
export type Parsed = { ok: true; value: InviteInput } | { ok: false; error: string };

const EMAIL = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const NAME = /^[\p{L}][\p{L}\p{M}' .-]*$/u;

const optional = (v: unknown, min: number, max: number, what: string): { value: string | null } | { error: string } => {
  if (v === undefined || v === null || (typeof v === "string" && v.trim() === "")) return { value: null };
  if (typeof v !== "string") return { error: `${what} no es válido.` };
  const t = v.trim().replace(/\s+/g, " ");
  if (t.length < min || t.length > max || !NAME.test(t)) return { error: `${what} no es válido.` };
  return { value: t };
};

export function parseInvite(b: Record<string, unknown> | null): Parsed {
  const email = typeof b?.email === "string" ? b.email.trim().toLowerCase() : "";
  if (email.length > 254 || !EMAIL.test(email)) return { ok: false, error: "Escribe un correo válido." };
  const rol = ROLES.find((r) => r === b?.rol);
  if (!rol) return { ok: false, error: "Elige un rol." };
  const n = optional(b?.nombre, 2, 60, "El nombre"), a = optional(b?.apellido, 2, 60, "El apellido"), c = optional(b?.cargo, 2, 80, "El cargo");
  for (const x of [n, a, c]) if ("error" in x) return { ok: false, error: x.error };
  let password: string | null = null;
  if (b?.password !== undefined && b?.password !== null && b?.password !== "") {
    const pw = b.password;
    if (typeof pw !== "string" || pw.length < 8 || pw.length > 72 || !/\p{L}/u.test(pw) || !/\d/.test(pw)) return { ok: false, error: "La contraseña debe tener de 8 a 72 caracteres, con letras y números." };
    if (pw.toLowerCase().includes(email.split("@")[0].toLowerCase()) && email.split("@")[0].length >= 4) return { ok: false, error: "La contraseña no puede incluir el correo." };
    password = pw;
  }
  return { ok: true, value: { email, rol, nombre: (n as { value: string | null }).value, apellido: (a as { value: string | null }).value, cargo: (c as { value: string | null }).value, password } };
}

/** A dónde vuelve la persona al tocar el botón del correo. Solo orígenes http(s); Supabase además exige que estén en su lista de permitidos. */
export function redirectFor(origin: string | null, token: string, site?: string | null): string | undefined {
  const o = siteOrigin(origin, site);
  return o ? `${o}/invitacion?token=${encodeURIComponent(token)}` : undefined;
}

/** Contraseña aleatoria legible (sin 0/O ni 1/l/I) que cumple las reglas: letras, números y un símbolo. */
export function generatePassword(length = 14, random: (n: number) => number = (n) => { const b = new Uint32Array(1); const max = Math.floor(0x100000000 / n) * n; do { crypto.getRandomValues(b); } while (b[0] >= max); return b[0] % n; }): string {
  const sets = ["ABCDEFGHJKLMNPQRSTUVWXYZ", "abcdefghijkmnpqrstuvwxyz", "23456789", "-_.!#"];
  const all = sets.join("");
  const out = sets.map((x) => x[random(x.length)]);
  while (out.length < length) out.push(all[random(all.length)]);
  for (let i = out.length - 1; i > 0; i--) { const j = random(i + 1); [out[i], out[j]] = [out[j], out[i]]; }
  return out.join("");
}
