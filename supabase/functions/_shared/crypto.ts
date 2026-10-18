// Cifrado simétrico AES-GCM con una clave del servidor (nunca sale del servidor, nunca toca la base).
// Mismo estilo que el baúl del dispositivo del web: IV aleatorio de 12 bytes, sobre { v, iv, d } en base64.

export interface CryptoError { kind: "crypto"; message: string }
const fail = (message: string): CryptoError => ({ kind: "crypto", message });

const b64 = (buf: ArrayBuffer | Uint8Array): string => {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = "";
  for (const byte of bytes) s += String.fromCharCode(byte);
  return btoa(s);
};
const unb64 = (s: string): Uint8Array<ArrayBuffer> => {
  const bin = atob(s);
  const out = new Uint8Array(new ArrayBuffer(bin.length));
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};

/** Sobre cifrado guardado en la columna `clave`. */
export interface Envelope { v: 1; iv: string; d: string }

/** Importa la clave base64; exige exactamente 32 bytes (AES-256) o lanza un error tipado. */
export async function importKey(keyB64: string): Promise<CryptoKey> {
  let raw: Uint8Array<ArrayBuffer>;
  try { raw = unb64(keyB64); } catch { throw fail("La clave de cifrado no es base64 válido."); }
  if (raw.length !== 32) throw fail("La clave de cifrado debe decodificar a 32 bytes (AES-256).");
  return await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

/** Cifra un texto plano y devuelve el sobre en base64. */
export async function encrypt(plain: string, keyB64: string): Promise<Envelope> {
  const key = await importKey(keyB64);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(plain));
  return { v: 1, iv: b64(iv), d: b64(data) };
}

/** Descifra un sobre (acepta el objeto o su JSON en texto). Lanza un error tipado si no corresponde a la clave. */
export async function decrypt(payload: Envelope | string, keyB64: string): Promise<string> {
  const env: Envelope = typeof payload === "string" ? JSON.parse(payload) : payload;
  if (!env || env.v !== 1 || typeof env.iv !== "string" || typeof env.d !== "string") throw fail("El sobre cifrado no es válido.");
  const key = await importKey(keyB64);
  try {
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(env.iv) }, key, unb64(env.d));
    return new TextDecoder().decode(plain);
  } catch { throw fail("No se pudo descifrar la clave."); }
}
