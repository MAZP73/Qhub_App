-- Un integrante del equipo también pide permiso a su administrador para cambiar su CORREO de acceso (igual que la contraseña):
-- la solicitud se aprueba, vale 24 h y para un solo cambio (que se gasta cuando el cambio se confirma por el enlace del correo).
alter table public.solicitudes_miembros drop constraint if exists solicitudes_miembros_tipo_check;
alter table public.solicitudes_miembros add constraint solicitudes_miembros_tipo_check check (tipo in ('contrasena', 'datos', 'correo'));

create or replace function public.solicitar_cambio_miembro(p_org uuid, p_tipo text, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_uid uuid := (select auth.uid());
begin
  if p_tipo not in ('contrasena', 'datos', 'correo') then raise exception 'Revisa los datos' using errcode = '22023'; end if;
  if not exists (select 1 from public.miembros where organizacion_id = p_org and usuario_id = v_uid and activo) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.solicitudes_miembros set estado = 'usada' where organizacion_id = p_org and usuario_id = v_uid and tipo in ('contrasena', 'correo') and estado = 'aprobada' and respondida_en < now() - interval '24 hours';
  insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, motivo) values (p_org, v_uid, p_tipo, nullif(left(trim(coalesce(p_motivo, '')), 300), '')) returning id into v_id;
  perform public.avisar_staff(p_org, 'equipo', case p_tipo when 'contrasena' then 'Piden cambiar su contraseña' when 'correo' then 'Piden cambiar su correo' else 'Piden cambiar sus datos' end,
    public.nombre_de(v_uid) || ' envió una solicitud. Revísala en Equipo.', '/equipo', v_uid);
  return v_id;
exception when unique_violation then raise exception 'Ya tienes una solicitud en curso' using errcode = '23505';
end $$;

create or replace function public.responder_solicitud_miembro(p_id uuid, p_aprobar boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v public.solicitudes_miembros;
begin
  select * into v from public.solicitudes_miembros where id = p_id and estado = 'pendiente' for update;
  if not found then raise exception 'La solicitud ya no está disponible' using errcode = 'P0002'; end if;
  if not public.es_admin_org(v.organizacion_id) then raise exception 'Sin permiso' using errcode = '42501'; end if;
  update public.solicitudes_miembros set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, respondida_en = now() where id = p_id;
  if v.tipo = 'datos' and p_aprobar then update public.solicitudes_miembros set estado = 'usada' where id = p_id; end if;
  perform public.avisar_usuario(v.usuario_id, v.organizacion_id, 'equipo',
    case when p_aprobar then 'Tu solicitud fue aprobada' else 'Tu solicitud no fue aprobada' end,
    case when p_aprobar and v.tipo = 'contrasena' then 'Ya puedes cambiar tu contraseña en Mi perfil → Seguridad durante las próximas 24 horas.'
         when p_aprobar and v.tipo = 'correo' then 'Ya puedes cambiar tu correo en Mi perfil → Seguridad durante las próximas 24 horas.'
         when p_aprobar then 'El administrador atendió tu solicitud.' else 'El administrador no aprobó tu solicitud. Puedes hablar con él para saber por qué.' end, '/perfil');
end $$;

-- Auth: el cambio de contraseña o de correo de un integrante gestionado exige su permiso aprobado y vigente (se gasta con el cambio).
create or replace function public.trg_auth_gestionado() returns trigger language plpgsql security definer set search_path = '' as $$
declare v uuid;
begin
  if not public.es_miembro_gestionado(new.id) then return new; end if;
  if new.email is distinct from old.email then
    select s.id into v from public.solicitudes_miembros s
     where s.usuario_id = new.id and s.tipo = 'correo' and s.estado = 'aprobada' and s.respondida_en > now() - interval '24 hours'
     order by s.respondida_en desc limit 1 for update;
    if v is null then raise exception 'Cambiar tu correo necesita la aprobación de tu administrador.' using errcode = '42501'; end if;
    update public.solicitudes_miembros set estado = 'usada' where id = v;
  end if;
  if new.encrypted_password is distinct from old.encrypted_password then
    select s.id into v from public.solicitudes_miembros s
     where s.usuario_id = new.id and s.tipo = 'contrasena' and s.estado = 'aprobada' and s.respondida_en > now() - interval '24 hours'
     order by s.respondida_en desc limit 1 for update;
    if v is null then raise exception 'Cambiar tu contraseña necesita la aprobación de tu administrador.' using errcode = '42501'; end if;
    update public.solicitudes_miembros set estado = 'usada' where id = v;
  end if;
  return new;
end $$;

-- Aviso del cambio de correo aprobado a la administración (auditoría) no hace falta: ya se avisó al aprobar.
