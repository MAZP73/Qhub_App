-- La conexión de la organización con Qhub se confirma UNA vez (al crear la cuenta) y queda registrada aquí.
-- Con ese registro, la plataforma no vuelve a mostrar la pantalla de conectar: lo decide la base de datos, no el navegador ni la API.
alter table public.organizaciones
  add column qhub_conectada_en  timestamptz,
  add column qhub_conectada_por uuid references public.perfiles(id) on delete set null;
-- Las columnas no están en el grant de UPDATE de `authenticated`: solo se escriben con la función de abajo o por el servidor.

-- Las organizaciones que ya existen ya pasaron por la pantalla de conectar.
update public.organizaciones set qhub_conectada_en = coalesce(qhub_conectada_en, now());

create or replace function public.confirmar_conexion_qhub(p_org uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.es_admin_org(p_org) then raise exception 'Solo un administrador puede hacerlo' using errcode = '42501'; end if;
  update public.organizaciones
     set qhub_conectada_en = coalesce(qhub_conectada_en, now()), qhub_conectada_por = coalesce(qhub_conectada_por, (select auth.uid()))
   where id = p_org;
end $$;
revoke all on function public.confirmar_conexion_qhub(uuid) from public, anon;
grant execute on function public.confirmar_conexion_qhub(uuid) to authenticated;

-- Si el servidor guarda la conexión (vinculada = true), también queda confirmada.
create or replace function public.trg_conexion_confirmada() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.vinculada and new.qhub_conectada_en is null then new.qhub_conectada_en := now(); end if;
  return new;
end $$;
create trigger conexion_confirmada before insert or update of vinculada on public.organizaciones for each row execute function public.trg_conexion_confirmada();
