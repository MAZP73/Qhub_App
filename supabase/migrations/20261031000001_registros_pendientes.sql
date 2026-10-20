-- Registros por confirmar: al crear la cuenta NO se crea nada (ni en la web ni en Qhub). Los datos (con la contraseña CIFRADA en el servidor)
-- esperan aquí hasta que la persona confirma su correo; ahí la función qhub-register crea las dos cuentas y esta fila se borra.
create table if not exists public.registros_pendientes (
  id          uuid primary key default gen_random_uuid(),
  email       text not null,
  token_hash  text not null unique,
  datos       text not null,                       -- sobre cifrado (AES-GCM) con nombre, apellido, contraseña y datos de la cuenta
  expira_en   timestamptz not null default now() + interval '24 hours',
  creado_en   timestamptz not null default now()
);
create unique index if not exists registros_pendientes_email_idx on public.registros_pendientes (lower(email));
alter table public.registros_pendientes enable row level security;   -- sin policies: solo service_role (Edge Function)
revoke all on public.registros_pendientes from anon, authenticated;
