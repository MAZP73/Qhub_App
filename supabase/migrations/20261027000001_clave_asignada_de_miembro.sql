-- Un administrador necesita poder ver la contraseña inicial que le asignó a cada persona de su equipo,
-- incluso después de que esa persona aceptó la invitación. Hasta hoy el sobre cifrado vivía en
-- public.claves_iniciales (keyed por invitación) y el trigger de aceptación lo BORRABA al aceptar, así que
-- un miembro ya aceptado no tenía sobre que leer. Solución: guardar el sobre, además, en una tabla keyed por
-- (organización, usuario) al momento de aceptar, y exponer una RPC admin-only que lo devuelve (cifrado) para
-- que la Edge Function qhub-clave lo descifre. Nunca texto plano: se reusa el mismo sobre AES-GCM { v, iv, d }.
-- No ejecutable localmente (sin Supabase CLI): aplicar por despliegue / Supabase CLI / SQL editor.

-- Sobre cifrado de la contraseña inicial, conservado por persona para que el administrador de la organización
-- pueda consultarlo. Mismo tratamiento de privacidad que public.claves_iniciales: RLS activada y sin políticas,
-- sin permisos directos; solo la RPC de abajo (service_role) lo lee.
create table public.claves_asignadas (
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  clave           text not null,
  creada_en       timestamptz not null default now(),
  primary key (organizacion_id, usuario_id)
);
comment on column public.claves_asignadas.clave is
  'Sobre cifrado AES-GCM ({ v, iv, d } en base64), nunca texto plano. Lo descifra la Edge Function qhub-clave con CLAVE_INICIAL_KEY.';
alter table public.claves_asignadas enable row level security;      -- sin políticas: nadie la lee por RLS
revoke all on public.claves_asignadas from public, anon, authenticated;

-- Al aceptar la invitación: copiar el sobre a public.claves_asignadas (keyed por organización + usuario que aceptó)
-- ANTES de borrarlo de public.claves_iniciales. El usuario que aceptó es el auth.users cuyo correo coincide con el
-- correo invitado. El trigger borrar_clave_inicial sobre public.invitaciones ya existe; aquí solo se reemplaza su función.
create or replace function public.trg_borrar_clave_inicial() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  if new.aceptada_en is not null then
    select u.id into v_uid from auth.users u where lower(u.email) = lower(new.email);
    if v_uid is not null then
      insert into public.claves_asignadas (organizacion_id, usuario_id, clave)
      select new.organizacion_id, v_uid, c.clave
      from public.claves_iniciales c where c.invitacion_id = new.id
      on conflict (organizacion_id, usuario_id) do update set clave = excluded.clave, creada_en = now();
    end if;
    delete from public.claves_iniciales where invitacion_id = new.id;
  end if;
  return new;
end $$;

-- Lectura admin-only del sobre cifrado de un miembro del equipo. Devuelve el TEXTO CIFRADO (nunca texto plano);
-- lo descifra la Edge Function qhub-clave. Autorización SIEMPRE dentro del SQL: es_admin_org + pertenencia al equipo.
-- Solo service_role (la Edge Function) puede ejecutarla.
create or replace function public.clave_inicial_de_miembro(p_org uuid, p_usuario uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_clave text;
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = p_usuario) then
    raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002';
  end if;
  select clave into v_clave from public.claves_asignadas where organizacion_id = p_org and usuario_id = p_usuario;
  return v_clave;
end $$;
revoke all on function public.clave_inicial_de_miembro(uuid, uuid) from public, anon, authenticated;
grant execute on function public.clave_inicial_de_miembro(uuid, uuid) to service_role;
