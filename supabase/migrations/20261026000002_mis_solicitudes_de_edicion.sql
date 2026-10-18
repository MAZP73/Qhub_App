-- El cliente (móvil) ve las solicitudes de permiso que le hacen las organizaciones para editar sus datos y las aprueba o rechaza.
create or replace function public.mis_solicitudes_edicion()
returns table (id uuid, organizacion text, motivo text, creada_en timestamptz, vence_en timestamptz)
language sql stable security definer set search_path = '' as $$
  select s.id, o.nombre, s.motivo, s.creada_en, s.creada_en + interval '48 hours'
  from public.permisos_edicion_cliente s join public.organizaciones o on o.id = s.organizacion_id
  where s.cliente_id = (select auth.uid()) and s.estado = 'pendiente' and s.creada_en > now() - interval '48 hours'
  order by s.creada_en desc
$$;
revoke all on function public.mis_solicitudes_edicion() from public, anon;
grant execute on function public.mis_solicitudes_edicion() to authenticated;
