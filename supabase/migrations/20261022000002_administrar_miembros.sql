-- Un administrador puede ver y editar el perfil básico de las personas de SU equipo y quitarlas del equipo.
-- Solo el equipo: nunca los clientes (personas de la app móvil), que pueden tener información sensible.
-- «Quitar» no borra la cuenta de la persona (puede pertenecer a otros equipos): solo termina su pertenencia a esta organización.

create or replace function public.perfil_de_miembro(p_org uuid, p_usuario uuid)
returns table (nombre text, apellido text, cargo text, telefono text, email text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  return query
  select p.nombre, p.apellido, p.cargo, p.telefono, u.email::text
  from public.miembros m join public.perfiles p on p.id = m.usuario_id join auth.users u on u.id = m.usuario_id
  where m.organizacion_id = p_org and m.usuario_id = p_usuario;
  if not found then raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.perfil_de_miembro(uuid, uuid) from public, anon;
grant execute on function public.perfil_de_miembro(uuid, uuid) to authenticated;

create or replace function public.editar_miembro(p_org uuid, p_usuario uuid, p_nombre text, p_apellido text, p_cargo text, p_telefono text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_n text := nullif(trim(p_nombre), ''); v_a text := nullif(trim(p_apellido), ''); v_c text := nullif(trim(p_cargo), ''); v_t text := nullif(trim(p_telefono), '');
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = p_usuario) then
    raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002';
  end if;
  if v_n is null or length(v_n) < 2 or length(v_n) > 60 or v_a is null or length(v_a) < 2 or length(v_a) > 60 then
    raise exception 'Revisa el nombre y el apellido' using errcode = '22023';
  end if;
  if v_c is not null and length(v_c) not between 2 and 80 then raise exception 'Revisa el cargo' using errcode = '22023'; end if;
  if v_t is not null and v_t !~ '^\+?[0-9 ()-]{7,20}$' then raise exception 'Revisa el teléfono' using errcode = '22023'; end if;
  update public.perfiles set nombre = v_n, apellido = v_a, cargo = v_c, telefono = v_t where id = p_usuario;
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, (select auth.uid()), 'miembro.editar', 'perfil', p_usuario::text, '{}'::jsonb);
end $$;
revoke all on function public.editar_miembro(uuid, uuid, text, text, text, text) from public, anon;
grant execute on function public.editar_miembro(uuid, uuid, text, text, text, text) to authenticated;

create or replace function public.quitar_miembro(p_org uuid, p_usuario uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol public.rol_organizacion;
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if p_usuario = (select auth.uid()) then raise exception 'No puedes quitarte a ti mismo del equipo' using errcode = '22023'; end if;
  select rol into v_rol from public.miembros where organizacion_id = p_org and usuario_id = p_usuario;
  if not found then raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002'; end if;
  if v_rol = 'admin' and not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id <> p_usuario and rol = 'admin' and activo) then
    raise exception 'Debe quedar al menos un administrador' using errcode = '22023';
  end if;
  delete from public.miembros where organizacion_id = p_org and usuario_id = p_usuario;
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, (select auth.uid()), 'miembro.quitar', 'miembro', p_usuario::text, jsonb_build_object('rol', v_rol::text));
end $$;
revoke all on function public.quitar_miembro(uuid, uuid) from public, anon;
grant execute on function public.quitar_miembro(uuid, uuid) to authenticated;
