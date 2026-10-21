-- Reglas propias de cada cola que la API no guarda: descansos y márgenes del turno «ahora» y de las citas.
-- Las aplica qhub-proxy (turnos de clientes) y las edita el administrador en la web. Aditivo: no toca nada existente.
create table public.cola_reglas (
  organizacion_id      uuid not null references public.organizaciones(id) on delete cascade,
  qhub_cola_id         uuid not null,
  -- [{"desde":"13:00","hasta":"14:00"}] en la hora local de la cola; aplica a todos los días de atención.
  descansos            jsonb not null default '[]'::jsonb check (jsonb_typeof(descansos) = 'array' and jsonb_array_length(descansos) <= 6),
  margen_ahora_min     integer not null default 3 check (margen_ahora_min between 0 and 60),      -- espera mínima de un turno «ahora»
  anticipacion_cita_min integer not null default 5 check (anticipacion_cita_min between 0 and 240), -- una cita debe empezar al menos tanto después de «ahora»
  max_citas_activas    integer not null default 3 check (max_citas_activas between 1 and 20),      -- citas activas por persona y cola
  actualizado_en       timestamptz not null default now(),
  primary key (organizacion_id, qhub_cola_id)
);
create trigger cola_reglas_actualizado before update on public.cola_reglas
  for each row execute function public.set_actualizado_en();

alter table public.cola_reglas enable row level security;
-- El público también las necesita para mostrar el descanso; solo el administrador las cambia (igual que los prefijos).
create policy cola_reglas_select on public.cola_reglas for select to authenticated using (
  public.es_miembro(organizacion_id)
  or exists (select 1 from public.organizaciones o where o.id = organizacion_id and o.publica and o.activa));
create policy cola_reglas_write on public.cola_reglas for all to authenticated
  using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id));
grant select, insert, update, delete on public.cola_reglas to authenticated;
