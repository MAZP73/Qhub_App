-- La lista de clientes no se duplica cuando alguien guarda varias colas como favoritas.
-- Lista agregada de las personas que usan la organización desde el móvil.
-- Contacto (correo, teléfono) solo para administradores; el supervisor ve nombre y actividad.
create or replace function public.clientes_organizacion(p_org uuid)
returns table (usuario_id uuid, nombre text, apellido text, email text, telefono text, primera_vez timestamptz, ultimo_turno timestamptz,
               turnos integer, atendidos integer, no_show integer, cancelados integer, sigue boolean, bloqueado boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_admin boolean;
begin
  if not public.es_admin_o_supervisor(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  v_admin := public.es_admin_org(p_org);
  return query
  with base as (
    select h.usuario_id as uid from public.historial_turnos h where h.organizacion_id = p_org
    union select f.usuario_id from public.favoritos f where f.organizacion_id = p_org
  ), agg as (
    select h.usuario_id as uid, min(h.creado_en) as primera, max(h.creado_en) as ultimo, count(*)::int as n,
           count(*) filter (where h.estado = 'finalizado')::int as ok, count(*) filter (where h.estado = 'no_show')::int as ns,
           count(*) filter (where h.estado = 'cancelado')::int as ca
    from public.historial_turnos h where h.organizacion_id = p_org group by h.usuario_id
  )
  select b.uid, p.nombre, p.apellido,
         case when v_admin then u.email::text else null end, case when v_admin then p.telefono else null end,
         coalesce(a.primera, f.desde), a.ultimo, coalesce(a.n, 0), coalesce(a.ok, 0), coalesce(a.ns, 0), coalesce(a.ca, 0),
         (f.desde is not null), (x.usuario_id is not null)
  from base b
  join public.perfiles p on p.id = b.uid
  left join auth.users u on u.id = b.uid
  left join agg a on a.uid = b.uid
  left join lateral (select min(ff.creado_en) as desde from public.favoritos ff where ff.usuario_id = b.uid and ff.organizacion_id = p_org) f on true
  left join public.clientes_bloqueados x on x.usuario_id = b.uid and x.organizacion_id = p_org
  order by coalesce(a.ultimo, f.desde) desc nulls last;
end $$;
revoke all on function public.clientes_organizacion(uuid) from public, anon;
grant execute on function public.clientes_organizacion(uuid) to authenticated;
