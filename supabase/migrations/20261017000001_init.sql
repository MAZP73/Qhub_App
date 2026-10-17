-- Qhub_APP — esquema inicial (proyecto Supabase compartido por escritorio y móvil)
-- Roles:
--   plataforma:   usuario (público) | superadmin (dueño de la plataforma)
--   organización: admin | agente   (tabla miembros; una persona puede ser staff de varias)
-- Seguridad: RLS en todo; anon sin permisos; credenciales de la API Qhub solo para service_role.

-- ───────── Tipos ─────────
create type public.rol_plataforma    as enum ('usuario', 'superadmin');
create type public.rol_organizacion  as enum ('admin', 'agente');
create type public.plataforma_disp   as enum ('android', 'ios', 'windows', 'macos', 'linux', 'web');

-- ───────── Utilidades ─────────
create or replace function public.set_actualizado_en()
returns trigger language plpgsql set search_path = '' as $$
begin new.actualizado_en = now(); return new; end $$;

-- ───────── perfiles (1:1 con auth.users) ─────────
create table public.perfiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  rol            public.rol_plataforma not null default 'usuario',
  nombre         text,
  apellido       text,
  telefono       text,
  avatar_url     text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create trigger perfiles_actualizado before update on public.perfiles
  for each row execute function public.set_actualizado_en();

-- El rol NUNCA sale de los metadatos que manda el cliente: todo registro nace 'usuario'.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfiles (id, nombre, apellido)
  values (new.id,
          nullif(new.raw_user_meta_data ->> 'nombre', ''),
          nullif(new.raw_user_meta_data ->> 'apellido', ''));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────── organizaciones ─────────
create table public.organizaciones (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null check (length(trim(nombre)) >= 2),
  slug               text not null unique check (slug ~ '^[a-z0-9-]+$'),
  descripcion        text,
  direccion          text,
  ciudad             text,
  pais               text,
  latitud            double precision check (latitud between -90 and 90),
  longitud           double precision check (longitud between -180 and 180),
  telefono           text,
  logo_url           text,
  zona_horaria       text not null default 'America/Guayaquil',
  qhub_propietario_tipo text check (qhub_propietario_tipo in ('empresa', 'usuario')),
  qhub_propietario_id   uuid,            -- id de la cuenta en la API Qhub (referencia, sin FK)
  publica            boolean not null default false,  -- visible en el móvil
  activa             boolean not null default true,
  creada_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now()
);
create trigger organizaciones_actualizado before update on public.organizaciones
  for each row execute function public.set_actualizado_en();

-- Credencial de la API Qhub por organización. Solo la lee el backend (Edge Functions, service_role).
create table public.organizacion_credenciales (
  organizacion_id uuid primary key references public.organizaciones(id) on delete cascade,
  qhub_api_key    text not null,
  actualizado_en  timestamptz not null default now()
);

-- ───────── miembros (staff) ─────────
create table public.miembros (
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  rol             public.rol_organizacion not null,
  activo          boolean not null default true,
  creado_en       timestamptz not null default now(),
  primary key (organizacion_id, usuario_id)
);
create index miembros_usuario_idx on public.miembros (usuario_id);

create table public.invitaciones (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  email           text not null,
  rol             public.rol_organizacion not null default 'agente',
  token           text not null unique default encode(gen_random_bytes(24), 'hex'),
  invitada_por    uuid references public.perfiles(id) on delete set null,
  expira_en       timestamptz not null default now() + interval '7 days',
  aceptada_en     timestamptz,
  creada_en       timestamptz not null default now()
);
create index invitaciones_org_idx on public.invitaciones (organizacion_id);

-- ───────── funciones de rol (security definer: evitan recursión de RLS) ─────────
create or replace function public.es_superadmin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfiles
                 where id = (select auth.uid()) and rol = 'superadmin' and activo)
$$;

create or replace function public.rol_en_organizacion(org uuid)
returns public.rol_organizacion language sql stable security definer set search_path = '' as $$
  select m.rol from public.miembros m
  where m.organizacion_id = org and m.usuario_id = (select auth.uid()) and m.activo
  limit 1
$$;

