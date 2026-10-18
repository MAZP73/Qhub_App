-- Tipo de cuenta: una persona natural (espacio personal, sin equipo) o una organización/empresa (con equipo y roles).
-- Coincide con los dos tipos de cuenta de la API Qhub (persona = `usuario`, 3 colas; empresa = `empresa`, 6 colas).
create type public.tipo_cuenta as enum ('persona', 'empresa');
alter table public.organizaciones add column tipo public.tipo_cuenta not null default 'empresa';
-- `tipo` se elige al crear y no se edita: el grant de columnas de `organizaciones` no lo incluye.

drop function if exists public.crear_organizacion(text, text, text, text, text);
create or replace function public.crear_organizacion(
  p_nombre text, p_slug text, p_ciudad text default null, p_pais text default null,
  p_zona_horaria text default 'America/Guayaquil', p_tipo public.tipo_cuenta default 'empresa')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  insert into public.organizaciones (nombre, slug, ciudad, pais, zona_horaria, tipo)
  values (p_nombre, p_slug, p_ciudad, p_pais, p_zona_horaria, p_tipo) returning id into v_id;
  insert into public.miembros (organizacion_id, usuario_id, rol) values (v_id, v_uid, 'admin');
  insert into public.ajustes_organizacion (organizacion_id) values (v_id);
  return v_id;
end $$;
revoke all on function public.crear_organizacion(text, text, text, text, text, public.tipo_cuenta) from public, anon;
grant execute on function public.crear_organizacion(text, text, text, text, text, public.tipo_cuenta) to authenticated;

-- Una cuenta personal no tiene equipo: no admite invitaciones ni más miembros que su titular.
create or replace function public.trg_sin_equipo_en_persona() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_tipo public.tipo_cuenta;
begin
  select tipo into v_tipo from public.organizaciones where id = new.organizacion_id;
  if v_tipo = 'persona' then raise exception 'Una cuenta personal no tiene equipo. Crea una organización para invitar personas.' using errcode = '23514'; end if;
  return new;
end $$;
create trigger sin_invitaciones_en_persona before insert on public.invitaciones for each row execute function public.trg_sin_equipo_en_persona();

-- El primer miembro (el titular, al crearla) sí entra; ninguno más.
create or replace function public.trg_un_solo_miembro_en_persona() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_tipo public.tipo_cuenta;
begin
  select tipo into v_tipo from public.organizaciones where id = new.organizacion_id;
  if v_tipo = 'persona' and exists (select 1 from public.miembros m where m.organizacion_id = new.organizacion_id and m.usuario_id <> new.usuario_id) then
    raise exception 'Una cuenta personal no tiene equipo. Crea una organización para invitar personas.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger un_solo_miembro_en_persona before insert on public.miembros for each row execute function public.trg_un_solo_miembro_en_persona();
