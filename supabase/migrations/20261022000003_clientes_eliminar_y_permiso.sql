-- Clientes (personas de la app móvil): la organización solo puede ELIMINARLOS de su lista.
-- Cambiar sus datos (nombre, apellido, teléfono) exige el permiso del cliente: la organización lo solicita, el cliente lo aprueba
-- (desde la app móvil) y el permiso sirve para UN cambio dentro de las 24 h siguientes.

create table public.permisos_edicion_cliente (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  cliente_id      uuid not null references public.perfiles(id) on delete cascade,
  solicitada_por  uuid references public.perfiles(id) on delete set null,
  motivo          text check (motivo is null or length(motivo) <= 200),
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada', 'usada')),
  creada_en       timestamptz not null default now(),
  respondida_en   timestamptz
);
create unique index permisos_edicion_pendiente_unico on public.permisos_edicion_cliente (organizacion_id, cliente_id) where estado in ('pendiente', 'aprobada');
alter table public.permisos_edicion_cliente enable row level security;
-- El cliente ve las solicitudes dirigidas a él; la organización las suyas (sin escribir directamente: todo por funciones).
create policy permisos_cliente_select on public.permisos_edicion_cliente for select to authenticated
  using (cliente_id = (select auth.uid()) or public.es_admin_org(organizacion_id));
grant select on public.permisos_edicion_cliente to authenticated;

create or replace function public.es_cliente_de(p_org uuid, p_cliente uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.historial_turnos h where h.organizacion_id = p_org and h.usuario_id = p_cliente)
      or exists (select 1 from public.favoritos f where f.organizacion_id = p_org and f.usuario_id = p_cliente)
$$;
revoke all on function public.es_cliente_de(uuid, uuid) from public, anon, authenticated;

-- ELIMINAR: borra lo que la organización tiene de esa persona (su historial de turnos allí y que la sigue). La cuenta de la persona no se toca.
create or replace function public.eliminar_cliente(p_org uuid, p_cliente uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not public.es_cliente_de(p_org, p_cliente) then raise exception 'No encontramos a ese cliente' using errcode = 'P0002'; end if;
  delete from public.historial_turnos where organizacion_id = p_org and usuario_id = p_cliente;
  delete from public.favoritos where organizacion_id = p_org and usuario_id = p_cliente;
  delete from public.permisos_edicion_cliente where organizacion_id = p_org and cliente_id = p_cliente and estado in ('pendiente', 'aprobada');
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, (select auth.uid()), 'cliente.eliminar', 'cliente', p_cliente::text, '{}'::jsonb);
end $$;
revoke all on function public.eliminar_cliente(uuid, uuid) from public, anon;
grant execute on function public.eliminar_cliente(uuid, uuid) to authenticated;

-- SOLICITAR permiso para editar.
create or replace function public.solicitar_edicion_cliente(p_org uuid, p_cliente uuid, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not public.es_cliente_de(p_org, p_cliente) then raise exception 'No encontramos a ese cliente' using errcode = 'P0002'; end if;
  -- Una solicitud pendiente vence a las 48 h; una aprobada, a las 24 h de responderla.
  update public.permisos_edicion_cliente set estado = 'rechazada', respondida_en = now()
   where organizacion_id = p_org and cliente_id = p_cliente and estado = 'pendiente' and creada_en < now() - interval '48 hours';
  update public.permisos_edicion_cliente set estado = 'usada'
   where organizacion_id = p_org and cliente_id = p_cliente and estado = 'aprobada' and respondida_en < now() - interval '24 hours';
  insert into public.permisos_edicion_cliente (organizacion_id, cliente_id, solicitada_por, motivo)
  values (p_org, p_cliente, (select auth.uid()), nullif(left(trim(coalesce(p_motivo, '')), 200), ''))
  returning id into v_id;
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, (select auth.uid()), 'cliente.solicitar_edicion', 'cliente', p_cliente::text, '{}'::jsonb);
  return v_id;
exception when unique_violation then raise exception 'Ya hay una solicitud en curso para este cliente' using errcode = '23505';
end $$;
revoke all on function public.solicitar_edicion_cliente(uuid, uuid, text) from public, anon;
grant execute on function public.solicitar_edicion_cliente(uuid, uuid, text) to authenticated;

-- Estado de la última solicitud (para la organización).
create or replace function public.estado_edicion_cliente(p_org uuid, p_cliente uuid)
returns table (estado text, creada_en timestamptz, vence_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  return query
  select case when x.estado = 'pendiente' and x.creada_en < now() - interval '48 hours' then 'vencida'
              when x.estado = 'aprobada' and x.respondida_en < now() - interval '24 hours' then 'vencida' else x.estado end,
         x.creada_en,
         case when x.estado = 'pendiente' then x.creada_en + interval '48 hours' when x.estado = 'aprobada' then x.respondida_en + interval '24 hours' end
  from public.permisos_edicion_cliente x
  where x.organizacion_id = p_org and x.cliente_id = p_cliente order by x.creada_en desc limit 1;
end $$;
revoke all on function public.estado_edicion_cliente(uuid, uuid) from public, anon;
grant execute on function public.estado_edicion_cliente(uuid, uuid) to authenticated;

-- RESPONDER (lo hace el cliente, desde la app móvil).
create or replace function public.responder_edicion_cliente(p_id uuid, p_aprobar boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.permisos_edicion_cliente
     set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, respondida_en = now()
   where id = p_id and cliente_id = (select auth.uid()) and estado = 'pendiente' and creada_en > now() - interval '48 hours';
  if not found then raise exception 'La solicitud ya no está disponible' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.responder_edicion_cliente(uuid, boolean) from public, anon;
grant execute on function public.responder_edicion_cliente(uuid, boolean) to authenticated;

-- EDITAR: solo con un permiso aprobado y vigente; se usa una vez.
create or replace function public.editar_cliente(p_org uuid, p_cliente uuid, p_nombre text, p_apellido text, p_telefono text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_perm uuid; v_n text := nullif(trim(p_nombre), ''); v_a text := nullif(trim(p_apellido), ''); v_t text := nullif(trim(p_telefono), '');
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  select id into v_perm from public.permisos_edicion_cliente
   where organizacion_id = p_org and cliente_id = p_cliente and estado = 'aprobada' and respondida_en > now() - interval '24 hours'
   order by creada_en desc limit 1 for update;
  if v_perm is null then raise exception 'El cliente no ha dado su permiso' using errcode = '42501'; end if;
  if v_n is null or length(v_n) not between 2 and 60 or v_a is null or length(v_a) not between 2 and 60 then raise exception 'Revisa el nombre y el apellido' using errcode = '22023'; end if;
  if v_t is not null and v_t !~ '^\+?[0-9 ()-]{7,20}$' then raise exception 'Revisa el teléfono' using errcode = '22023'; end if;
  update public.perfiles set nombre = v_n, apellido = v_a, telefono = v_t where id = p_cliente;
  update public.permisos_edicion_cliente set estado = 'usada' where id = v_perm;
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle)
  values (p_org, (select auth.uid()), 'cliente.editar', 'cliente', p_cliente::text, '{}'::jsonb);
end $$;
revoke all on function public.editar_cliente(uuid, uuid, text, text, text) from public, anon;
grant execute on function public.editar_cliente(uuid, uuid, text, text, text) to authenticated;