create or replace function public.es_miembro(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.rol_en_organizacion(org) is not null or public.es_superadmin()
$$;

create or replace function public.es_admin_org(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.rol_en_organizacion(org) = 'admin' or public.es_superadmin()
$$;

-- ───────── ajustes por organización ─────────
create table public.ajustes_organizacion (
  organizacion_id uuid primary key references public.organizaciones(id) on delete cascade,
  preferencias    jsonb not null default '{}'::jsonb,
  actualizado_en  timestamptz not null default now()
);
create trigger ajustes_actualizado before update on public.ajustes_organizacion
  for each row execute function public.set_actualizado_en();

-- Prefijo visible del turno (A-023): la API solo da un número entero.
create table public.cola_prefijos (
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  qhub_cola_id    uuid not null,
  prefijo         text not null check (prefijo ~ '^[A-Z]{1,2}$'),
  primary key (organizacion_id, qhub_cola_id)
);

-- ───────── público (móvil) ─────────
create table public.favoritos (
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  qhub_cola_id    uuid,
  creado_en       timestamptz not null default now()
);
create unique index favoritos_unico on public.favoritos
  (usuario_id, organizacion_id, coalesce(qhub_cola_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table public.dispositivos (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.perfiles(id) on delete cascade,
  plataforma  public.plataforma_disp not null,
  token_push  text not null,
  activo      boolean not null default true,
  creado_en   timestamptz not null default now(),
  unique (usuario_id, token_push)
);

-- Copia local del historial del usuario (la escribe el backend al sacar/cambiar un turno).
create table public.historial_turnos (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  qhub_turno_id   uuid not null,
  qhub_cola_id    uuid not null,
  cola_nombre     text,
  numero          integer,
  estado          text not null,
  franja_inicio   timestamptz,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  unique (organizacion_id, qhub_turno_id)
);
create index historial_usuario_idx on public.historial_turnos (usuario_id, creado_en desc);
create trigger historial_actualizado before update on public.historial_turnos
  for each row execute function public.set_actualizado_en();

-- ───────── escritorio ─────────
create table public.auditoria (
  id              bigint generated always as identity primary key,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id      uuid references public.perfiles(id) on delete set null,
  accion          text not null,
  entidad         text,
  entidad_id      text,
  detalle         jsonb not null default '{}'::jsonb,
  creada_en       timestamptz not null default now()
);
create index auditoria_org_idx on public.auditoria (organizacion_id, creada_en desc);

create table public.snapshots_metricas (
  id              bigint generated always as identity primary key,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  qhub_cola_id    uuid,
  fecha           date not null,
  datos           jsonb not null,
  creado_en       timestamptz not null default now(),
  unique (organizacion_id, qhub_cola_id, fecha)
);

-- ───────── RPC: crear organización (el creador queda como admin) ─────────
create or replace function public.crear_organizacion(
  p_nombre text, p_slug text, p_ciudad text default null, p_pais text default null,
  p_zona_horaria text default 'America/Guayaquil')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  insert into public.organizaciones (nombre, slug, ciudad, pais, zona_horaria)
  values (p_nombre, p_slug, p_ciudad, p_pais, p_zona_horaria) returning id into v_id;
  insert into public.miembros (organizacion_id, usuario_id, rol) values (v_id, v_uid, 'admin');
  insert into public.ajustes_organizacion (organizacion_id) values (v_id);
  return v_id;
end $$;

-- ───────── RPC: aceptar invitación ─────────
create or replace function public.aceptar_invitacion(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_inv public.invitaciones; v_uid uuid := (select auth.uid());
        v_email text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select email into v_email from auth.users where id = v_uid;
  select * into v_inv from public.invitaciones
   where token = p_token and aceptada_en is null and expira_en > now()
     and lower(email) = lower(v_email)
   for update;
  if not found then raise exception 'Invitación inválida, vencida o para otro correo' using errcode = 'P0002'; end if;
  insert into public.miembros (organizacion_id, usuario_id, rol)
  values (v_inv.organizacion_id, v_uid, v_inv.rol)
  on conflict (organizacion_id, usuario_id) do update set rol = excluded.rol, activo = true;
  update public.invitaciones set aceptada_en = now() where id = v_inv.id;
  return v_inv.organizacion_id;
end $$;

-- ───────── RLS ─────────
alter table public.perfiles                  enable row level security;
alter table public.organizaciones            enable row level security;
alter table public.organizacion_credenciales enable row level security;  -- sin policies: solo service_role
alter table public.miembros                  enable row level security;
alter table public.invitaciones              enable row level security;
alter table public.ajustes_organizacion      enable row level security;
alter table public.cola_prefijos             enable row level security;
alter table public.favoritos                 enable row level security;
alter table public.dispositivos              enable row level security;
alter table public.historial_turnos          enable row level security;
alter table public.auditoria                 enable row level security;
alter table public.snapshots_metricas        enable row level security;

-- perfiles
create policy perfiles_select on public.perfiles for select to authenticated using (
  id = (select auth.uid()) or public.es_superadmin()
  or exists (select 1 from public.miembros m where m.usuario_id = perfiles.id and public.es_miembro(m.organizacion_id)));
create policy perfiles_update_propio on public.perfiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- organizaciones
create policy org_select on public.organizaciones for select to authenticated using (
  (publica and activa) or public.es_miembro(id));
create policy org_update on public.organizaciones for update to authenticated
  using (public.es_admin_org(id)) with check (public.es_admin_org(id));

-- miembros
create policy miembros_select on public.miembros for select to authenticated using (
  usuario_id = (select auth.uid()) or public.es_miembro(organizacion_id));
create policy miembros_insert on public.miembros for insert to authenticated
  with check (public.es_admin_org(organizacion_id));
create policy miembros_update on public.miembros for update to authenticated
  using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id));
create policy miembros_delete on public.miembros for delete to authenticated
  using (public.es_admin_org(organizacion_id));

-- invitaciones
create policy inv_all on public.invitaciones for all to authenticated
  using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id));

-- ajustes
create policy ajustes_select on public.ajustes_organizacion for select to authenticated using (public.es_miembro(organizacion_id));
create policy ajustes_write  on public.ajustes_organizacion for all to authenticated
  using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id));

