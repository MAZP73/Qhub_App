-- Avisos para el equipo, clientes de la organización (personas de la app móvil) y bloqueo de clientes.

create or replace function public.es_admin_o_supervisor(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.rol_en_organizacion(org) in ('admin', 'supervisor'), false) or public.es_superadmin()
$$;
revoke all on function public.es_admin_o_supervisor(uuid) from public, anon;
grant execute on function public.es_admin_o_supervisor(uuid) to authenticated;

-- ───────── avisos del equipo (campana de la web) ─────────
create table public.notificaciones_staff (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,      -- destinatario
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  tipo            text not null check (tipo in ('equipo', 'cliente', 'sistema')),
  titulo          text not null check (length(titulo) between 1 and 120),
  mensaje         text not null check (length(mensaje) <= 400),
  ruta            text check (ruta is null or ruta ~ '^/[a-z0-9/_-]*$'),               -- a dónde lleva en la web
  leida           boolean not null default false,
  creada_en       timestamptz not null default now()
);
create index notificaciones_staff_idx on public.notificaciones_staff (usuario_id, leida, creada_en desc);
alter table public.notificaciones_staff enable row level security;
create policy avisos_select on public.notificaciones_staff for select to authenticated using (usuario_id = (select auth.uid()));
create policy avisos_update on public.notificaciones_staff for update to authenticated using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
create policy avisos_delete on public.notificaciones_staff for delete to authenticated using (usuario_id = (select auth.uid()));
grant select, delete on public.notificaciones_staff to authenticated;
grant update (leida) on public.notificaciones_staff to authenticated;   -- el contenido nunca se edita

create or replace function public.avisar_staff(org uuid, p_tipo text, p_titulo text, p_mensaje text, p_ruta text, excepto uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje, ruta)
  select m.usuario_id, org, p_tipo, p_titulo, p_mensaje, p_ruta
  from public.miembros m
  where m.organizacion_id = org and m.activo and m.rol in ('admin', 'supervisor') and m.usuario_id is distinct from excepto
$$;
revoke all on function public.avisar_staff(uuid, text, text, text, text, uuid) from public, anon, authenticated;

create or replace function public.nombre_de(p uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(trim(concat_ws(' ', nombre, apellido)), ''), 'Una persona') from public.perfiles where id = p
$$;
revoke all on function public.nombre_de(uuid) from public, anon, authenticated;

create or replace function public.trg_aviso_miembro() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.avisar_staff(new.organizacion_id, 'equipo', 'Nueva persona en el equipo',
    public.nombre_de(new.usuario_id) || ' se unió como ' || new.rol::text || '.', '/equipo', new.usuario_id);
  return new;
end $$;
create trigger aviso_miembro after insert on public.miembros for each row execute function public.trg_aviso_miembro();

create or replace function public.trg_aviso_favorito() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.avisar_staff(new.organizacion_id, 'cliente', 'Alguien sigue tu organización',
    public.nombre_de(new.usuario_id) || ' guardó tu organización en la app móvil.', '/clientes', null);
  return new;
end $$;
create trigger aviso_favorito after insert on public.favoritos for each row execute function public.trg_aviso_favorito();

create or replace function public.trg_aviso_primer_turno() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.historial_turnos h where h.organizacion_id = new.organizacion_id and h.usuario_id = new.usuario_id and h.id <> new.id) then
    perform public.avisar_staff(new.organizacion_id, 'cliente', 'Cliente nuevo',
      public.nombre_de(new.usuario_id) || ' sacó su primer turno' || coalesce(' en ' || new.cola_nombre, '') || '.', '/clientes', null);
  end if;
  return new;
end $$;
create trigger aviso_primer_turno after insert on public.historial_turnos for each row execute function public.trg_aviso_primer_turno();

-- ───────── clientes de la organización ─────────
create table public.clientes_bloqueados (
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  motivo          text check (motivo is null or length(motivo) <= 200),
  bloqueado_por   uuid references public.perfiles(id) on delete set null,
  creado_en       timestamptz not null default now(),
  primary key (organizacion_id, usuario_id)
);
alter table public.clientes_bloqueados enable row level security;
create policy bloqueados_select on public.clientes_bloqueados for select to authenticated using (public.es_admin_o_supervisor(organizacion_id));
create policy bloqueados_write on public.clientes_bloqueados for all to authenticated using (public.es_admin_org(organizacion_id)) with check (public.es_admin_org(organizacion_id) and bloqueado_por = (select auth.uid()));
grant select, insert, update, delete on public.clientes_bloqueados to authenticated;

-- El historial de la organización lo ve su administración (el cliente sigue viendo solo el suyo).
create policy historial_select_staff on public.historial_turnos for select to authenticated using (public.es_admin_o_supervisor(organizacion_id));

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
