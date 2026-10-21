import { siteOrigin } from "./site.ts";
// Reglas puras de la recuperación de contraseña (sin red).
const EMAIL = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;

export function parseRecover(b: Record<string, unknown> | null): { email: string; movil: boolean } | null {
  const email = typeof b?.email === "string" ? b.email.trim().toLowerCase() : "";
  return email.length <= 254 && EMAIL.test(email) ? { email, movil: b?.movil === true } : null;
}

/** Destino del enlace cuando la recuperación se pide desde la app móvil: vuelve a la app, no a la web. */
export const MOBILE_REDIRECT = "qhub://auth/callback";

/** A dónde vuelve la persona al tocar el botón del correo. Solo orígenes http(s). */
export function recoverRedirect(origin: string | null, site?: string | null): string | undefined {
  const o = siteOrigin(origin, site);
  return o ? `${o}/restablecer` : undefined;
}
