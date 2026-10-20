// Reglas puras del registro de un cliente (sin red). Mismas semánticas que validateEmail/validatePassword de @qhub/core,
// reescritas para Deno. tipo_cuenta='cliente' NUNCA llega por el body: lo estampa la Edge Function; aquí solo se valida la forma.
const EMAIL = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;
const NAME = /^[\p{L}][\p{L}\p{M}' .-]*$/u;

/** Los campos usan las claves first/last para que casen con el mapa de errores de AuthScreen (NO nombre/apellido). */
export interface RegistroInput { email: string; password: string; nombre: string; apellido: string }
export type ParsedRegistro =
  | { ok: true; value: RegistroInput }
  | { ok: false; fields: { email?: string; password?: string; first?: string; last?: string } };

function emailError(v: string): string | null {
  const e = v.trim();
  if (e.length < 6 || e.length > 254 || /\s/.test(e) || (e.match(/@/g) ?? []).length !== 1) return "Escribe un correo válido.";
  const [local, domain] = e.split("@") as [string, string];
  if (!local || local.length > 64 || local.startsWith(".") || local.endsWith(".") || local.includes("..") || !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$/.test(local)) return "Escribe un correo válido.";
  return EMAIL.test(e) ? null : "Escribe un correo válido.";
}

function passwordError(v: string, email: string): string | null {
  if (typeof v !== "string" || v.length < 8) return "Usa al menos 8 caracteres.";
  if (v.length > 72) return "Usa 72 caracteres como máximo.";
  if (!/[a-z]/i.test(v) || !/[0-9]/.test(v)) return "Combina letras y números.";
  const local = email.split("@")[0]?.toLowerCase() ?? "";
  if (local.length >= 4 && v.toLowerCase().includes(local)) return "No uses tu correo dentro de la contraseña.";
  return null;
}

function nameError(v: unknown, what: string): string | null {
  const t = typeof v === "string" ? v.trim().replace(/\s+/g, " ") : "";
  if (t.length < 2) return `Escribe ${what} (mínimo 2 letras).`;
  if (t.length > 60) return "Usa 60 caracteres como máximo.";
  if (!NAME.test(t) || /(.)\1{3,}/u.test(t)) return "Usa solo letras, sin números ni símbolos.";
  return null;
}

/** Valida y normaliza el cuerpo del registro. En error devuelve los campos en claves first/last/email/password. */
export function parseRegistro(b: Record<string, unknown> | null): ParsedRegistro {
  const email = typeof b?.email === "string" ? b.email.trim().toLowerCase() : "";
  const password = typeof b?.password === "string" ? b.password : "";
  const nombre = typeof b?.nombre === "string" ? b.nombre.trim().replace(/\s+/g, " ") : "";
  const apellido = typeof b?.apellido === "string" ? b.apellido.trim().replace(/\s+/g, " ") : "";

  const fields: { email?: string; password?: string; first?: string; last?: string } = {};
  const eErr = emailError(email);
  if (eErr) fields.email = eErr;
  const pErr = passwordError(password, email);
  if (pErr) fields.password = pErr;
  const nErr = nameError(b?.nombre, "tu nombre");
  if (nErr) fields.first = nErr;
  const aErr = nameError(b?.apellido, "tu apellido");
  if (aErr) fields.last = aErr;

  if (Object.keys(fields).length > 0) return { ok: false, fields };
  return { ok: true, value: { email, password, nombre, apellido } };
}
