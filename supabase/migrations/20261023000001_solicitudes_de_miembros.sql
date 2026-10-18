-- Solicitudes de una persona del equipo a su administrador:
--   contrasena  pedir permiso para cambiar su contraseña (cuando el administrador se la asignó al invitarla)
--   datos       pedir que el administrador cambie o corrija sus datos
-- Una solicitud en curso por persona y tipo. El permiso de contraseña vale 24 h y para un solo cambio.
create table public.solicitudes_miembros (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  tipo            text not null check (tipo in ('contrasena', 'datos')),
  motivo          text check (motivo is null or length(motivo) <= 300),
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'aprobada', 'rechazada', 'usada')),
  creada_en       timestamptz not null default now(),
  respondida_en   timestamptz
);
create unique index solicitudes_miembros_en_curso on public.solicitudes_miembros (organizacion_id, usuario_id, tipo) where estado in ('pendiente', 'aprobada');
alter table public.solicitudes_miembros enable row level security;
create policy solicitudes_select on public.solicitudes_miembros for select to authenticated using (usuario_id = (select auth.uid()) or public.es_admin_org(organizacion_id));
grant select on public.solicitudes_miembros to authenticated;

create or replace function public.solicitar_cambio_miembro(p_org uuid, p_tipo text, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if p_tipo not in ('contrasena', 'datos') then raise exception 'Revisa los datos' using errcode = '22023'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = v_uid and activo) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  -- una aprobada que ya pasó de 24 h deja de contar
  update public.solicitudes_miembros set estado = 'usada' where organizacion_id = p_org and usuario_id = v_uid and tipo = 'contrasena' and estado = 'aprobada' and respondida_en < now() - interval '24 hours';
  insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, motivo) values (p_org, v_uid, p_tipo, nullif(left(trim(coalesce(p_motivo, '')), 300), '')) returning id into v_id;
  perform public.avisar_staff(p_org, 'equipo', case p_tipo when 'contrasena' then 'Piden cambiar su contraseña' else 'Piden cambiar sus datos' end,
    public.nombre_de(v_uid) || ' envió una solicitud. Revísala en Equipo.', '/equipo', v_uid);
  return v_id;
exception when unique_violation then raise exception 'Ya tienes una solicitud en curso' using errcode = '23505';
end $$;
revoke all on function public.solicitar_cambio_miembro(uuid, text, text) from public, anon;
grant execute on function public.solicitar_cambio_miembro(uuid, text, text) to authenticated;

-- Lo que ve el administrador: solicitudes pendientes de su equipo.
create or replace function public.solicitudes_pendientes(p_org uuid)
returns table (id uuid, usuario_id uuid, nombre text, tipo text, motivo text, creada_en timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  return query select s.id, s.usuario_id, public.nombre_de(s.usuario_id), s.tipo, s.motivo, s.creada_en
    from public.solicitudes_miembros s where s.organizacion_id = p_org and s.estado = 'pendiente' order by s.creada_en;
end $$;
revoke all on function public.solicitudes_pendientes(uuid) from public, anon;
grant execute on function public.solicitudes_pendientes(uuid) to authenticated;

create or replace function public.responder_solicitud_miembro(p_id uuid, p_aprobar boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.solicitudes_miembros;
begin
  select * into v from public.solicitudes_miembros where id = p_id and estado = 'pendiente' for update;
  if not found then raise exception 'La solicitud ya no está disponible' using errcode = 'P0002'; end if;
  if not public.es_admin_org(v.organizacion_id) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.solicitudes_miembros set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, respondida_en = now() where id = p_id;
  -- «datos» no es un permiso: se atiende editando el perfil, así que aprobar = atendida.
  if v.tipo = 'datos' and p_aprobar then update public.solicitudes_miembros set estado = 'usada' where id = p_id; end if;
  perform public.avisar_usuario(v.usuario_id, v.organizacion_id, 'equipo',
    case when p_aprobar then 'Tu solicitud fue aprobada' else 'Tu solicitud no fue aprobada' end,
    case when p_aprobar and v.tipo = 'contrasena' then 'Ya puedes cambiar tu contraseña en Mi perfil → Seguridad durante las próximas 24 horas.'
         when p_aprobar then 'El administrador atendió tu solicitud.' else 'El administrador no aprobó tu solicitud. Puedes hablar con él para saber por qué.' end, '/perfil');
end $$;
revoke all on function public.responder_solicitud_miembro(uuid, boolean) from public, anon;
grant execute on function public.responder_solicitud_miembro(uuid, boolean) to authenticated;

-- Estado de MI permiso de contraseña (para la pantalla de Seguridad).
create or replace function public.mi_permiso(p_org uuid, p_tipo text)
returns table (estado text, creada_en timestamptz, vence_en timestamptz)
language sql stable security definer set search_path = '' as $$
  select case when s.estado = 'aprobada' and s.respondida_en < now() - interval '24 hours' then 'vencida' else s.estado end, s.creada_en,
         case when s.estado = 'aprobada' then s.respondida_en + interval '24 hours' end
  from public.solicitudes_miembros s where s.organizacion_id = p_org and s.usuario_id = (select auth.uid()) and s.tipo = p_tipo order by s.creada_en desc limit 1
$$;
revoke all on function public.mi_permiso(uuid, text) from public, anon;
grant execute on function public.mi_permiso(uuid, text) to authenticated;

-- Gasta el permiso de contraseña (un cambio). Devuelve false si no había uno vigente.
create or replace function public.usar_permiso_contrasena(p_org uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v uuid;
begin
  select id into v from public.solicitudes_miembros where organizacion_id = p_org and usuario_id = (select auth.uid()) and tipo = 'contrasena' and estado = 'aprobada' and respondida_en > now() - interval '24 hours' for update;
  if v is null then return false; end if;
  update public.solicitudes_miembros set estado = 'usada' where id = v;
  return true;
end $$;
revoke all on function public.usar_permiso_contrasena(uuid) from public, anon;
grant execute on function public.usar_permiso_contrasena(uuid) to authenticated;
