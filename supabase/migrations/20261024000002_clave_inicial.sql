-- Contraseña inicial de quien es invitado: la asigna el administrador (o se genera sola) y la persona la VE en la pantalla de la invitación
-- para copiarla y guardarla. Vive solo hasta que acepta (o cancelan/vence la invitación) y nadie más puede leerla: sin permisos directos,
-- solo la función de abajo, y solo para el correo invitado.
create table public.claves_iniciales (
  invitacion_id uuid primary key references public.invitaciones(id) on delete cascade,
  clave         text not null,
  creada_en     timestamptz not null default now()
);
alter table public.claves_iniciales enable row level security;      -- sin políticas: ni siquiera el administrador la lee
revoke all on public.claves_iniciales from public, anon, authenticated;

create or replace function public.ver_clave_inicial(p_token text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_email text; v_clave text;
begin
  select u.email into v_email from auth.users u where u.id = (select auth.uid());
  select c.clave into v_clave from public.claves_iniciales c join public.invitaciones i on i.id = c.invitacion_id
   where i.token = p_token and i.aceptada_en is null and i.expira_en > now() and lower(i.email) = lower(v_email);
  return v_clave;
end $$;
revoke all on function public.ver_clave_inicial(text) from public, anon;
grant execute on function public.ver_clave_inicial(text) to authenticated;

create or replace function public.trg_borrar_clave_inicial() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.aceptada_en is not null then delete from public.claves_iniciales where invitacion_id = new.id; end if;
  return new;
end $$;
drop trigger if exists borrar_clave_inicial on public.invitaciones;
create trigger borrar_clave_inicial after update of aceptada_en on public.invitaciones for each row execute function public.trg_borrar_clave_inicial();
