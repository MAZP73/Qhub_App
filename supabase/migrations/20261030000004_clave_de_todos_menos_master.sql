-- guardar_clave_de_miembro: se guarda la contraseña vigente de todo el equipo MENOS la del master (la del dueño es privada).
-- Antes excluía a los admin, y entonces el master no podía ver la de un admin. Quien la ve sigue decidido en clave_inicial_de_miembro
-- (admin: su equipo; la propia persona: la suya). Un admin normal ve la de los no-admin; la de un admin la ve el master.
create or replace function public.guardar_clave_de_miembro(p_usuario uuid, p_clave text)
returns void language sql security definer set search_path = '' as $$
  insert into public.claves_asignadas (organizacion_id, usuario_id, clave)
  select m.organizacion_id, m.usuario_id, p_clave
  from public.miembros m join public.organizaciones o on o.id = m.organizacion_id
  where m.usuario_id = p_usuario and m.activo and not m.es_master and o.tipo = 'empresa'
  on conflict (organizacion_id, usuario_id) do update set clave = excluded.clave, creada_en = now()
$$;

-- Ver la clave de un administrador: solo el master (o la propia persona). A un no-admin lo ve cualquier admin.
create or replace function public.clave_inicial_de_miembro(p_org uuid, p_usuario uuid, p_solicitante uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_clave text; v_rol public.rol_organizacion; v_master boolean; v_soy_master boolean; v_soy_admin boolean;
begin
  select rol, es_master into v_rol, v_master from public.miembros where organizacion_id = p_org and usuario_id = p_usuario;
  if not found then raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002'; end if;
  select coalesce(bool_or(es_master), false), coalesce(bool_or(rol = 'admin'), false) into v_soy_master, v_soy_admin
    from public.miembros where organizacion_id = p_org and usuario_id = p_solicitante and activo;
  if p_solicitante is null or not (
    p_solicitante = p_usuario
    or (v_soy_master and not v_master)
    or (v_soy_admin and v_rol <> 'admin')
  ) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  select clave into v_clave from public.claves_asignadas where organizacion_id = p_org and usuario_id = p_usuario;
  return v_clave;
end $$;
