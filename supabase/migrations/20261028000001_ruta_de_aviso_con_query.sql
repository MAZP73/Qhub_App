-- La columna `ruta` de los avisos debe poder apuntar a una sección con pestaña (deep-link),
-- p. ej. /perfil?tab=seguridad. Se relaja el CHECK para admitir un query simple
-- (?clave=valor&...) con los mismos caracteres seguros. Idempotente.
alter table public.notificaciones_staff drop constraint if exists notificaciones_staff_ruta_check;
alter table public.notificaciones_staff
  add constraint notificaciones_staff_ruta_check
  check (ruta is null or ruta ~ '^/[a-z0-9/_-]*(\?[a-z0-9_=&-]*)?$');

-- Reapuntar los avisos de permiso/solicitud a la zona de Seguridad del perfil.
-- Se redefine `responder_solicitud_miembro` (la última definición manda) para que, cuando la
-- solicitud sea de contraseña o correo, el aviso al integrante lleve a '/perfil?tab=seguridad';
-- en otro caso conserva '/perfil'. El cuerpo es idéntico al vigente en
-- 20261025000001_solicitud_cambio_de_correo.sql salvo el último argumento de avisar_usuario.
create or replace function public.responder_solicitud_miembro(p_id uuid, p_aprobar boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.solicitudes_miembros;
begin
  select * into v from public.solicitudes_miembros where id = p_id and estado = 'pendiente' for update;
  if not found then raise exception 'La solicitud ya no está disponible' using errcode = 'P0002'; end if;
  if not public.es_admin_org(v.organizacion_id) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.solicitudes_miembros set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, respondida_en = now() where id = p_id;
  if v.tipo = 'datos' and p_aprobar then update public.solicitudes_miembros set estado = 'usada' where id = p_id; end if;
  perform public.avisar_usuario(v.usuario_id, v.organizacion_id, 'equipo',
    case when p_aprobar then 'Tu solicitud fue aprobada' else 'Tu solicitud no fue aprobada' end,
    case when p_aprobar and v.tipo = 'contrasena' then 'Ya puedes cambiar tu contraseña en Mi perfil → Seguridad durante las próximas 24 horas.'
         when p_aprobar and v.tipo = 'correo' then 'Ya puedes cambiar tu correo en Mi perfil → Seguridad durante las próximas 24 horas.'
         when p_aprobar then 'El administrador atendió tu solicitud.' else 'El administrador no aprobó tu solicitud. Puedes hablar con él para saber por qué.' end,
    case when v.tipo in ('contrasena','correo') then '/perfil?tab=seguridad' else '/perfil' end);
end $$;
