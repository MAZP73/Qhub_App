-- Avisos de las acciones importantes: cada vez que alguien de la administración hace algo relevante (invitar, quitar a alguien, editar perfiles,
-- eliminar un cliente, crear una cola, publicar…) queda registrado en la auditoría y se avisa a la administración (admin y supervisor) en la campana.
-- Los textos no llevan datos sensibles de clientes (nunca nombres ni contacto).
create or replace function public.trg_aviso_auditoria() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_actor text; v_obj text; v_tipo text; v_titulo text; v_msg text; v_ruta text := '/inicio'; v_det jsonb := coalesce(new.detalle, '{}'::jsonb);
begin
  v_actor := case when new.usuario_id is null then 'Alguien' else public.nombre_de(new.usuario_id) end;
  begin v_obj := case when new.entidad in ('miembro', 'perfil') then public.nombre_de(new.entidad_id::uuid) end; exception when others then v_obj := null; end;
  case new.accion
    when 'invitacion.enviar'   then v_tipo := 'equipo'; v_titulo := 'Invitación enviada'; v_msg := v_actor || ' invitó a ' || coalesce(v_det->>'email', 'una persona') || coalesce(' como ' || (v_det->>'rol'), '') || '.'; v_ruta := '/equipo';
    when 'invitacion.reenviar' then v_tipo := 'equipo'; v_titulo := 'Invitación reenviada'; v_msg := v_actor || ' reenvió la invitación a ' || coalesce(v_det->>'email', 'una persona') || '.'; v_ruta := '/equipo';
    when 'invitacion.cancelar' then v_tipo := 'equipo'; v_titulo := 'Invitación cancelada'; v_msg := v_actor || ' canceló la invitación a ' || coalesce(v_det->>'email', 'una persona') || '.'; v_ruta := '/equipo';
    when 'miembro.quitar'      then v_tipo := 'equipo'; v_titulo := 'Salió una persona del equipo'; v_msg := v_actor || ' quitó a ' || coalesce(v_obj, 'una persona') || ' del equipo.'; v_ruta := '/equipo';
    when 'miembro.editar'      then v_tipo := 'equipo'; v_titulo := 'Perfil del equipo actualizado'; v_msg := v_actor || ' actualizó el perfil de ' || coalesce(v_obj, 'una persona') || '.'; v_ruta := '/equipo';
    when 'miembro.rol'         then v_tipo := 'equipo'; v_titulo := 'Cambió un rol'; v_msg := v_actor || ' cambió el rol de ' || coalesce(v_obj, 'una persona') || coalesce(' a ' || (v_det->>'rol'), '') || '.'; v_ruta := '/equipo';
    when 'miembro.acceso'      then v_tipo := 'equipo'; v_titulo := case when v_det->>'activo' = 'true' then 'Acceso activado' else 'Acceso desactivado' end;
                                    v_msg := v_actor || case when v_det->>'activo' = 'true' then ' activó' else ' desactivó' end || ' el acceso de ' || coalesce(v_obj, 'una persona') || '.'; v_ruta := '/equipo';
    when 'cliente.eliminar'    then v_tipo := 'cliente'; v_titulo := 'Cliente eliminado'; v_msg := v_actor || ' eliminó a un cliente de la lista.'; v_ruta := '/clientes';
    when 'cliente.editar'      then v_tipo := 'cliente'; v_titulo := 'Datos de un cliente actualizados'; v_msg := v_actor || ' editó los datos de un cliente con su permiso.'; v_ruta := '/clientes';
    when 'cliente.solicitar_edicion' then v_tipo := 'cliente'; v_titulo := 'Permiso solicitado a un cliente'; v_msg := v_actor || ' pidió permiso a un cliente para editar sus datos.'; v_ruta := '/clientes';
    when 'cola.crear'          then v_tipo := 'sistema'; v_titulo := 'Cola creada'; v_msg := v_actor || ' creó la cola ' || coalesce(v_det->>'nombre', '') || '.'; v_ruta := '/colas';
    when 'cola.editar'         then v_tipo := 'sistema'; v_titulo := 'Cola actualizada'; v_msg := v_actor || ' editó la cola ' || coalesce(v_det->>'nombre', '') || '.'; v_ruta := '/colas';
    when 'cola.archivar'       then v_tipo := 'sistema'; v_titulo := 'Cola archivada'; v_msg := v_actor || ' archivó una cola.'; v_ruta := '/colas';
    when 'organizacion.publicar'    then v_tipo := 'sistema'; v_titulo := 'Publicada en la app móvil'; v_msg := v_actor || ' publicó la organización en la app móvil.'; v_ruta := '/ajustes';
    when 'organizacion.despublicar' then v_tipo := 'sistema'; v_titulo := 'Ya no aparece en la app móvil'; v_msg := v_actor || ' dejó de publicar la organización.'; v_ruta := '/ajustes';
    when 'organizacion.editar'      then v_tipo := 'sistema'; v_titulo := 'Datos de la organización actualizados'; v_msg := v_actor || ' actualizó los datos de la organización.'; v_ruta := '/ajustes';
    else return new;
  end case;
  perform public.avisar_staff(new.organizacion_id, v_tipo, v_titulo, left(v_msg, 400), v_ruta, null);
  return new;
end $$;
drop trigger if exists aviso_auditoria on public.auditoria;
create trigger aviso_auditoria after insert on public.auditoria for each row execute function public.trg_aviso_auditoria();

-- Las funciones del paso anterior no anotaban el correo ni el rol de la invitación: se anotan desde la función de envío (service_role).
