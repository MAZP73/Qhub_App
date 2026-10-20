-- Aviso al administrador cuando un integrante NO admin no pudo reconectar la cuenta de Qhub
-- (la credencial solo la conoce el admin). Lo llama la web (miembro activo). Seguridad DENTRO del SQL:
-- debe ser miembro activo de la organización; el aviso se inserta solo para los admin activos.
-- De-dupe: no repetir si ya hay un aviso igual sin leer en las últimas 6 horas.
create or replace function public.avisar_reconexion_qhub(p_org uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_nombre text; v_insertados int;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  -- Autorización: miembro ACTIVO de esa organización (cualquier rol). Inline a propósito:
  -- es_miembro aceptaría a un superadmin ajeno; aquí el aviso solo tiene sentido para un integrante real.
  if not exists (select 1 from public.miembros m where m.organizacion_id = p_org and m.usuario_id = v_uid and m.activo) then
    raise exception 'Sin permiso' using errcode = '42501';
  end if;
  v_nombre := public.nombre_de(v_uid);
  -- Inserta para los admin ACTIVOS, saltando a quien ya tiene un aviso igual sin leer reciente (de-dupe).
  with destinatarios as (
    select m.usuario_id
    from public.miembros m
    where m.organizacion_id = p_org and m.activo and m.rol = 'admin'
      and not exists (
        select 1 from public.notificaciones_staff n
        where n.usuario_id = m.usuario_id
          and n.organizacion_id = p_org
          and n.tipo = 'sistema'
          and n.titulo = 'Falta reconectar con Qhub'
          and n.leida = false
          and n.creada_en > now() - interval '6 hours'
      )
  )
  insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje, ruta)
  select d.usuario_id, p_org, 'sistema', 'Falta reconectar con Qhub',
         left(v_nombre || ' no pudo usar las colas y turnos: la conexión con Qhub dejó de funcionar. Vuelve a conectar la cuenta en Ajustes.', 400),
         '/ajustes'
  from destinatarios d;
  get diagnostics v_insertados = row_count;
  return v_insertados > 0;  -- true si se avisó a alguien; false si todo estaba de-dupeado
end $$;
revoke all on function public.avisar_reconexion_qhub(uuid) from public, anon;
grant execute on function public.avisar_reconexion_qhub(uuid) to authenticated;
