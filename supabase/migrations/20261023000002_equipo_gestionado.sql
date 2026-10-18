-- Quien pertenece al equipo de una organización (y no es su administrador) tiene sus datos y su contraseña GESTIONADOS por el administrador:
--   · nombre, apellido, teléfono y cargo no los cambia por su cuenta (solo puede completarlos si están vacíos); los edita el administrador
--   · recuperar la contraseña por correo exige que el administrador lo apruebe
-- Las cuentas personales y los administradores se gestionan solos.
create or replace function public.es_miembro_gestionado(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.miembros m join public.organizaciones o on o.id = m.organizacion_id
                 where m.usuario_id = p_uid and m.activo and m.rol <> 'admin' and o.tipo = 'empresa')
$$;
revoke all on function public.es_miembro_gestionado(uuid) from public, anon, authenticated;

create or replace function public.trg_perfil_gestionado() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Las funciones del sistema (aceptar invitación, edición del administrador) marcan la excepción; solo se aplica a quien edita SU propio perfil.
  if current_setting('qhub.bypass', true) = 'on' or (select auth.uid()) is distinct from new.id then return new; end if;
  if not public.es_miembro_gestionado(new.id) then return new; end if;
  if (nullif(old.nombre, '') is not null and new.nombre is distinct from old.nombre)
     or (nullif(old.apellido, '') is not null and new.apellido is distinct from old.apellido)
     or (nullif(old.telefono, '') is not null and new.telefono is distinct from old.telefono)
     or (nullif(old.cargo, '') is not null and new.cargo is distinct from old.cargo) then
    raise exception 'Estos datos los gestiona tu administrador. Pídele el cambio.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists perfiles_gestionado on public.perfiles;
create trigger perfiles_gestionado before update on public.perfiles for each row execute function public.trg_perfil_gestionado();

-- Aceptar la invitación copia el perfil que dejó configurado el administrador: es una excepción legítima.
create or replace function public.aceptar_invitacion(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_inv public.invitaciones; v_uid uuid := (select auth.uid());
        v_email text;
begin
  if v_uid is null then raise exception 'No autenticado' using errcode = '28000'; end if;
  select email into v_email from auth.users where id = v_uid;
  select * into v_inv from public.invitaciones
   where token = p_token and aceptada_en is null and expira_en > now()
     and lower(email) = lower(v_email)
   for update;
  if not found then raise exception 'Invitación inválida, vencida o para otro correo' using errcode = 'P0002'; end if;
  insert into public.miembros (organizacion_id, usuario_id, rol)
  values (v_inv.organizacion_id, v_uid, v_inv.rol)
  on conflict (organizacion_id, usuario_id) do update set rol = excluded.rol, activo = true;
  perform set_config('qhub.bypass', 'on', true);
  update public.perfiles set
    nombre   = coalesce(nullif(nombre, ''),   v_inv.nombre),
    apellido = coalesce(nullif(apellido, ''), v_inv.apellido),
    cargo    = coalesce(nullif(cargo, ''),    v_inv.cargo)
   where id = v_uid;
  perform set_config('qhub.bypass', 'off', true);
  update public.invitaciones set aceptada_en = now() where id = v_inv.id;
  return v_inv.organizacion_id;
end $$;

-- Recuperación de contraseña de alguien del equipo: solo con el permiso del administrador. La llama la Edge Function `qhub-recover`
-- (service_role). Devuelve 'libre' (puede recuperar), 'aprobada' (había permiso y se gastó) o 'pendiente' (se avisó al administrador).
create or replace function public.solicitar_recuperacion(p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid; v_perm uuid; r record; v_nombre text;
begin
  select id into v_uid from auth.users where lower(email) = lower(trim(p_email));
  if v_uid is null or not public.es_miembro_gestionado(v_uid) then return 'libre'; end if;
  select s.id into v_perm from public.solicitudes_miembros s join public.miembros m on m.organizacion_id = s.organizacion_id and m.usuario_id = s.usuario_id
   where s.usuario_id = v_uid and s.tipo = 'contrasena' and s.estado = 'aprobada' and s.respondida_en > now() - interval '24 hours' and m.activo
   order by s.respondida_en desc limit 1 for update of s;
  if v_perm is not null then update public.solicitudes_miembros set estado = 'usada' where id = v_perm; return 'aprobada'; end if;
  v_nombre := public.nombre_de(v_uid);
  for r in select m.organizacion_id from public.miembros m join public.organizaciones o on o.id = m.organizacion_id
            where m.usuario_id = v_uid and m.activo and m.rol <> 'admin' and o.tipo = 'empresa' loop
    begin
      insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, motivo) values (r.organizacion_id, v_uid, 'contrasena', 'Recuperación de contraseña');
      perform public.avisar_staff(r.organizacion_id, 'equipo', 'Piden recuperar su contraseña', v_nombre || ' no puede entrar y pidió recuperar su contraseña. Revísalo en Equipo.', '/equipo', v_uid);
    exception when unique_violation then null;      -- ya hay una solicitud en curso
    end;
  end loop;
  return 'pendiente';
end $$;
revoke all on function public.solicitar_recuperacion(text) from public, anon, authenticated;
grant execute on function public.solicitar_recuperacion(text) to service_role;
