#!/usr/bin/env python3
"""Ejecuta un archivo SQL contra el proyecto Supabase usando la Management API (vía curl, IPv4).
Lee SUPABASE_PROJECT_REF y SUPABASE_ACCESS_TOKEN de .env (nunca se imprimen).
Uso: python3 -I tool/supabase_sql.py <archivo.sql>"""
import json, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
env = {}
for line in (root / ".env").read_text().splitlines():
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1); env[k.strip()] = v.strip()
ref, token = env["SUPABASE_PROJECT_REF"], env["SUPABASE_ACCESS_TOKEN"]
payload = json.dumps({"query": pathlib.Path(sys.argv[1]).read_text()})
with tempfile.NamedTemporaryFile("w", suffix=".json") as f:
    f.write(payload); f.flush()
    out = subprocess.run(
        ["curl", "-4", "-s", "-m", "90", "-X", "POST", f"https://api.supabase.com/v1/projects/{ref}/database/query",
         "-H", f"Authorization: Bearer {token}", "-H", "Content-Type: application/json", "--data", f"@{f.name}"],
        capture_output=True, text=True)
print(out.stdout[:3000] or out.stderr[:500])
ok = out.stdout.startswith("[") or "P0001: OK:" in out.stdout
sys.exit(0 if ok else 1)
