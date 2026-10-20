-- Quitar a alguien del equipo borra también su cuenta cuando la creó una invitación nuestra (clave_asignada) y no pertenece a ninguna
-- otra organización: si después se registra con ese correo entra como persona nueva. Una cuenta que la persona ya tenía por su cuenta
-- (p. ej. de la app móvil) NO se borra: solo termina su pertenencia al equipo. Mismas reglas de permiso que antes (y el trigger del master).
create or replace function public.quitar_miembro(p_org uuid, p_usuario uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol public.rol_organizacion; v_nuestra boolean;
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
  select coalesce((u.raw_app_meta_data ->> 'clave_asignada')::boolean, false) into v_nuestra from auth.users u where u.id = p_usuario;
  if coalesce(v_nuestra, false) and not exists (select 1 from public.miembros where usuario_id = p_usuario) then
    delete from public.invitaciones where organizacion_id = p_org and lower(email) = (select lower(email) from auth.users where id = p_usuario);
    delete from auth.users where id = p_usuario;
  end if;
end $$;
revoke all on function public.quitar_miembro(uuid, uuid) from public, anon;
grant execute on function public.quitar_miembro(uuid, uuid) to authenticated;
