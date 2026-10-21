-- La búsqueda y «mis organizaciones» ahora dicen si es una empresa o una cuenta personal (persona natural), para mostrarlo y filtrarlo en la app.
-- Aditivo: solo se agrega la columna `tipo` al final de lo que ya devuelven.
drop function if exists public.buscar_organizaciones(text);
create or replace function public.buscar_organizaciones(p_q text)
returns table (id uuid, nombre text, slug text, codigo text, descripcion text, direccion text, ciudad text, pais text, telefono text, latitud double precision, longitud double precision, vinculada boolean, tipo text)
language sql stable set search_path = '' as $$
  with q as (select nullif(trim(coalesce(p_q, '')), '') as t)
  select o.id, o.nombre, o.slug, o.codigo, o.descripcion, o.direccion, o.ciudad, o.pais, o.telefono, o.latitud, o.longitud,
         exists (select 1 from public.favoritos f where f.organizacion_id = o.id and f.usuario_id = (select auth.uid())) as vinculada,
         o.tipo::text
  from public.organizaciones o, q
  where o.publica and o.activa
    and (q.t is null
         or o.nombre ilike '%' || replace(replace(replace(q.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or o.ciudad ilike '%' || replace(replace(replace(q.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or o.direccion ilike '%' || replace(replace(replace(q.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
         or upper(o.codigo) = upper(q.t) or upper(o.codigo) = 'QH-' || upper(q.t)
         or o.id::text = lower(q.t) or o.slug = lower(q.t))
  order by o.nombre limit 100
$$;
revoke all on function public.buscar_organizaciones(text) from public, anon;
grant execute on function public.buscar_organizaciones(text) to authenticated;

drop function if exists public.mis_organizaciones();
create or replace function public.mis_organizaciones()
returns table (id uuid, nombre text, slug text, codigo text, descripcion text, direccion text, ciudad text, pais text, telefono text, latitud double precision, longitud double precision, vinculada boolean, tipo text)
language sql stable set search_path = '' as $$
  select o.id, o.nombre, o.slug, o.codigo, o.descripcion, o.direccion, o.ciudad, o.pais, o.telefono, o.latitud, o.longitud, true, o.tipo::text
  from public.organizaciones o
  where o.publica and o.activa and exists (select 1 from public.favoritos f where f.organizacion_id = o.id and f.usuario_id = (select auth.uid()))
  order by o.nombre
$$;
revoke all on function public.mis_organizaciones() from public, anon;
grant execute on function public.mis_organizaciones() to authenticated;
