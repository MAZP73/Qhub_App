-- Invitaciones por correo: el administrador puede dejar el perfil de la persona ya configurado, la persona acepta
-- desde el enlace del correo (o con el código) y entra. Una invitación pendiente por correo y organización.
alter table public.invitaciones
  add column nombre   text check (nombre   is null or length(nombre)   between 2 and 60),
  add column apellido text check (apellido is null or length(apellido) between 2 and 60),
  add column cargo    text check (cargo    is null or length(cargo)    between 2 and 80),
  add column enviada_en timestamptz;

create unique index invitaciones_pendiente_unica on public.invitaciones (organizacion_id, lower(email)) where aceptada_en is null;

-- ¿Esa persona ya es parte del equipo? (solo administradores; mira el correo en auth sin exponerlo)
create or replace function public.ya_es_miembro(p_org uuid, p_email text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  return exists (select 1 from public.miembros m join auth.users u on u.id = m.usuario_id
                 where m.organizacion_id = p_org and m.activo and lower(u.email) = lower(trim(p_email)));
end $$;
revoke all on function public.ya_es_miembro(uuid, text) from public, anon;
grant execute on function public.ya_es_miembro(uuid, text) to authenticated;

-- Lo que ve la persona invitada antes de aceptar. Solo si la invitación es para SU correo, no está usada y no venció.
create or replace function public.ver_invitacion(p_token text)
returns table (organizacion text, tipo public.tipo_cuenta, rol public.rol_organizacion, email text, nombre text, apellido text, cargo text, expira_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_email text;
begin
  select u.email into v_email from auth.users u where u.id = (select auth.uid());
  return query
  select o.nombre, o.tipo, i.rol, i.email, i.nombre, i.apellido, i.cargo, i.expira_en
  from public.invitaciones i join public.organizaciones o on o.id = i.organizacion_id
  where i.token = p_token and i.aceptada_en is null and i.expira_en > now() and lower(i.email) = lower(v_email);
  if not found then raise exception 'Invitación inválida, vencida o para otro correo' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.ver_invitacion(text) from public, anon;
grant execute on function public.ver_invitacion(text) to authenticated;

-- Al aceptar, el perfil queda con lo que el administrador configuró (sin pisar lo que la persona ya tenía).
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
  update public.perfiles set
    nombre   = coalesce(nullif(nombre, ''),   v_inv.nombre),
    apellido = coalesce(nullif(apellido, ''), v_inv.apellido),
    cargo    = coalesce(nullif(cargo, ''),    v_inv.cargo)
   where id = v_uid;
  update public.invitaciones set aceptada_en = now() where id = v_inv.id;
  return v_inv.organizacion_id;
end $$;
