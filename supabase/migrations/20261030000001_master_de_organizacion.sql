-- Master de la organización: el dueño. Es un admin con la bandera es_master (por eso todas las reglas de admin actuales
-- le siguen valiendo) y tiene una diferencia: SOLO él puede quitar, desactivar o cambiar de rol a otros administradores.
-- Un admin normal sigue igual que hasta hoy con el resto del equipo, pero no puede tocar a otro admin ni al master.
-- El master no se puede quitar, desactivar ni degradar por nadie. La regla vive en un trigger (las altas/bajas van directo a la tabla).
alter table public.miembros add column if not exists es_master boolean not null default false;
create unique index if not exists un_master_por_organizacion on public.miembros (organizacion_id) where es_master;

-- Organizaciones existentes: el admin más antiguo pasa a ser el master.
update public.miembros m set es_master = true
from (select distinct on (organizacion_id) organizacion_id, usuario_id from public.miembros where rol = 'admin' and activo order by organizacion_id, creado_en) x
where m.organizacion_id = x.organizacion_id and m.usuario_id = x.usuario_id
  and not exists (select 1 from public.miembros k where k.organizacion_id = m.organizacion_id and k.es_master);

create or replace function public.trg_proteger_admins() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_soy_master boolean;
begin
  if v_uid is null then return coalesce(new, old); end if;        -- servidor (service_role / cascadas): sin restricción
  if tg_op = 'INSERT' then
    -- quien crea la organización (primer miembro, admin) queda como master; nadie más se marca master por su cuenta
    if new.es_master and not (new.rol = 'admin' and not exists (select 1 from public.miembros where organizacion_id = new.organizacion_id)) then new.es_master := false; end if;
    if not exists (select 1 from public.miembros where organizacion_id = new.organizacion_id) and new.rol = 'admin' then new.es_master := true; end if;
    return new;
  end if;
  select exists (select 1 from public.miembros where organizacion_id = old.organizacion_id and usuario_id = v_uid and es_master and activo) into v_soy_master;
  if tg_op = 'UPDATE' then
    if new.es_master is distinct from old.es_master then raise exception 'No se puede cambiar quién es el master' using errcode = '42501'; end if;
    if new.rol is not distinct from old.rol and new.activo is not distinct from old.activo then return new; end if;   -- otros campos: sin cambio de regla
    if old.es_master then raise exception 'El master no se puede cambiar ni desactivar' using errcode = '42501'; end if;
    if (old.rol = 'admin' or new.rol = 'admin') and not v_soy_master then raise exception 'Solo el master puede cambiar a un administrador' using errcode = '42501'; end if;
    return new;
  end if;
  -- DELETE
  if old.usuario_id = v_uid then return old; end if;                -- salir uno mismo (p. ej. eliminar su cuenta)
  if old.es_master then raise exception 'El master no se puede quitar del equipo' using errcode = '42501'; end if;
  if old.rol = 'admin' and not v_soy_master then raise exception 'Solo el master puede quitar a un administrador' using errcode = '42501'; end if;
  return old;
end $$;
drop trigger if exists proteger_admins on public.miembros;
create trigger proteger_admins before insert or update or delete on public.miembros for each row execute function public.trg_proteger_admins();
