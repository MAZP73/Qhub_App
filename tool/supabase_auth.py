#!/usr/bin/env python3
"""Configura la autenticación del proyecto Supabase (Management API, curl por IPv4).
Lee de .env: SUPABASE_PROJECT_REF, SUPABASE_ACCESS_TOKEN y, opcional, APP_URLS (separadas por coma; por defecto http://localhost:8080). No imprime ningún secreto.
Uso: python3 -I tool/supabase_auth.py"""
import json, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
env = {}
for line in (root / ".env").read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1); env[k.strip()] = v.strip()
raw_urls = [u.strip() for u in env.get("APP_URLS", "http://localhost:8080").split(",") if u.strip()]
# Esquemas de la app móvil (qhub://) se conservan con sus dos barras; las URL web pierden la barra final.
urls = [u if u.endswith("://") else u.rstrip("/") for u in raw_urls]
allow = [f"{u}**" if u.endswith("://") else f"{u}/**" for u in urls]
if not any(u.startswith("qhub:") for u in urls): allow.append("qhub://**")   # los correos de la app móvil siempre deben poder volver a ella
site = next(u for u in urls if not u.endswith("://"))
patch = {
    "site_url": site,
    "uri_allow_list": ",".join(allow),
    "password_min_length": 8,
    "mfa_totp_enroll_enabled": True,    # verificación en dos pasos con app autenticadora (Mi perfil → Seguridad)
    "mfa_totp_verify_enabled": True,
}

# --- Correos de Qhub: mismo aspecto (botón, sin enlaces largos a la vista), en español y con la marca. ---
# Los correos no pueden usar tokens CSS: este es el azul de marca (--interactive de tokens.css) y los grises del tema claro.
BRAND, INK, MUTED, LINE = "#3b4eff", "#161616", "#525252", "#e0e0e0"

def email(title, intro, button, outro):
    return f"""<!doctype html><html lang="es"><body style="margin:0;padding:0;background:#f4f4f4;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f4;padding:32px 16px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid {LINE};font-family:'IBM Plex Sans',Arial,Helvetica,sans-serif;color:{INK};">
<tr><td style="padding:28px 32px 0 32px;font-size:22px;font-weight:600;letter-spacing:-0.2px;color:{BRAND};">Qhub</td></tr>
<tr><td style="padding:20px 32px 0 32px;font-size:20px;font-weight:600;line-height:28px;">{title}</td></tr>
<tr><td style="padding:12px 32px 0 32px;font-size:15px;line-height:24px;color:{MUTED};">{intro}</td></tr>
<tr><td style="padding:24px 32px 0 32px;"><a href="{{{{ .ConfirmationURL }}}}" style="display:inline-block;background:{BRAND};color:#ffffff;text-decoration:none;font-size:15px;font-weight:500;line-height:20px;padding:12px 24px;">{button}</a></td></tr>
<tr><td style="padding:24px 32px 0 32px;font-size:13px;line-height:20px;color:{MUTED};">{outro}</td></tr>
<tr><td style="padding:24px 32px 28px 32px;"><div style="border-top:1px solid {LINE};padding-top:16px;font-size:12px;line-height:18px;color:{MUTED};">Si no esperabas este correo, ignóralo: no se hará ningún cambio.<br>Qhub · Turnos sin filas</div></td></tr>
</table></td></tr></table></body></html>"""

EXPIRES = "Por seguridad, este botón funciona una sola vez y vence pronto."
mails = {
    "invite": ("Te invitaron a unirte a un equipo en Qhub", email("Te invitaron a Qhub", "Te invitaron a unirte a un equipo. Tu perfil ya está listo: solo acepta la invitación para entrar.", "Aceptar invitación", EXPIRES)),
    "magic_link": ("Tu acceso a Qhub", email("Entra a Qhub", "Toca el botón para entrar. Si te invitaron a un equipo, verás la invitación al llegar.", "Entrar a Qhub", EXPIRES)),
    "confirmation": ("Confirma tu correo en Qhub", email("Confirma tu correo", "Gracias por crear tu cuenta en Qhub. Confirma tu correo para empezar.", "Confirmar correo", EXPIRES)),
    "recovery": ("Restablece tu contraseña de Qhub", email("Restablece tu contraseña", "Recibimos una solicitud para cambiar tu contraseña. Toca el botón para elegir una nueva.", "Cambiar contraseña", EXPIRES)),
    "email_change": ("Confirma tu nuevo correo en Qhub", email("Confirma tu nuevo correo", "Pediste cambiar el correo de tu cuenta. Confírmalo para terminar el cambio.", "Confirmar correo", EXPIRES)),
}
templates = {}
for key, (subject, html) in mails.items():
    templates[f"mailer_subjects_{key}"] = subject
    templates[f"mailer_templates_{key}_content"] = html
    (root / "supabase/templates").mkdir(exist_ok=True)
    (root / f"supabase/templates/{key}.html").write_text(html)      # copia para pegarla a mano en el panel si hiciera falta
# Remitente propio (opcional): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_ADMIN_EMAIL en .env. Sin SMTP propio Supabase no deja personalizar los correos.
smtp = {}
if env.get("SMTP_HOST"):
    smtp = {"smtp_host": env["SMTP_HOST"], "smtp_port": env.get("SMTP_PORT", "587"), "smtp_user": env.get("SMTP_USER", ""), "smtp_pass": env.get("SMTP_PASS", ""),
            "smtp_admin_email": env.get("SMTP_ADMIN_EMAIL", ""), "smtp_sender_name": env.get("SMTP_SENDER_NAME", "Qhub")}


def call(method, body=None):
    cmd = ["curl", "-4", "-s", "-m", "60", "-X", method, f"https://api.supabase.com/v1/projects/{env['SUPABASE_PROJECT_REF']}/config/auth",
           "-H", f"Authorization: Bearer {env['SUPABASE_ACCESS_TOKEN']}", "-H", "Content-Type: application/json"]
    with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
        if body is not None:
            f.write(json.dumps(body)); f.flush(); cmd += ["--data", f"@{f.name}"]
        return json.loads(subprocess.run(cmd, capture_output=True, text=True).stdout or "{}")

res = call("PATCH", patch)
if smtp: call("PATCH", smtp)
tres = call("PATCH", templates)
templates_ok = not tres.get("message")
if not templates_ok: print("correos con la marca: no aplicados —", "Supabase solo permite personalizarlos con un SMTP propio (configura SMTP_HOST… en .env). Las plantillas quedaron en supabase/templates/.")
now = call("GET")
print("site_url:", now.get("site_url"))
print("uri_allow_list:", now.get("uri_allow_list"))
print("password_min_length:", now.get("password_min_length"))
print("2FA (TOTP) habilitado:", now.get("mfa_totp_enroll_enabled"), now.get("mfa_totp_verify_enabled"))
bad = [k for k, v in mails.items() if now.get(f"mailer_subjects_{k}") != v[0]]
print("correos con la marca:", "aplicados" if not bad else "pendientes (necesitan SMTP propio)")
ok = now.get("password_min_length") == 8 and now.get("site_url") == site and "qhub://**" in (now.get("uri_allow_list") or "") and now.get("mfa_totp_enroll_enabled") is True
sys.exit(0 if ok else 1)
