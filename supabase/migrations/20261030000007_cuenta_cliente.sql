-- ¿Este correo es de un cliente de la app móvil? Solo lo es si su cuenta trae app_metadata.tipo_cuenta='cliente'
-- (lo estampa qhub-registro-cliente con service_role; el cliente no puede escribirlo). La app móvil es solo para clientes:
-- un correo del staff (web) o uno inexistente NO pasa la puerta. Solo la Edge Function qhub-sesion-cliente (service_role) la usa.
create or replace function public.es_correo_cliente(p_email text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select (u.raw_app_meta_data ->> 'tipo_cuenta') = 'cliente'
    from auth.users u where lower(u.email) = lower(trim(p_email)) limit 1
  ), false)
$$;
revoke all on function public.es_correo_cliente(text) from public, anon, authenticated;
grant execute on function public.es_correo_cliente(text) to service_role;

-- Relleno único e idempotente: las cuentas del público que ya existían (no son staff, no nacieron de una invitación nuestra
-- y no son superadmin de la plataforma) quedan marcadas como 'cliente'. Reejecutarlo no cambia nada (el where ya las excluye).
-- Aditivo: no toca ninguna tabla/columna/enum/RLS/permiso existente.
update auth.users u
set raw_app_meta_data = jsonb_set(coalesce(u.raw_app_meta_data, '{}'::jsonb), '{tipo_cuenta}', '"cliente"', true)
where (u.raw_app_meta_data ->> 'tipo_cuenta') is distinct from 'cliente'
  and coalesce((u.raw_app_meta_data ->> 'clave_asignada')::boolean, false) is not true
  and not exists (select 1 from public.miembros m where m.usuario_id = u.id)
  and not exists (select 1 from public.perfiles p where p.id = u.id and p.rol = 'superadmin');
