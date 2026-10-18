-- Quien no es miembro no tiene rol (null): las comprobaciones deben dar false, no null, para que `if not ...` los rechace.
create or replace function public.es_admin_o_supervisor(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.rol_en_organizacion(org) in ('admin', 'supervisor'), false) or public.es_superadmin()
$$;
create or replace function public.es_admin_org(org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.rol_en_organizacion(org) = 'admin', false) or public.es_superadmin()
$$;
