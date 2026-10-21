import { siteOrigin } from "./site.ts";
// Reglas puras del registro con confirmación (sin red): validación de lo que llega y el usuario de Qhub que se propone.
export interface Cuenta { tipo: "persona" | "empresa"; nombre: string; pais: string; ciudad: string; zona_horaria: string }
export interface RegisterInput { email: string; password: string; nombre: string; apellido: string; cuenta: Cuenta }
export type Parsed = { ok: true; value: RegisterInput } | { ok: false; error: string };

const EMAIL = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const str = (v: unknown, min: number, max: number) => typeof v === "string" && v.trim().length >= min && v.trim().length <= max ? v.trim().replace(/\s+/g, " ") : null;

export function parseRegister(b: Record<string, unknown> | null): Parsed {
  const email = typeof b?.email === "string" ? b.email.trim().toLowerCase() : "";
  if (email.length > 254 || !EMAIL.test(email)) return { ok: false, error: "Escribe un correo válido." };
  const pw = b?.password;
  if (typeof pw !== "string" || pw.length < 8 || pw.length > 72 || !/\p{L}/u.test(pw) || !/\d/.test(pw)) return { ok: false, error: "La contraseña debe tener de 8 a 72 caracteres, con letras y números." };
  const nombre = str(b?.nombre, 2, 60), apellido = str(b?.apellido, 2, 60);
  if (!nombre || !apellido) return { ok: false, error: "Escribe tu nombre y apellido." };
  const c = (b?.cuenta ?? {}) as Record<string, unknown>;
  const tipo = c.tipo === "persona" ? "persona" : c.tipo === "empresa" ? "empresa" : null;
  const cn = str(c.nombre, 2, 120), pais = str(c.pais, 2, 80), ciudad = str(c.ciudad, 2, 80), tz = str(c.zona_horaria, 3, 60) ?? "America/Guayaquil";
  if (!tipo || !cn || !pais || !ciudad) return { ok: false, error: "Completa el tipo de cuenta, el nombre, el país y la ciudad." };
  return { ok: true, value: { email, password: pw, nombre, apellido, cuenta: { tipo, nombre: cn, pais, ciudad, zona_horaria: tz } } };
}

/** Usuario de Qhub sacado del correo (3 a 30: minúsculas, números, punto, guion). Del segundo intento en adelante lleva números al final. */
export function qhubUsername(email: string, attempt = 0, random: () => number = Math.random): string {
  const base = (email.split("@")[0] ?? "").toLowerCase().replace(/[^a-z0-9._-]/g, "").replace(/^[^a-z0-9]+/, "").slice(0, 22).padEnd(3, "x");
  return attempt === 0 ? base : `${base}${Math.floor(1000 + random() * 9000)}`;
}

/** Cuerpo de `POST /auth/registro` de la API Qhub. */
export function qhubBody(r: RegisterInput, username: string): Record<string, unknown> {
  const persona = r.cuenta.tipo === "persona";
  return {
    tipo_cuenta: persona ? "usuario" : "empresa", ...(persona ? {} : { nombre_empresa: r.cuenta.nombre }), nombre: r.nombre, apellido: r.apellido,
    nombre_usuario: username, email: r.email, password: r.password, pais: r.cuenta.pais, ciudad: r.cuenta.ciudad, acepto_terminos: true,
  };
}

/** Enlace del botón del correo de registro (ver `siteOrigin`). */
export function confirmLink(origin: string | null, token: string, site?: string | null): string | undefined {
  const o = siteOrigin(origin, site);
  return o ? `${o}/confirmar?token=${encodeURIComponent(token)}` : undefined;
}

export const sha256Hex = async (s: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((x) => x.toString(16).padStart(2, "0")).join("");
