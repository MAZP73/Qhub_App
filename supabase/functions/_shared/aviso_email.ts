// Correo de un aviso (acción importante). Mismo aspecto que los correos de autenticación: marca, botón y pie. Puro: sin red.
const BRAND = "#3b4eff", INK = "#161616", MUTED = "#525252", LINE = "#e0e0e0";

export const escapeHtml = (v: string): string =>
  v.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");

export interface AvisoMail { titulo: string; mensaje: string; boton?: { texto: string; url: string } | null }

/** Enlace del botón: solo http(s). Cualquier otra cosa se descarta (nunca `javascript:`). */
export function enlaceSeguro(url: string | null | undefined): string | null {
  try { if (!url) return null; const u = new URL(url); return u.protocol === "https:" || u.protocol === "http:" ? u.toString() : null; } catch { return null; }
}

/** Enlace de la web para un aviso de equipo: `ruta` es relativa (`/equipo`) y se pega al sitio público. */
export function enlaceDeRuta(ruta: string | null | undefined, site: string | null | undefined): string | null {
  if (!ruta || !/^\/[a-z0-9/_-]*$/.test(ruta) || !site) return null;
  return enlaceSeguro(`${site.replace(/\/+$/, "")}${ruta}`);
}

export function avisoHtml(a: AvisoMail): string {
  const boton = a.boton && enlaceSeguro(a.boton.url)
    ? `<tr><td style="padding:24px 32px 0 32px;"><a href="${escapeHtml(enlaceSeguro(a.boton.url)!)}" style="display:inline-block;background:${BRAND};color:#ffffff;text-decoration:none;font-size:15px;font-weight:500;line-height:20px;padding:12px 24px;">${escapeHtml(a.boton.texto)}</a></td></tr>`
    : "";
  return `<!doctype html><html lang="es"><body style="margin:0;padding:0;background:#f4f4f4;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:32px 16px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid ${LINE};font-family:'IBM Plex Sans',Arial,Helvetica,sans-serif;color:${INK};">
<tr><td style="padding:28px 32px 0 32px;font-size:22px;font-weight:600;letter-spacing:-0.2px;color:${BRAND};">Qhub</td></tr>
<tr><td style="padding:20px 32px 0 32px;font-size:20px;font-weight:600;line-height:28px;">${escapeHtml(a.titulo)}</td></tr>
<tr><td style="padding:12px 32px 0 32px;font-size:15px;line-height:24px;color:${MUTED};">${escapeHtml(a.mensaje)}</td></tr>
${boton}
<tr><td style="padding:24px 32px 28px 32px;"><div style="border-top:1px solid ${LINE};padding-top:16px;font-size:12px;line-height:18px;color:${MUTED};">Recibes este correo porque pasó algo importante en tu cuenta de Qhub.<br>Qhub · Turnos sin filas</div></td></tr>
</table></td></tr></table></body></html>`;
}

/** Envía un correo por Brevo. `false` si Brevo no lo aceptó (el llamador decide si reintenta). */
export async function enviarBrevo(to: string, asunto: string, html: string, env: { key: string; from: string; name?: string }, fetchFn: typeof fetch = fetch): Promise<boolean> {
  const res = await fetchFn("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": env.key, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ sender: { email: env.from, name: env.name ?? "Qhub" }, to: [{ email: to }], subject: asunto, htmlContent: html }),
  }).catch(() => null);
  return !!res && res.ok;
}
