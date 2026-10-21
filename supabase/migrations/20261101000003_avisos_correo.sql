-- Avisos por correo (Brevo) de las acciones importantes, para cuentas web y móviles, y avisos propios de la cuenta del cliente.
-- Los eventos solo guardan una fila; la función qhub-correo (pg_cron, cada 30 s) reclama las pendientes y las envía.
-- Aditivo: lo existente no cambia; los avisos de equipo anteriores se marcan como enviados para no mandar correos viejos.

-- ───────── avisos de la cuenta del cliente (móvil) ─────────
create table public.avisos_cuenta (
  id               uuid primary key default gen_random_uuid(),
  usuario_id       uuid not null references auth.users(id) on delete cascade,
  tipo             text not null check (length(tipo) between 1 and 40),     -- bienvenida · vinculacion · desvinculacion · turno_creado · cita_creada
  titulo           text not null check (length(titulo) between 1 and 120),
  mensaje          text not null check (length(mensaje) <= 400),
  leida            boolean not null default false,
  creada_en        timestamptz not null default now(),
  correo_enviado_en timestamptz,
  correo_intentos  smallint not null default 0
);
create index avisos_cuenta_idx on public.avisos_cuenta (usuario_id, creada_en desc);
create unique index avisos_cuenta_bienvenida_uq on public.avisos_cuenta (usuario_id) where tipo = 'bienvenida';
alter table public.avisos_cuenta enable row level security;
create policy avisos_cuenta_select on public.avisos_cuenta for select to authenticated using (usuario_id = (select auth.uid()));
create policy avisos_cuenta_update on public.avisos_cuenta for update to authenticated using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
create policy avisos_cuenta_delete on public.avisos_cuenta for delete to authenticated using (usuario_id = (select auth.uid()));
grant select, delete on public.avisos_cuenta to authenticated;
grant update (leida) on public.avisos_cuenta to authenticated;              -- el contenido nunca se edita

-- ───────── cola de correo de los avisos del equipo (web) ─────────
alter table public.notificaciones_staff add column correo_enviado_en timestamptz, add column correo_intentos smallint not null default 0;
update public.notificaciones_staff set correo_enviado_en = now() where correo_enviado_en is null;   -- lo anterior no se envía por correo

-- Avisos de Qhub (API) ya enviados por correo, por persona y organización (los avisos de turno viven en la API).
create table public.avisos_correo_enviados (
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  aviso_id        text not null,
  enviado_en      timestamptz not null default now(),
  primary key (usuario_id, organizacion_id, aviso_id)
);
alter table public.avisos_correo_enviados enable row level security;

-- ───────── eventos que generan aviso ─────────
-- Bienvenida: cuando un cliente confirma su correo (o nace ya confirmado).
create or replace function public.trg_bienvenida_cliente() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email_confirmed_at is not null and (new.raw_app_meta_data ->> 'tipo_cuenta') = 'cliente' then
    insert into public.avisos_cuenta (usuario_id, tipo, titulo, mensaje)
    values (new.id, 'bienvenida', '¡Felicidades, tu cuenta está lista!',
            'Ya puedes buscar organizaciones, vincularte y sacar turno o reservar una cita desde la app de Qhub.')
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists bienvenida_cliente_ins on auth.users;
create trigger bienvenida_cliente_ins after insert on auth.users for each row execute function public.trg_bienvenida_cliente();
drop trigger if exists bienvenida_cliente_upd on auth.users;
create trigger bienvenida_cliente_upd after update of email_confirmed_at on auth.users for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null) execute function public.trg_bienvenida_cliente();

-- Vincularse / desvincularse de una organización.
create or replace function public.trg_aviso_vinculacion() returns trigger language plpgsql security definer set search_path = '' as $$
declare nombre text;
begin
  if coalesce(new.qhub_cola_id, old.qhub_cola_id) is not null then return null; end if;   -- solo la vinculación a la organización, no una cola favorita
  if tg_op = 'INSERT' then
    select o.nombre into nombre from public.organizaciones o where o.id = new.organizacion_id;
    insert into public.avisos_cuenta (usuario_id, tipo, titulo, mensaje)
    values (new.usuario_id, 'vinculacion', 'Te uniste a ' || coalesce(nombre, 'una organización'),
            'Ya puedes ver sus colas y sacar turno o reservar una cita en ' || coalesce(nombre, 'esta organización') || '.');
  else
    select o.nombre into nombre from public.organizaciones o where o.id = old.organizacion_id;
    if exists (select 1 from auth.users u where u.id = old.usuario_id) then
      insert into public.avisos_cuenta (usuario_id, tipo, titulo, mensaje)
      values (old.usuario_id, 'desvinculacion', 'Saliste de ' || coalesce(nombre, 'una organización'),
              'Ya no estás vinculado a ' || coalesce(nombre, 'esta organización') || '. Puedes volver a vincularte cuando quieras.');
    end if;
  end if;
  return null;
end $$;
drop trigger if exists aviso_vinculacion on public.favoritos;
create trigger aviso_vinculacion after insert or delete on public.favoritos for each row execute function public.trg_aviso_vinculacion();

-- ───────── reclamar correos pendientes (solo la Edge Function qhub-correo, con service_role) ─────────
-- Marca como enviados al reclamar (dos corridas nunca mandan el mismo) y cuenta el intento; hasta 3 intentos.
create or replace function public.reclamar_avisos_correo(p_limite integer default 30)
returns table (origen text, id uuid, usuario_id uuid, email text, titulo text, mensaje text, ruta text, tipo text)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with c as (
    update public.avisos_cuenta a set correo_enviado_en = now(), correo_intentos = a.correo_intentos + 1
    where a.id in (select x.id from public.avisos_cuenta x where x.correo_enviado_en is null and x.correo_intentos < 3 order by x.creada_en limit p_limite for update skip locked)
    returning 'cuenta'::text as origen, a.id, a.usuario_id, a.titulo, a.mensaje, null::text as ruta, a.tipo
  ), s as (
    update public.notificaciones_staff n set correo_enviado_en = now(), correo_intentos = n.correo_intentos + 1
    where n.id in (select x.id from public.notificaciones_staff x where x.correo_enviado_en is null and x.correo_intentos < 3 order by x.creada_en limit p_limite for update skip locked)
    returning 'staff'::text as origen, n.id, n.usuario_id, n.titulo, n.mensaje, n.ruta, n.tipo
  )
  select r.origen, r.id, r.usuario_id, u.email::text, r.titulo, r.mensaje, r.ruta, r.tipo
  from (select * from c union all select * from s) r join auth.users u on u.id = r.usuario_id;
end $$;
-- Si el envío falla, se devuelve a la cola (el contador de intentos ya cuenta).
create or replace function public.devolver_aviso_correo(p_origen text, p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_origen = 'cuenta' then update public.avisos_cuenta set correo_enviado_en = null where id = p_id;
  else update public.notificaciones_staff set correo_enviado_en = null where id = p_id; end if;
end $$;
revoke all on function public.reclamar_avisos_correo(integer), public.devolver_aviso_correo(text, uuid), public.trg_bienvenida_cliente(), public.trg_aviso_vinculacion() from public, anon, authenticated;
grant execute on function public.reclamar_avisos_correo(integer), public.devolver_aviso_correo(text, uuid) to service_role;