-- prefijos (el público también los necesita para mostrar A-023)
create policy prefijos_select on public.cola_prefijos for select to authenticated using (
  public.es_miembro(organizacion_id)
  or exists (select 1 from public.organizaciones o where o.id = organizacion_id and o.publica and o.activa));
create policy prefijos_write on public.cola_prefijos for all to authenticated
  using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id));

-- público
create policy favoritos_propios on public.favoritos for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
create policy dispositivos_propios on public.dispositivos for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
create policy historial_select on public.historial_turnos for select to authenticated
  using (usuario_id = (select auth.uid()));   -- escribe solo el backend (service_role)

-- escritorio
create policy auditoria_select on public.auditoria for select to authenticated using (public.es_admin_org(organizacion_id));
create policy auditoria_insert on public.auditoria for insert to authenticated
  with check (public.es_miembro(organizacion_id) and usuario_id = (select auth.uid()));
create policy snapshots_select on public.snapshots_metricas for select to authenticated using (public.es_miembro(organizacion_id));
create policy snapshots_write on public.snapshots_metricas for all to authenticated
  using (public.es_miembro(organizacion_id)) with check (public.es_miembro(organizacion_id));

-- ───────── Permisos: cerrado por defecto ─────────
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated, public;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated, public;

grant select                         on public.organizaciones, public.miembros, public.ajustes_organizacion,
                                        public.cola_prefijos, public.perfiles, public.historial_turnos,
                                        public.auditoria, public.snapshots_metricas to authenticated;
grant update (nombre, apellido, telefono, avatar_url) on public.perfiles to authenticated;      -- nunca rol/activo
grant update (nombre, descripcion, direccion, ciudad, pais, latitud, longitud, telefono, logo_url,
              zona_horaria, publica)  on public.organizaciones to authenticated;                -- no activa ni ids Qhub
grant insert, update, delete         on public.miembros, public.invitaciones, public.cola_prefijos,
                                        public.ajustes_organizacion, public.snapshots_metricas to authenticated;
grant select                         on public.invitaciones to authenticated;
grant select, insert, update, delete on public.favoritos, public.dispositivos to authenticated;
grant insert                         on public.auditoria to authenticated;

grant execute on function public.es_superadmin(), public.rol_en_organizacion(uuid),
                          public.es_miembro(uuid), public.es_admin_org(uuid),
                          public.crear_organizacion(text, text, text, text, text),
                          public.aceptar_invitacion(text) to authenticated;
-- service_role conserva todo (backend / Edge Functions).
grant all on all tables    in schema public to service_role;
grant all on all functions in schema public to service_role;
grant usage, select on all sequences in schema public to service_role, authenticated;
