-- Móvil como una red social de organizaciones: la persona BUSCA una organización por nombre o por su ID, se VINCULA y pasa a ser cliente suyo
-- (aparece en su lista de clientes). Una persona puede estar vinculada a varias organizaciones. Solo vinculada ve las colas y saca turnos.

-- ID público corto de cada organización (para buscarla y compartirla): QH-XXXXXX, sin letras que se confunden.
alter table public.organizaciones add column if not exists codigo text;
create or replace function public.generar_codigo_org() returns text language plpgsql volatile set search_path = '' as $$
declare alfabeto constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v text; i int;
begin
  loop
    v := 'QH-';
    for i in 1..6 loop v := v || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1); end loop;
    exit when not exists (select 1 from public.organizaciones where codigo = v);
  end loop;
  return v;
end $$;
update public.organizaciones set codigo = public.generar_codigo_org() where codigo is null;
alter table public.organizaciones alter column codigo set default public.generar_codigo_org();
alter table public.organizaciones alter column codigo set not null;
create unique index if not exists organizaciones_codigo_unico on public.organizaciones (codigo);

-- Vincularse ya no es un insert libre: pasa por la función (que respeta publicación y bloqueos).
drop policy if exists favoritos_propios on public.favoritos;
create policy favoritos_select_propios on public.favoritos for select to authenticated using (usuario_id = (select auth.uid()));
create policy favoritos_delete_propios on public.favoritos for delete to authenticated using (usuario_id = (select auth.uid()));
revoke insert, update on public.favoritos from authenticated;

-- Buscar organizaciones publicadas por nombre, ciudad, dirección o ID (código QH-…, id completo o slug).
create or replace function public.buscar_organizaciones(p_q text)
returns table (id uuid, nombre text, slug text, codigo text, descripcion text, direccion text, ciudad text, pais text, telefono text, latitud double precision, longitud double precision, vinculada boolean)
language sql stable set search_path = '' as $$
  with q as (select nullif(trim(coalesce(p_q, '')), '') as t)
  select o.id, o.nombre, o.slug, o.codigo, o.descripcion, o.direccion, o.ciudad, o.pais, o.telefono, o.latitud, o.longitud,
         exists (select 1 from public.favoritos f where f.organizacion_id = o.id and f.usuario_id = (select auth.uid())) as vinculada
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

-- Las organizaciones a las que estoy vinculado.
create or replace function public.mis_organizaciones()
returns table (id uuid, nombre text, slug text, codigo text, descripcion text, direccion text, ciudad text, pais text, telefono text, latitud double precision, longitud double precision, vinculada boolean)
language sql stable set search_path = '' as $$
  select o.id, o.nombre, o.slug, o.codigo, o.descripcion, o.direccion, o.ciudad, o.pais, o.telefono, o.latitud, o.longitud, true
  from public.organizaciones o
  where o.publica and o.activa and exists (select 1 from public.favoritos f where f.organizacion_id = o.id and f.usuario_id = (select auth.uid()))
  order by o.nombre
$$;
revoke all on function public.mis_organizaciones() from public, anon;
grant execute on function public.mis_organizaciones() to authenticated;

create or replace function public.vincular_organizacion(p_org uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  if not exists (select 1 from public.organizaciones where id = p_org and publica and activa) then raise exception 'Organización no disponible' using errcode = 'P0002'; end if;
  if exists (select 1 from public.clientes_bloqueados where organizacion_id = p_org and usuario_id = v_uid) then
    raise exception 'No puedes vincularte a esta organización' using errcode = '42501';
  end if;
  insert into public.favoritos (usuario_id, organizacion_id)
  select v_uid, p_org where not exists (select 1 from public.favoritos where usuario_id = v_uid and organizacion_id = p_org and qhub_cola_id is null);
end $$;
revoke all on function public.vincular_organizacion(uuid) from public, anon;
grant execute on function public.vincular_organizacion(uuid) to authenticated;

create or replace function public.desvincular_organizacion(p_org uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.favoritos where usuario_id = (select auth.uid()) and organizacion_id = p_org
$$;
revoke all on function public.desvincular_organizacion(uuid) from public, anon;
grant execute on function public.desvincular_organizacion(uuid) to authenticated;

-- Aviso a la administración cuando alguien se vincula.
create or replace function public.trg_aviso_favorito() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.qhub_cola_id is null then
    perform public.avisar_staff(new.organizacion_id, 'cliente', 'Cliente vinculado', public.nombre_de(new.usuario_id) || ' se vinculó a tu organización desde la app móvil.', '/clientes', null);
  end if;
  return new;
end $$;
