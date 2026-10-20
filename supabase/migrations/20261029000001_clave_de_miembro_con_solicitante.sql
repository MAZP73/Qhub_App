-- Arregla clave_inicial_de_miembro: la Edge Function qhub-clave la llama con service_role, donde auth.uid() es nulo,
-- así que es_admin_org(p_org) siempre fallaba ("Sin permiso") y la función respondía 500.
-- Ahora recibe el solicitante (el usuario que la Edge Function ya verificó con su JWT) y la autorización sigue DENTRO
-- del SQL: debe ser admin ACTIVO de esa organización y la persona consultada debe pertenecer a ella.
-- Devuelve solo el TEXTO CIFRADO. Solo service_role puede ejecutarla.
drop function if exists public.clave_inicial_de_miembro(uuid, uuid);
create or replace function public.clave_inicial_de_miembro(p_org uuid, p_usuario uuid, p_solicitante uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_clave text;
begin
  if p_solicitante is null or not exists (
    select 1 from public.miembros m where m.organizacion_id = p_org and m.usuario_id = p_solicitante and m.activo and m.rol = 'admin'
  ) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = p_usuario) then
    raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002';
  end if;
  select clave into v_clave from public.claves_asignadas where organizacion_id = p_org and usuario_id = p_usuario;
  return v_clave;
end $$;
revoke all on function public.clave_inicial_de_miembro(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.clave_inicial_de_miembro(uuid, uuid, uuid) to service_role;
