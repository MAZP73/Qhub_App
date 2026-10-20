-- editar_miembro: (1) el cargo pasa a ser obligatorio; (2) a un administrador solo lo edita el master (o él mismo);
-- al master no lo edita nadie más. Mismo resto de validaciones que la versión anterior.
create or replace function public.editar_miembro(p_org uuid, p_usuario uuid, p_nombre text, p_apellido text, p_cargo text, p_telefono text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_n text := nullif(trim(p_nombre), ''); v_a text := nullif(trim(p_apellido), ''); v_c text := nullif(trim(p_cargo), ''); v_t text := nullif(trim(p_telefono), '');
        v_uid uuid := (select auth.uid()); v_rol public.rol_organizacion; v_master boolean; v_soy_master boolean;
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  select rol, es_master into v_rol, v_master from public.miembros where organizacion_id = p_org and usuario_id = p_usuario;
  if not found then raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002'; end if;
  select exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = v_uid and es_master and activo) into v_soy_master;
  if p_usuario <> v_uid and (v_master or (v_rol = 'admin' and not v_soy_master)) then
    raise exception 'Solo el master puede editar a un administrador' using errcode = '42501';
  end if;
  if v_n is null or length(v_n) < 2 or length(v_n) > 60 or v_a is null or length(v_a) < 2 or length(v_a) > 60 then
    raise exception 'Revisa el nombre y el apellido' using errcode = '22023';
  end if;
  if v_c is null or length(v_c) not between 2 and 80 then raise exception 'Revisa el cargo' using errcode = '22023'; end if;
  if v_t is not null and v_t !~ '^\+?[0-9 ()-]{7,20}$' then raise exception 'Revisa el teléfono' using errcode = '22023'; end if;
  update public.perfiles set nombre = v_n, apellido = v_a, cargo = v_c, telefono = v_t where id = p_usuario;
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, v_uid, 'miembro.editar', 'perfil', p_usuario::text, '{}'::jsonb);
end $$;
