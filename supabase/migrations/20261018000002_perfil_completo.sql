-- Perfil editable: ubicación y preferencias, y eliminación de la propia cuenta.
alter table public.perfiles
  add column if not exists pais         text check (pais is null or length(pais) = 2),   -- ISO 3166-1 alfa-2
  add column if not exists ciudad       text check (ciudad is null or length(ciudad) between 2 and 80),
  add column if not exists zona_horaria text check (zona_horaria is null or length(zona_horaria) between 3 and 64),
  add column if not exists cargo        text check (cargo is null or length(cargo) between 2 and 80);

alter table public.perfiles
  add constraint perfiles_telefono_formato check (telefono is null or telefono ~ '^\+?[0-9 ()-]{7,20}$') not valid;

grant update (nombre, apellido, telefono, avatar_url, pais, ciudad, zona_horaria, cargo) on public.perfiles to authenticated;

-- Elimina la cuenta de quien llama. Se niega si es el único administrador de una organización con más miembros
-- (habría que transferirla antes); si es el único miembro, la organización se elimina con él.
create or replace function public.eliminar_mi_cuenta()
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_org record;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  for v_org in
    select m.organizacion_id from public.miembros m
    where m.usuario_id = v_uid and m.rol = 'admin' and m.activo
      and not exists (select 1 from public.miembros o where o.organizacion_id = m.organizacion_id
                      and o.usuario_id <> v_uid and o.rol = 'admin' and o.activo)
  loop
    if exists (select 1 from public.miembros o where o.organizacion_id = v_org.organizacion_id and o.usuario_id <> v_uid) then
      raise exception 'Eres el único administrador de una organización con más miembros. Nombra otro administrador antes de eliminar tu cuenta.' using errcode = '23514';
    end if;
    delete from public.organizaciones where id = v_org.organizacion_id;
  end loop;
  delete from auth.users where id = v_uid;
end $$;
revoke all on function public.eliminar_mi_cuenta() from public, anon;
grant execute on function public.eliminar_mi_cuenta() to authenticated;
