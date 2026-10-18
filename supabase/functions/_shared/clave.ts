// Orquestación de la clave inicial cifrada, probable sin red (los `index.ts` quedan como cascarón delgado).
// La clave de cifrado vive en CLAVE_INICIAL_KEY (base64 -> 32 bytes); nunca toca la base ni el cliente.
import { decrypt, encrypt, importKey, type Envelope } from "./crypto.ts";

/** Lee y valida CLAVE_INICIAL_KEY del entorno. `null` si falta o no es una clave AES-256 válida. */
export async function loadKey(getEnv: (k: string) => string | undefined): Promise<string | null> {
  const key = getEnv("CLAVE_INICIAL_KEY");
  if (!key) return null;
  try { await importKey(key); return key; } catch { return null; }
}

/**
 * Al invitar: cifra la contraseña para guardarla. `null` = no se puede (falta la clave): el invite NO guarda nada
 * (no texto plano) y la invitación se envía igual; la persona recupera por «Olvidé mi contraseña».
 */
export async function sealInitialPassword(plain: string, keyB64: string | null): Promise<Envelope | null> {
  if (!keyB64) return null;
  try { return await encrypt(plain, keyB64); } catch { return null; }
}

/** Resultado de leer la clave inicial para mostrarla una vez. */
export type ClaveResult = { status: 200; body: { clave: string | null } } | { status: 500; body: { error: string } };

/**
 * Al aceptar: con el sobre cifrado que devolvió la SQL (o `null` si no hay/está vencida), decide la respuesta.
 * - sin sobre autorizado -> 200 { clave: null } (aceptada/vencida/correo no coincide)
 * - con sobre y clave válida -> 200 { clave: string }
 * - falla el descifrado o falta la clave -> 500 (detalle solo a consola)
 */
export async function readInitialPassword(sealed: Envelope | string | null, keyB64: string | null): Promise<ClaveResult> {
  if (sealed == null) return { status: 200, body: { clave: null } };
  if (!keyB64) return { status: 500, body: { error: "No pudimos leer la clave." } };
  try { return { status: 200, body: { clave: await decrypt(sealed, keyB64) } }; }
  catch { return { status: 500, body: { error: "No pudimos leer la clave." } }; }
}
