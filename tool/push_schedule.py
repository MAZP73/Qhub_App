#!/usr/bin/env python3
"""Activa el envío de notificaciones push: crea el secreto PUSH_CRON_SECRET (Edge Functions + Vault) y programa con pg_cron
la llamada a la función qhub-push cada 30 s. Es idempotente: cada corrida rota el secreto y reemplaza la tarea.
Lee SUPABASE_PROJECT_REF y SUPABASE_ACCESS_TOKEN de .env (nunca se imprimen).
Uso: python3 -I tool/push_schedule.py   (antes: desplegar la función qhub-push y aplicar la migración de dispositivos_push)"""
import json, pathlib, secrets, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
env = {}
for line in (root / ".env").read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1); env[k.strip()] = v.strip()
ref, token = env["SUPABASE_PROJECT_REF"], env["SUPABASE_ACCESS_TOKEN"]

def api(path, body):
    with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
        f.write(json.dumps(body)); f.flush()
        out = subprocess.run(["curl", "-4", "-s", "-m", "90", "-w", "\n%{http_code}", "-X", "POST", f"https://api.supabase.com/v1/projects/{ref}{path}",
                              "-H", f"Authorization: Bearer {token}", "-H", "Content-Type: application/json", "--data", f"@{f.name}"],
                             capture_output=True, text=True).stdout
    text, _, code = out.rpartition("\n")
    return int(code or 0), text

secret = secrets.token_urlsafe(32)
code, _ = api("/secrets", [{"name": "PUSH_CRON_SECRET", "value": secret}])
if code not in (200, 201):
    print("No se pudo guardar PUSH_CRON_SECRET en las Edge Functions (HTTP", code, ")"); sys.exit(1)

sql = f"""
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $$
begin
  if exists (select 1 from vault.secrets where name = 'qhub_push_secret') then
    perform vault.update_secret((select id from vault.secrets where name = 'qhub_push_secret'), '{secret}');
  else
    perform vault.create_secret('{secret}', 'qhub_push_secret', 'Secreto con que pg_cron llama a la función qhub-push');
  end if;
  perform cron.unschedule(jobid) from cron.job where jobname = 'qhub-push';
end $$;
select cron.schedule('qhub-push', '30 seconds', $job$
  select net.http_post(
    url := 'https://{ref}.supabase.co/functions/v1/qhub-push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-push-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'qhub_push_secret')),
    body := '{{}}'::jsonb, timeout_milliseconds := 20000);
$job$);
"""
code, text = api("/database/query", {"query": sql})
print("HTTP", code, "—", "tarea qhub-push programada cada 30 s" if code in (200, 201) else text[:500])
sys.exit(0 if code in (200, 201) else 1)
