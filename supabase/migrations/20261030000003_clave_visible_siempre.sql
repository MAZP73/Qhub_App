-- 1) Bug: clave_inicial_cifrada leía el correo con auth.uid(), pero la Edge Function la llama con service_role (auth.uid() nulo),
--    así que la página de invitación nunca veía la clave. Ahora el correo ya verificado lo pasa la Edge Function.
drop function if exists public.clave_inicial_cifrada(text);
create or replace function public.clave_inicial_cifrada(p_token text, p_email text)
returns text language sql stable security definer set search_path = '' as $$
  select c.clave from public.claves_iniciales c join public.invitaciones i on i.id = c.invitacion_id
   where i.token = p_token and i.aceptada_en is null and i.expira_en > now() and lower(i.email) = lower(p_email)
$$;
revoke all on function public.clave_inicial_cifrada(text, text) from public, anon, authenticated;
grant execute on function public.clave_inicial_cifrada(text, text) to service_role;

-- 2) La propia persona también puede leer (cifrada) su clave asignada; el admin sigue pudiendo leer la de su equipo.
create or replace function public.clave_inicial_de_miembro(p_org uuid, p_usuario uuid, p_solicitante uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_clave text;
begin
  if p_solicitante is null or not (
    p_solicitante = p_usuario
    or exists (select 1 from public.miembros m where m.organizacion_id = p_org and m.usuario_id = p_solicitante and m.activo and m.rol = 'admin')
  ) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = p_usuario) then
    raise exception 'No encontramos a esa persona en tu equipo' using errcode = 'P0002';
  end if;
  select clave into v_clave from public.claves_asignadas where organizacion_id = p_org and usuario_id = p_usuario;
  return v_clave;
end $$;

-- 3) Al aceptar la invitación con contraseña asignada: además de guardarla, llega un aviso a la persona para que la vea y la copie.
create or replace function public.trg_borrar_clave_inicial() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid; v_hay int;
begin
  if new.aceptada_en is not null then
    select u.id into v_uid from auth.users u where lower(u.email) = lower(new.email);
    if v_uid is not null then
      insert into public.claves_asignadas (organizacion_id, usuario_id, clave)
      select new.organizacion_id, v_uid, c.clave
      from public.claves_iniciales c where c.invitacion_id = new.id
      on conflict (organizacion_id, usuario_id) do update set clave = excluded.clave, creada_en = now();
      get diagnostics v_hay = row_count;
      if v_hay > 0 then
        insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje, ruta)
        values (v_uid, new.organizacion_id, 'sistema', 'Tu contraseña de acceso', 'Ábrelo para ver tu contraseña, copiarla y guardarla.', '/perfil?clave=1');
      end if;
    end if;
    delete from public.claves_iniciales where invitacion_id = new.id;
  end if;
  return new;
end $$;

-- 4) Contraseña ACTUAL: cuando la persona cambia su contraseña, la Edge Function guarda la nueva (cifrada) para que el admin siempre vea la vigente.
create or replace function public.guardar_clave_de_miembro(p_usuario uuid, p_clave text)
returns void language sql security definer set search_path = '' as $$
  insert into public.claves_asignadas (organizacion_id, usuario_id, clave)
  select m.organizacion_id, m.usuario_id, p_clave
  from public.miembros m join public.organizaciones o on o.id = m.organizacion_id
  where m.usuario_id = p_usuario and m.activo and m.rol <> 'admin' and o.tipo = 'empresa'
  on conflict (organizacion_id, usuario_id) do update set clave = excluded.clave, creada_en = now()
$$;
revoke all on function public.guardar_clave_de_miembro(uuid, text) from public, anon, authenticated;
grant execute on function public.guardar_clave_de_miembro(uuid, text) to service_role;
