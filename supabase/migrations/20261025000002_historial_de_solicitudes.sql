-- Historial de solicitudes del equipo (contraseña, correo, datos) para el administrador: quién pidió qué, cuándo y qué pasó.
create or replace function public.historial_solicitudes(p_org uuid)
returns table (id uuid, usuario_id uuid, nombre text, tipo text, motivo text, resultado text, creada_en timestamptz, respondida_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  return query
  select s.id, s.usuario_id, public.nombre_de(s.usuario_id), s.tipo, s.motivo,
         case when s.estado = 'usada' and s.tipo = 'datos' then 'atendida'
              when s.estado = 'aprobada' and s.respondida_en < now() - interval '24 hours' then 'vencida'
              when s.estado = 'pendiente' and s.creada_en < now() - interval '30 days' then 'vencida'
              else s.estado end,
         s.creada_en, s.respondida_en
  from public.solicitudes_miembros s
  where s.organizacion_id = p_org and s.estado <> 'pendiente'
  order by coalesce(s.respondida_en, s.creada_en) desc limit 100;
end $$;
revoke all on function public.historial_solicitudes(uuid) from public, anon;
grant execute on function public.historial_solicitudes(uuid) to authenticated;
