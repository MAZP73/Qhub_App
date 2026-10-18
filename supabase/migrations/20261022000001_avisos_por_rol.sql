-- Avisos para todos los roles: cada persona recibe los que le corresponden.
--   · administración (admin, supervisor): quién se une, clientes nuevos, quién sigue la organización (ya existían)
--   · quien se une: un aviso de bienvenida con su rol
--   · cualquier integrante: se le avisa cuando le cambian el rol
create or replace function public.avisar_usuario(p_usuario uuid, org uuid, p_tipo text, p_titulo text, p_mensaje text, p_ruta text)
returns void language sql security definer set search_path = '' as $$
  insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje, ruta) values (p_usuario, org, p_tipo, p_titulo, p_mensaje, p_ruta)
$$;
revoke all on function public.avisar_usuario(uuid, uuid, text, text, text, text) from public, anon, authenticated;

create or replace function public.etiqueta_rol(r public.rol_organizacion)
returns text language sql immutable set search_path = '' as $$
  select case r::text when 'admin' then 'administrador' when 'supervisor' then 'supervisor' when 'agente' then 'agente' when 'recepcion' then 'recepción' else r::text end
$$;

create or replace function public.trg_aviso_miembro() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_org text;
begin
  select nombre into v_org from public.organizaciones where id = new.organizacion_id;
  perform public.avisar_staff(new.organizacion_id, 'equipo', 'Nueva persona en el equipo',
    public.nombre_de(new.usuario_id) || ' se unió como ' || public.etiqueta_rol(new.rol) || '.', '/equipo', new.usuario_id);
  perform public.avisar_usuario(new.usuario_id, new.organizacion_id, 'equipo', 'Te damos la bienvenida',
    'Ya eres parte de ' || coalesce(v_org, 'el equipo') || ' con el rol de ' || public.etiqueta_rol(new.rol) || '.', '/inicio');
  return new;
end $$;

create or replace function public.trg_aviso_cambio_rol() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.rol is distinct from old.rol then
    perform public.avisar_usuario(new.usuario_id, new.organizacion_id, 'equipo', 'Cambió tu rol',
      'Ahora eres ' || public.etiqueta_rol(new.rol) || '. Verás las secciones que corresponden a ese rol.', '/inicio');
  end if;
  return new;
end $$;
drop trigger if exists aviso_cambio_rol on public.miembros;
create trigger aviso_cambio_rol after update of rol on public.miembros for each row execute function public.trg_aviso_cambio_rol();
