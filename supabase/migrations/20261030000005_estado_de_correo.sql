-- Estado de un correo para invitar: ¿ya tiene cuenta?, ¿la creó una invitación nuestra (clave_asignada)?, ¿ya está en OTRA organización?
-- Solo la Edge Function qhub-invite (service_role) la usa.
create or replace function public.estado_de_correo(p_email text, p_org uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((
    select jsonb_build_object(
      'existe', true,
      'id', u.id,
      'nuestra', coalesce((u.raw_app_meta_data ->> 'clave_asignada')::boolean, false),
      'en_otra_org', exists (select 1 from public.miembros m where m.usuario_id = u.id and m.organizacion_id <> p_org))
    from auth.users u where lower(u.email) = lower(trim(p_email)) limit 1
  ), jsonb_build_object('existe', false))
$$;
revoke all on function public.estado_de_correo(text, uuid) from public, anon, authenticated;
grant execute on function public.estado_de_correo(text, uuid) to service_role;
