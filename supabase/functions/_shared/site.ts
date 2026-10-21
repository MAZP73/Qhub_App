// Sitio al que vuelven los enlaces de los correos. Siempre el público (SITE_URL), nunca el dominio desde donde se pidió: puede ser una
// vista previa de Vercel protegida. Solo en desarrollo (localhost) se respeta el origen. Solo http(s).
const http = (v: string | null | undefined): URL | null => {
  try { if (!v) return null; const u = new URL(v); return u.protocol === "https:" || u.protocol === "http:" ? u : null; } catch { return null; }
};

/** Origen (`https://dominio`) para armar un enlace, o `undefined` si no hay ninguno válido. */
export function siteOrigin(origin: string | null, site?: string | null): string | undefined {
  const o = http(origin), pub = http(site);
  const local = o && (o.hostname === "localhost" || o.hostname === "127.0.0.1");
  return (local ? o : (pub ?? o))?.origin;
}

/** Cambia el dominio de una URL ya armada (conserva ruta y query) por el del sitio público. Localhost se deja igual. */
export function withSite(url: string | undefined, site?: string | null): string | undefined {
  const u = http(url), pub = http(site);
  if (!u || !pub || u.hostname === "localhost" || u.hostname === "127.0.0.1") return url;
  return `${pub.origin}${u.pathname}${u.search}${u.hash}`;
}
