-- La cuenta que usa el escritorio (usuario + contraseña) es la MISMA que debe usar el móvil: si no, verían colas distintas.
-- Las credenciales solo las lee/escribe el backend (service_role); ningún rol de cliente tiene permisos.
alter table public.organizacion_credenciales
  add column if not exists qhub_identificador text,
  add column if not exists qhub_password text,
  alter column qhub_api_key drop not null;

alter table public.organizacion_credenciales
  add constraint chk_credencial_presente check (
    qhub_api_key is not null or (qhub_identificador is not null and qhub_password is not null)
  );

-- ¿Está la organización conectada al móvil? (lo mantienen las Edge Functions; el cliente solo lo lee)
alter table public.organizaciones add column if not exists vinculada boolean not null default false;

-- Publicar sin vínculo no tiene sentido: el móvil no podría operar.
alter table public.organizaciones
  add constraint chk_publica_requiere_vinculo check (not publica or vinculada);

-- Un administrador ya no cambia "publica" directamente: se hace con la función qhub-link.
revoke update (publica) on public.organizaciones from authenticated;

revoke all on public.organizacion_credenciales from anon, authenticated;
