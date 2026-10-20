-- Estrecha la AUDIENCIA de los avisos de staff ACCIONABLES para que lleguen solo a los admin.
-- Hoy solicitar_cambio_miembro (contraseña/correo/datos) y solicitar_recuperacion avisan vía
-- avisar_staff, que incluye al supervisor; pero solo el admin tiene permiso para aprobar esas
-- solicitudes (team.manage). El supervisor recibía avisos que no podía atender.
-- Aquí NO se cambia la semántica de permisos (el supervisor sigue sin poder aprobar): solo se
-- estrecha a quién le llega el aviso. No se toca avisar_staff ni los triggers informativos, así que
-- los avisos de equipo/cliente y el de reconexión siguen igual.
-- La autorización vive DENTRO del SQL (security definer, set search_path = '').
-- CLI de Supabase/Deno NO disponible aquí: esta migración es review-only y debe aplicarse en el
-- Supabase de la plataforma (p.ej. `supabase db push` o el editor SQL).

-- Helper hermano de avisar_staff, pero solo para admin ACTIVOS (mismo patrón y firma).
create or replace function public.avisar_staff_admins(org uuid, p_tipo text, p_titulo text, p_mensaje text, p_ruta text, excepto uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje, ruta)
  select m.usuario_id, org, p_tipo, p_titulo, p_mensaje, p_ruta
  from public.miembros m
  where m.organizacion_id = org and m.activo and m.rol = 'admin' and m.usuario_id is distinct from excepto
$$;
revoke all on function public.avisar_staff_admins(uuid, text, text, text, text, uuid) from public, anon, authenticated;

-- Redefine solicitar_cambio_miembro: idéntica a la última versión (20261025000001), cambiando
-- únicamente la llamada avisar_staff -> avisar_staff_admins para que el aviso accionable solo
-- llegue a los admin.
create or replace function public.solicitar_cambio_miembro(p_org uuid, p_tipo text, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if p_tipo not in ('contrasena', 'datos', 'correo') then raise exception 'Revisa los datos' using errcode = '22023'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = v_uid and activo) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.solicitudes_miembros set estado = 'usada' where organizacion_id = p_org and usuario_id = v_uid and tipo in ('contrasena', 'correo') and estado = 'aprobada' and respondida_en < now() - interval '24 hours';
  insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, motivo) values (p_org, v_uid, p_tipo, nullif(left(trim(coalesce(p_motivo, '')), 300), '')) returning id into v_id;
  perform public.avisar_staff_admins(p_org, 'equipo', case p_tipo when 'contrasena' then 'Piden cambiar su contraseña' when 'correo' then 'Piden cambiar su correo' else 'Piden cambiar sus datos' end,
    public.nombre_de(v_uid) || ' envió una solicitud. Revísala en Equipo.', '/equipo', v_uid);
  return v_id;
exception when unique_violation then raise exception 'Ya tienes una solicitud en curso' using errcode = '23505';
end $$;
revoke all on function public.solicitar_cambio_miembro(uuid, text, text) from public, anon;
grant execute on function public.solicitar_cambio_miembro(uuid, text, text) to authenticated;

-- Redefine solicitar_recuperacion: idéntica a la última versión (20261024000003), cambiando
-- únicamente la llamada avisar_staff -> avisar_staff_admins.
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
      perform public.avisar_staff_admins(r.organizacion_id, 'equipo', 'Piden recuperar su contraseña', v_nombre || ' no puede entrar y pidió recuperar su contraseña. Revísalo en Equipo.', '/equipo', v_uid);
    exception when unique_violation then null;
    end;
  end loop;
  return 'pendiente';
end $$;
revoke all on function public.solicitar_recuperacion(text) from public, anon, authenticated;
grant execute on function public.solicitar_recuperacion(text) to service_role;
