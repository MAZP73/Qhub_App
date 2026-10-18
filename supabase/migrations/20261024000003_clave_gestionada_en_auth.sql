-- Restricción REAL de la contraseña (no solo de la pantalla): quien es parte de un equipo (y no es administrador) no puede cambiar su
-- contraseña ni su correo sin que el administrador lo haya aprobado, venga el cambio de donde venga (la app, un enlace de recuperación o la API directa).
-- Un disparador sobre auth.users lo exige en el propio Auth de Supabase. Las cuentas personales y los administradores no se tocan.
-- Nota: este es el Supabase de LA APP. El de la API Qhub es otro proyecto y no se toca; los integrantes del equipo nunca manejan la contraseña de Qhub
-- (la conexión la guarda el administrador en el servidor).
create or replace function public.trg_auth_gestionado() returns trigger language plpgsql security definer set search_path = '' as $$
declare v uuid;
begin
  if not public.es_miembro_gestionado(new.id) then return new; end if;
  if new.email is distinct from old.email then
    raise exception 'Tu correo lo gestiona tu administrador. Pídele el cambio.' using errcode = '42501';
  end if;
  if new.encrypted_password is distinct from old.encrypted_password then
    -- el permiso aprobado y vigente se gasta con este cambio
    select s.id into v from public.solicitudes_miembros s
     where s.usuario_id = new.id and s.tipo = 'contrasena' and s.estado = 'aprobada' and s.respondida_en > now() - interval '24 hours'
     order by s.respondida_en desc limit 1 for update;
    if v is null then raise exception 'Cambiar tu contraseña necesita la aprobación de tu administrador.' using errcode = '42501'; end if;
    update public.solicitudes_miembros set estado = 'usada' where id = v;
  end if;
  return new;
end $$;
drop trigger if exists auth_gestionado on auth.users;
create trigger auth_gestionado before update of encrypted_password, email on auth.users for each row execute function public.trg_auth_gestionado();

-- La recuperación ya no gasta el permiso al enviar el correo: se gasta al cambiar la contraseña (disparador de arriba).
create or replace function public.solicitar_recuperacion(p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_uid uuid; r record; v_nombre text;
begin
  select id into v_uid from auth.users where lower(email) = lower(trim(p_email));
  if v_uid is null or not public.es_miembro_gestionado(v_uid) then return 'libre'; end if;
  if exists (select 1 from public.solicitudes_miembros s where s.usuario_id = v_uid and s.tipo = 'contrasena' and s.estado = 'aprobada' and s.respondida_en > now() - interval '24 hours') then
    return 'aprobada';
  end if;
  v_nombre := public.nombre_de(v_uid);
  for r in select m.organizacion_id from public.miembros m join public.organizaciones o on o.id = m.organizacion_id
            where m.usuario_id = v_uid and m.activo and m.rol <> 'admin' and o.tipo = 'empresa' loop
    begin
      insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, motivo) values (r.organizacion_id, v_uid, 'contrasena', 'Recuperación de contraseña');
      perform public.avisar_staff(r.organizacion_id, 'equipo', 'Piden recuperar su contraseña', v_nombre || ' no puede entrar y pidió recuperar su contraseña. Revísalo en Equipo.', '/equipo', v_uid);
    exception when unique_violation then null;
    end;
  end loop;
  return 'pendiente';
end $$;
