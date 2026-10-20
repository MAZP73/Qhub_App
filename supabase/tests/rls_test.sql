-- Pruebas de seguridad (RLS, permisos de columna, roles). Corren dentro de una transacción que se deshace:
-- no dejan datos. Ejecutar con: python3 tool/supabase_sql.py supabase/tests/rls_test.sql
begin;
do $$
declare
  a uuid := gen_random_uuid();   -- admin de la organización
  b uuid := gen_random_uuid();   -- futuro agente
  c uuid := gen_random_uuid();   -- persona del público
  s uuid := gen_random_uuid();   -- supervisor
  r uuid := gen_random_uuid();   -- recepción
  org uuid; tok text; tok2 text; n int; checks int := 0; denied boolean;
  procedure_dummy int;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
  values
   (a, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a_'||a||'@test.local', 'x', now(), '{"nombre":"Ana","rol":"superadmin"}', now(), now()),
   (b, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b_'||b||'@test.local', 'x', now(), '{"nombre":"Beto"}', now(), now()),
   (c, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'c_'||c||'@test.local', 'x', now(), '{"nombre":"Cami"}', now(), now());

  -- 1. el rol nunca sale de lo que manda el cliente
  if exists (select 1 from public.perfiles where rol <> 'usuario' and id in (a,b,c)) then raise exception 'FALLO 1: un registro nació con rol distinto de usuario'; end if;
  checks := checks + 1;

  -- 2. anon no tiene ningún permiso
  begin
    set local role anon;
    perform count(*) from public.organizaciones;
    raise exception 'FALLO 2: anon pudo leer organizaciones';
  exception when insufficient_privilege then null; end;
  reset role; checks := checks + 1;

  -- 3. A crea una organización y queda como admin
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  org := public.crear_organizacion('Org Test', 'org-test-'||substr(a::text,1,8), 'Quito', 'Ecuador');
  if public.rol_en_organizacion(org) is distinct from 'admin' then raise exception 'FALLO 3: el creador no es admin'; end if;
  checks := checks + 1;

  -- 4. nadie puede subirse el rol ni desactivar su perfil
  begin
    update public.perfiles set rol = 'superadmin' where id = a;
    raise exception 'FALLO 4a: A se pudo subir a superadmin';
  exception when insufficient_privilege then null; end;
  begin
    update public.perfiles set activo = false where id = a;
    raise exception 'FALLO 4b: A pudo cambiar activo';
  exception when insufficient_privilege then null; end;
  update public.perfiles set nombre = 'Ana María' where id = a;  -- esto sí
  checks := checks + 1;

  -- 5. las credenciales de Qhub no son accesibles ni para el admin
  begin
    perform * from public.organizacion_credenciales;
    raise exception 'FALLO 5: se pudo leer organizacion_credenciales';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.organizacion_credenciales (organizacion_id, qhub_identificador, qhub_password) values (org, 'x', 'y');
    raise exception 'FALLO 5b: se pudo escribir organizacion_credenciales';
  exception when insufficient_privilege then null; end;
  checks := checks + 1;

  -- 6. el admin no puede publicar a mano ni marcar vinculada: eso lo hace la función de servidor
  begin
    update public.organizaciones set publica = true where id = org;
    raise exception 'FALLO 6a: el admin publicó directamente';
  exception when insufficient_privilege then null; end;
  begin
    update public.organizaciones set vinculada = true where id = org;
    raise exception 'FALLO 6b: el admin se marcó vinculada';
  exception when insufficient_privilege then null; end;
  update public.organizaciones set nombre = 'Org Test 2' where id = org;  -- esto sí
  checks := checks + 1;

  -- 7. B (otra persona) no ve la organización mientras no esté publicada ni sus miembros
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.organizaciones where id = org;
  if n <> 0 then raise exception 'FALLO 7a: B ve una organización no publicada'; end if;
  select count(*) into n from public.miembros where organizacion_id = org;
  if n <> 0 then raise exception 'FALLO 7b: B ve miembros ajenos'; end if;
  update public.organizaciones set nombre = 'hack' where id = org;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 7c: B editó la organización de A'; end if;
  begin
    insert into public.miembros (organizacion_id, usuario_id, rol) values (org, b, 'admin');
    raise exception 'FALLO 7d: B se auto-asignó como admin';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;
  checks := checks + 1;

  -- 8. la organización publicada y vinculada (lo hace el servidor) la ve el público, sin credenciales
  reset role;
  update public.organizaciones set vinculada = true, publica = true where id = org;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.organizaciones where id = org;
  if n <> 1 then raise exception 'FALLO 8a: el público no ve la organización publicada'; end if;
  select count(*) into n from public.miembros where organizacion_id = org;
  if n <> 0 then raise exception 'FALLO 8b: el público ve miembros'; end if;
  checks := checks + 1;

  -- 9. invitación: solo el admin crea; solo el correo invitado acepta; el agente queda sin poderes de admin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.invitaciones (organizacion_id, email, rol) values (org, 'b_'||b||'@test.local', 'agente') returning token into tok;

  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.aceptar_invitacion(tok);
    raise exception 'FALLO 9a: C aceptó una invitación para B';
  exception when sqlstate 'P0002' then null; end;
  begin
    insert into public.invitaciones (organizacion_id, email, rol) values (org, 'x@x.co', 'admin');
    raise exception 'FALLO 9b: C creó una invitación';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;

  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.aceptar_invitacion(tok);
  if public.rol_en_organizacion(org) is distinct from 'agente' then raise exception 'FALLO 9c: B no quedó como agente'; end if;
  begin
    perform public.aceptar_invitacion(tok);
    raise exception 'FALLO 9d: la invitación se pudo usar dos veces';
  exception when sqlstate 'P0002' then null; end;
  checks := checks + 1;

  -- 10. el agente ve al equipo pero no administra
  select count(*) into n from public.miembros where organizacion_id = org;
  if n <> 2 then raise exception 'FALLO 10a: el agente no ve a su equipo (%).', n; end if;
  update public.miembros set rol = 'admin' where organizacion_id = org and usuario_id = b;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 10b: el agente se subió a admin'; end if;
  begin
    insert into public.invitaciones (organizacion_id, email, rol) values (org, 'otro@x.co', 'agente');
    raise exception 'FALLO 10c: el agente creó una invitación';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;
  begin
    insert into public.cola_prefijos (organizacion_id, qhub_cola_id, prefijo) values (org, gen_random_uuid(), 'Z');
    raise exception 'FALLO 10d: el agente escribió prefijos';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;
  checks := checks + 1;

  -- 11. datos personales del público: favoritos, dispositivos e historial son solo del dueño
  reset role;
  update public.organizaciones set vinculada = true, publica = true, activa = true where id = org;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.vincular_organizacion(org);                         -- vincularse pasa por la función
  insert into public.dispositivos (usuario_id, plataforma, token_push) values (c, 'android', 'tok-c');
  begin
    insert into public.historial_turnos (usuario_id, organizacion_id, qhub_turno_id, qhub_cola_id, estado) values (c, org, gen_random_uuid(), gen_random_uuid(), 'en_espera');
    raise exception 'FALLO 11a: el cliente escribió su historial (debe hacerlo el servidor)';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;
  reset role;
  insert into public.historial_turnos (usuario_id, organizacion_id, qhub_turno_id, qhub_cola_id, estado) values (c, org, gen_random_uuid(), gen_random_uuid(), 'en_espera');
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.historial_turnos;
  if n <> 0 then raise exception 'FALLO 11b: B ve el historial de C'; end if;
  select count(*) into n from public.favoritos;
  if n <> 0 then raise exception 'FALLO 11c: B ve favoritos de C'; end if;
  select count(*) into n from public.dispositivos;
  if n <> 0 then raise exception 'FALLO 11d: B ve dispositivos de C'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  select count(*) into n from public.historial_turnos;
  if n <> 1 then raise exception 'FALLO 11e: C no ve su propio historial'; end if;
  checks := checks + 1;

  -- 12. auditoría: el staff escribe lo suyo y el agente no la lee
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.auditoria (organizacion_id, usuario_id, accion) values (org, b, 'cola.crear');
  begin
    insert into public.auditoria (organizacion_id, usuario_id, accion) values (org, a, 'suplantada');
    raise exception 'FALLO 12a: B auditó a nombre de A';
  exception when insufficient_privilege or others then
    if sqlstate not in ('42501') then raise; end if;
  end;
  select count(*) into n from public.auditoria;
  if n <> 0 then raise exception 'FALLO 12b: el agente lee la auditoría'; end if;
  checks := checks + 1;

  -- 13. las funciones internas no se pueden invocar sin sesión
  reset role;
  set local role anon;
  begin
    perform public.es_superadmin();
    raise exception 'FALLO 13: anon ejecutó es_superadmin';
  exception when insufficient_privilege then null; end;
  reset role; checks := checks + 1;


  -- 14. perfil: cada quien edita el suyo, con validaciones; nadie edita el ajeno
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update public.perfiles set pais = 'EC', ciudad = 'Quito', telefono = '+593 991234567', cargo = 'Ciudadana', zona_horaria = 'America/Guayaquil' where id = c;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLO 14a: C no pudo editar su perfil'; end if;
  begin update public.perfiles set pais = 'Ecuador' where id = c; raise exception 'FALLO 14b: país que no es código ISO'; exception when check_violation then null; end;
  begin update public.perfiles set telefono = 'abc' where id = c; raise exception 'FALLO 14c: teléfono inválido aceptado'; exception when check_violation then null; end;
  update public.perfiles set nombre = 'hack' where id = a;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 14d: C editó el perfil de A'; end if;
  reset role; checks := checks + 1;

  -- 15. roles nuevos: supervisor y recepción entran por invitación, ven al equipo y no administran
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
   (s, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 's_'||s||'@test.local', 'x', now(), '{"given_name":"Sofía","family_name":"Paz"}', now(), now()),
   (r, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'r_'||r||'@test.local', 'x', now(), '{"full_name":"Rosa María Vega"}', now(), now());
  if (select nombre || '|' || apellido from public.perfiles where id = s) is distinct from 'Sofía|Paz' then raise exception 'FALLO 15a: perfil desde given_name/family_name'; end if;
  if (select nombre || '|' || apellido from public.perfiles where id = r) is distinct from 'Rosa|María Vega' then raise exception 'FALLO 15b: perfil desde full_name'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.invitaciones (organizacion_id, email, rol) values (org, 's_'||s||'@test.local', 'supervisor') returning token into tok;
  insert into public.invitaciones (organizacion_id, email, rol) values (org, 'r_'||r||'@test.local', 'recepcion') returning token into tok2;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.aceptar_invitacion(tok);
  if public.rol_en_organizacion(org) is distinct from 'supervisor' then raise exception 'FALLO 15c: no quedó como supervisor'; end if;
  select count(*) into n from public.miembros where organizacion_id = org;
  if n < 3 then raise exception 'FALLO 15d: el supervisor no ve al equipo'; end if;
  update public.miembros set rol = 'admin' where organizacion_id = org and usuario_id = s;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 15e: el supervisor se subió a admin'; end if;
  begin insert into public.invitaciones (organizacion_id, email, rol) values (org, 'z@x.co', 'agente'); raise exception 'FALLO 15f: el supervisor invitó'; exception when insufficient_privilege or others then if sqlstate not in ('42501') then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', r, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.aceptar_invitacion(tok2);
  if public.rol_en_organizacion(org) is distinct from 'recepcion' then raise exception 'FALLO 15g: no quedó como recepción'; end if;
  update public.organizaciones set nombre = 'hack' where id = org;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO 15h: recepción editó la organización'; end if;
  reset role; checks := checks + 1;

  -- 16. avisos del equipo: llegan solo a administración, el contenido no se edita ni se fabrica
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.notificaciones_staff where organizacion_id = org;
  if n < 3 then raise exception 'FALLO 16a: el admin no recibió los avisos de equipo y clientes (%).', n; end if;
  begin update public.notificaciones_staff set titulo = 'hack' where usuario_id = a; raise exception 'FALLO 16b: se editó el contenido de un aviso'; exception when insufficient_privilege then null; end;
  update public.notificaciones_staff set leida = true where usuario_id = a;
  get diagnostics n = row_count;
  if n < 1 then raise exception 'FALLO 16c: el admin no pudo marcar sus avisos como leídos'; end if;
  begin insert into public.notificaciones_staff (usuario_id, organizacion_id, tipo, titulo, mensaje) values (a, org, 'sistema', 'x', 'y'); raise exception 'FALLO 16d: se creó un aviso a mano'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.notificaciones_staff;
  if n < 1 then raise exception 'FALLO 16e: el supervisor no recibió el aviso de la persona que se unió'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.notificaciones_staff where usuario_id <> b;
  if n <> 0 then raise exception 'FALLO 16f: un agente ve avisos de administración o de otras personas'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.notificaciones_staff;
  if n <> 0 then raise exception 'FALLO 16g: el público ve avisos'; end if;
  reset role; checks := checks + 1;

  -- 17. clientes: admin ve contacto y bloquea; supervisor ve actividad sin contacto; agente y público nada
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.clientes_organizacion(org) where usuario_id = c and email is not null;
  if n <> 1 then raise exception 'FALLO 17a: el admin no ve a su cliente con contacto (%).', n; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.clientes_organizacion(org) where usuario_id = c and email is null and telefono is null;
  if n <> 1 then raise exception 'FALLO 17b: el supervisor ve el contacto del cliente o no lo ve en la lista (%).', n; end if;
  select count(*) into n from public.historial_turnos where organizacion_id = org;
  if n < 1 then raise exception 'FALLO 17c: el supervisor no ve el historial de turnos de la organización'; end if;
  begin insert into public.clientes_bloqueados (organizacion_id, usuario_id, motivo, bloqueado_por) values (org, c, 'x', s); raise exception 'FALLO 17d: el supervisor bloqueó a un cliente';
  exception when insufficient_privilege or others then if sqlstate not in ('42501') then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform * from public.clientes_organizacion(org); raise exception 'FALLO 17e: un agente listó clientes'; exception when insufficient_privilege then null; end;
  select count(*) into n from public.historial_turnos where organizacion_id = org and usuario_id <> b;
  if n <> 0 then raise exception 'FALLO 17f: un agente ve turnos de clientes ajenos'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform * from public.clientes_organizacion(org); raise exception 'FALLO 17g: el público listó clientes'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  insert into public.clientes_bloqueados (organizacion_id, usuario_id, motivo, bloqueado_por) values (org, c, 'Abuso', a);
  begin insert into public.clientes_bloqueados (organizacion_id, usuario_id, motivo, bloqueado_por) values (org, b, 'x', s); raise exception 'FALLO 17h: se bloqueó a nombre de otra persona';
  exception when insufficient_privilege or others then if sqlstate not in ('42501') then raise; end if; end;
  select count(*) into n from public.clientes_organizacion(org) where usuario_id = c and bloqueado;
  if n <> 1 then raise exception 'FALLO 17i: el bloqueo no se refleja en la lista'; end if;
  delete from public.clientes_bloqueados where usuario_id = c and organizacion_id = org;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALLO 17j: el admin no pudo desbloquear'; end if;
  reset role; checks := checks + 1;

  -- 19. cuenta personal vs organización: la personal no tiene equipo
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  org := public.crear_organizacion('Mi espacio', 'mi-espacio-'||substr(a::text,1,8), null, null, 'America/Guayaquil', 'persona');
  if (select tipo from public.organizaciones where id = org) is distinct from 'persona' then raise exception 'FALLO 19a: la cuenta no quedó como persona'; end if;
  if public.rol_en_organizacion(org) is distinct from 'admin' then raise exception 'FALLO 19b: la persona no es titular'; end if;
  begin insert into public.invitaciones (organizacion_id, email, rol) values (org, 'otro@x.co', 'agente'); raise exception 'FALLO 19c: una cuenta personal aceptó una invitación'; exception when check_violation then null; end;
  begin update public.organizaciones set tipo = 'empresa' where id = org; raise exception 'FALLO 19d: se cambió el tipo de cuenta'; exception when insufficient_privilege then null; end;
  reset role;
  begin insert into public.miembros (organizacion_id, usuario_id, rol) values (org, b, 'agente'); raise exception 'FALLO 19e: entró un segundo miembro a una cuenta personal'; exception when check_violation then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  org := public.crear_organizacion('Empresa X', 'empresa-x-'||substr(a::text,1,8));
  if (select tipo from public.organizaciones where id = org) is distinct from 'empresa' then raise exception 'FALLO 19f: el tipo por defecto no es empresa'; end if;
  reset role; checks := checks + 1;

  -- 20. conexión con Qhub confirmada: la decide la base de datos; solo un administrador la confirma
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  org := public.crear_organizacion('Org conexión', 'org-conexion-'||substr(a::text,1,8));
  if (select qhub_conectada_en from public.organizaciones where id = org) is not null then raise exception 'FALLO 20a: una organización nueva ya nace conectada'; end if;
  begin update public.organizaciones set qhub_conectada_en = now() where id = org; raise exception 'FALLO 20b: el admin escribió la marca a mano'; exception when insufficient_privilege then null; end;
  perform public.confirmar_conexion_qhub(org);
  if (select qhub_conectada_en is null or qhub_conectada_por is distinct from a from public.organizaciones where id = org) then raise exception 'FALLO 20c: no quedó confirmada por el admin'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.confirmar_conexion_qhub(org); raise exception 'FALLO 20d: alguien ajeno confirmó la conexión'; exception when insufficient_privilege then null; end;
  reset role;
  checks := checks + 1;

  -- 21. si el servidor guarda la conexión (vinculada), también queda confirmada
  org := (select id from public.organizaciones where slug = 'org-conexion-'||substr(a::text,1,8));
  update public.organizaciones set qhub_conectada_en = null where id = org;
  update public.organizaciones set vinculada = true where id = org;
  if (select qhub_conectada_en from public.organizaciones where id = org) is null then raise exception 'FALLO 21: vincular no confirmó la conexión'; end if;
  checks := checks + 1;

  -- 22. invitaciones por correo: una pendiente por correo, la ve solo su destinatario, y al aceptar el perfil queda configurado
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  org := public.crear_organizacion('Org invitaciones', 'org-inv-'||substr(a::text,1,8));
  insert into public.invitaciones (organizacion_id, email, rol, nombre, apellido, cargo) values (org, 'c_'||c||'@test.local', 'agente', 'Carla', 'Mena', 'Caja') returning token into tok;
  begin insert into public.invitaciones (organizacion_id, email, rol) values (org, upper('c_'||c||'@test.local'), 'agente'); raise exception 'FALLO 22a: dos invitaciones pendientes al mismo correo';
  exception when unique_violation then null; end;
  if public.ya_es_miembro(org, 'c_'||c||'@test.local') then raise exception 'FALLO 22b: aún no es miembro'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform * from public.ver_invitacion(tok); raise exception 'FALLO 22c: otra persona vio la invitación'; exception when sqlstate 'P0002' then null; end;
  begin perform public.ya_es_miembro(org, 'x@x.co'); raise exception 'FALLO 22d: un no administrador consultó miembros'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.ver_invitacion(tok) where organizacion = 'Org invitaciones' and cargo = 'Caja';
  if n <> 1 then raise exception 'FALLO 22e: el invitado no ve su invitación'; end if;
  perform public.aceptar_invitacion(tok);
  if (select apellido from public.perfiles where id = c) is distinct from 'Mena' then raise exception 'FALLO 22f: no se aplicó el apellido configurado'; end if;
  if (select nombre from public.perfiles where id = c) is distinct from 'Cami' then raise exception 'FALLO 22g: se pisó el nombre que la persona ya tenía'; end if;
  if (select cargo from public.perfiles where id = c) is distinct from 'Ciudadana' then raise exception 'FALLO 22h: se pisó el cargo que la persona ya tenía'; end if;
  begin perform * from public.ver_invitacion(tok); raise exception 'FALLO 22i: una invitación usada sigue visible'; exception when sqlstate 'P0002' then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if not public.ya_es_miembro(org, 'c_'||c||'@test.local') then raise exception 'FALLO 22j: ya_es_miembro no lo detecta'; end if;
  reset role; checks := checks + 1;

  -- 23. avisos por rol: quien se une recibe su bienvenida y a quien le cambian el rol se le avisa; cada quien solo ve los suyos
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.notificaciones_staff where usuario_id = c and titulo = 'Te damos la bienvenida';
  reset role;
  if n <> 0 then raise exception 'FALLO 23a: un administrador ve avisos de otra persona'; end if;
  select count(*) into n from public.notificaciones_staff where usuario_id = c and titulo = 'Te damos la bienvenida' and organizacion_id = org;
  if n <> 1 then raise exception 'FALLO 23b: la persona que se unió no recibió su bienvenida'; end if;
  update public.miembros set rol = 'supervisor' where organizacion_id = org and usuario_id = c;
  select count(*) into n from public.notificaciones_staff where usuario_id = c and titulo = 'Cambió tu rol' and mensaje like '%supervisor%';
  if n <> 1 then raise exception 'FALLO 23c: no se avisó el cambio de rol'; end if;
  checks := checks + 1;

  -- 24. administrar miembros: el admin edita y quita a su equipo, nadie más, y los clientes no se tocan
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.editar_miembro(org, c, 'Hack', 'Er', null, null); raise exception 'FALLO 24a: un no administrador editó un perfil'; exception when insufficient_privilege then null; end;
  begin perform public.quitar_miembro(org, c); raise exception 'FALLO 24b: un no administrador quitó a alguien'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.editar_miembro(org, c, 'Camila', 'Mena', 'Jefa de caja', '+593 99 123 4567');
  if (select cargo from public.perfil_de_miembro(org, c)) is distinct from 'Jefa de caja' then raise exception 'FALLO 24c: no se guardó la edición'; end if;
  begin perform public.editar_miembro(org, c, 'X', 'Y', null, null); raise exception 'FALLO 24d: nombre inválido aceptado'; exception when sqlstate '22023' then null; end;
  begin perform public.editar_miembro(org, b, 'Ana', 'Pérez', null, null); raise exception 'FALLO 24e: se editó a alguien de otro equipo'; exception when sqlstate 'P0002' then null; end;
  begin perform public.quitar_miembro(org, a); raise exception 'FALLO 24f: el admin se quitó a sí mismo'; exception when sqlstate '22023' then null; end;
  perform public.quitar_miembro(org, c);
  if exists (select 1 from public.miembros where organizacion_id = org and usuario_id = c) then raise exception 'FALLO 24g: no se quitó del equipo'; end if;
  reset role;
  if not exists (select 1 from public.perfiles where id = c) then raise exception 'FALLO 24h: se borró la cuenta en vez de solo quitarla del equipo'; end if;
  checks := checks + 1;

  -- 25. clientes: la organización solo los elimina; editar sus datos exige permiso del cliente (aprobado, vigente y de un solo uso)
  insert into public.favoritos (usuario_id, organizacion_id) values (c, org);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.eliminar_cliente(org, c); raise exception 'FALLO 25a: un no administrador eliminó un cliente'; exception when insufficient_privilege then null; end;
  begin perform public.solicitar_edicion_cliente(org, c, 'x'); raise exception 'FALLO 25b: un no administrador pidió permiso'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.editar_cliente(org, c, 'Camila', 'Mena', null); raise exception 'FALLO 25c: se editó un cliente sin permiso'; exception when insufficient_privilege then null; end;
  tok := public.solicitar_edicion_cliente(org, c, 'Corregir el apellido')::text;
  begin perform public.solicitar_edicion_cliente(org, c, 'otra vez'); raise exception 'FALLO 25d: dos solicitudes a la vez'; exception when unique_violation then null; end;
  begin perform public.editar_cliente(org, c, 'Camila', 'Mena', null); raise exception 'FALLO 25e: se editó con la solicitud pendiente'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.responder_edicion_cliente(tok::uuid, true); raise exception 'FALLO 25f: otra persona aprobó el permiso del cliente'; exception when sqlstate 'P0002' then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.responder_edicion_cliente(tok::uuid, true);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.editar_cliente(org, c, 'Camila', 'Mena', null);
  begin perform public.editar_cliente(org, c, 'Otra', 'Vez', null); raise exception 'FALLO 25g: un permiso sirvió dos veces'; exception when insufficient_privilege then null; end;
  perform public.eliminar_cliente(org, c);
  reset role;
  if public.es_cliente_de(org, c) then raise exception 'FALLO 25h: el cliente sigue en la organización'; end if;
  checks := checks + 1;

  -- 26. solicitudes de una persona del equipo a su administrador: el permiso de contraseña lo da solo el admin, vale una vez
  insert into public.miembros (organizacion_id, usuario_id, rol) values (org, c, 'agente') on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  tok := public.solicitar_cambio_miembro(org, 'contrasena', 'Quiero una propia')::text;
  begin perform public.solicitar_cambio_miembro(org, 'contrasena', 'otra'); raise exception 'FALLO 26a: dos solicitudes iguales'; exception when unique_violation then null; end;
  begin perform public.responder_solicitud_miembro(tok::uuid, true); raise exception 'FALLO 26b: la persona se aprobó su propia solicitud'; exception when insufficient_privilege then null; end;
  if public.usar_permiso_contrasena(org) then raise exception 'FALLO 26c: usó un permiso sin aprobar'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.solicitudes_pendientes(org);
  if n <> 1 then raise exception 'FALLO 26d: el admin no ve la solicitud'; end if;
  perform public.responder_solicitud_miembro(tok::uuid, true);
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if (select estado from public.mi_permiso(org, 'contrasena')) is distinct from 'aprobada' then raise exception 'FALLO 26e: no ve su permiso'; end if;
  if not public.usar_permiso_contrasena(org) then raise exception 'FALLO 26f: no pudo usar su permiso'; end if;
  if public.usar_permiso_contrasena(org) then raise exception 'FALLO 26g: el permiso sirvió dos veces'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.solicitar_cambio_miembro(org, 'datos', 'x'); raise exception 'FALLO 26h: alguien de otro equipo hizo una solicitud'; exception when insufficient_privilege then null; end;
  reset role; checks := checks + 1;

  -- 27. equipo gestionado: un integrante no cambia por su cuenta nombre/teléfono/cargo ya completos, y recuperar la contraseña exige aprobación
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform set_config('qhub.bypass', 'on', true);
  update public.perfiles set nombre = 'Cami', telefono = null, cargo = null where id = c;      -- preparación de la prueba
  perform set_config('qhub.bypass', 'off', true);
  set local role authenticated;
  begin update public.perfiles set nombre = 'Otro' where id = c; raise exception 'FALLO 27a: un integrante cambió su nombre por su cuenta'; exception when insufficient_privilege then null; end;
  update public.perfiles set telefono = '+593 99 123 4567', ciudad = 'Quito' where id = c;        -- completar un campo vacío y cambiar la ciudad sí
  reset role;
  if public.solicitar_recuperacion('c_'||c||'@test.local') <> 'pendiente' then raise exception 'FALLO 27b: la recuperación no quedó pendiente'; end if;
  if public.solicitar_recuperacion('c_'||c||'@test.local') <> 'pendiente' then raise exception 'FALLO 27c: repetir la solicitud falló'; end if;
  if public.solicitar_recuperacion('nadie_'||c||'@test.local') <> 'libre' then raise exception 'FALLO 27d: un correo desconocido no es libre'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select id::text into tok2 from public.solicitudes_pendientes(org) where usuario_id = c and tipo = 'contrasena' limit 1;
  perform public.responder_solicitud_miembro(tok2::uuid, true);
  reset role;
  if public.solicitar_recuperacion('c_'||c||'@test.local') <> 'aprobada' then raise exception 'FALLO 27e: no se aceptó la recuperación aprobada'; end if;
  if public.solicitar_recuperacion('c_'||c||'@test.local') <> 'aprobada' then raise exception 'FALLO 27f: enviar el correo no debe gastar el permiso'; end if;
  if public.solicitar_recuperacion('a_'||a||'@test.local') <> 'libre' then raise exception 'FALLO 27g: un administrador tiene que poder recuperar solo'; end if;
  checks := checks + 1;

  -- 28. restricción real en Auth: un integrante del equipo no cambia contraseña ni correo sin aprobación (un cambio por permiso); el administrador sí
  update public.solicitudes_miembros set estado = 'usada' where usuario_id = c;                  -- sin ningún permiso vigente
  begin update auth.users set encrypted_password = 'otra-clave-1' where id = c; raise exception 'FALLO 28a: cambió la contraseña sin permiso'; exception when insufficient_privilege then null; end;
  begin update auth.users set email = 'otro_'||c||'@test.local' where id = c; raise exception 'FALLO 28b: cambió el correo sin permiso'; exception when insufficient_privilege then null; end;
  insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, estado, respondida_en) values (org, c, 'contrasena', 'aprobada', now());
  update auth.users set encrypted_password = 'otra-clave-2' where id = c;       -- con el permiso aprobado, este cambio lo gasta
  begin update auth.users set encrypted_password = 'otra-clave-3' where id = c; raise exception 'FALLO 28c: un permiso sirvió dos veces'; exception when insufficient_privilege then null; end;
  insert into public.solicitudes_miembros (organizacion_id, usuario_id, tipo, estado, respondida_en) values (org, c, 'correo', 'aprobada', now());
  update auth.users set email = 'nuevo_'||c||'@test.local' where id = c;           -- con el permiso de correo aprobado, el cambio pasa
  begin update auth.users set email = 'otro2_'||c||'@test.local' where id = c; raise exception 'FALLO 28d: el permiso de correo sirvió dos veces'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.historial_solicitudes(org) where usuario_id = c and tipo = 'contrasena' and resultado = 'usada';
  if n < 1 then raise exception 'FALLO 28e: el historial no muestra las solicitudes ya resueltas'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.historial_solicitudes(org); raise exception 'FALLO 28f: un no administrador vio el historial'; exception when insufficient_privilege then null; end;
  reset role;
  update auth.users set encrypted_password = 'clave-admin-1' where id = a;      -- el administrador se gestiona solo
  checks := checks + 1;

  -- 29. acciones importantes avisan a la administración (invitar, quitar a alguien, eliminar un cliente…) sin nombres de clientes
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id, detalle) values (org, a, 'invitacion.enviar', 'invitacion', 'x', '{"email":"nueva@x.co","rol":"agente"}');
  insert into public.auditoria (organizacion_id, usuario_id, accion, entidad, entidad_id) values (org, a, 'cliente.eliminar', 'cliente', c::text);
  select count(*) into n from public.notificaciones_staff where usuario_id = a and organizacion_id = org and titulo = 'Invitación enviada' and mensaje like '%nueva@x.co%';
  if n <> 1 then raise exception 'FALLO 29a: no se avisó la invitación enviada'; end if;
  select count(*) into n from public.notificaciones_staff where organizacion_id = org and titulo = 'Cliente eliminado' and mensaje like '%' || coalesce((select nombre from public.perfiles where id = c), 'zzz') || '%';
  if n <> 0 then raise exception 'FALLO 29b: el aviso de cliente eliminado llevó su nombre'; end if;
  checks := checks + 1;

  -- 30. móvil: buscar por nombre o ID, vincularse (solo a organizaciones publicadas y sin bloqueo) y desvincularse
  update public.organizaciones set vinculada = true, publica = true, activa = true where id = org;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.buscar_organizaciones((select codigo from public.organizaciones where id = org)) where id = org and not vinculada;
  if n <> 1 then raise exception 'FALLO 30a: no se encontró la organización por su ID'; end if;
  select count(*) into n from public.buscar_organizaciones('Org invitaciones') where id = org;
  if n <> 1 then raise exception 'FALLO 30b: no se encontró por nombre'; end if;
  begin insert into public.favoritos (usuario_id, organizacion_id) values (b, org); raise exception 'FALLO 30c: se vinculó sin pasar por la función'; exception when insufficient_privilege then null; end;
  perform public.vincular_organizacion(org);
  perform public.vincular_organizacion(org);
  select count(*) into n from public.mis_organizaciones() where id = org;
  if n <> 1 then raise exception 'FALLO 30d: no aparece entre mis organizaciones (o se duplicó)'; end if;
  select count(*) into n from public.buscar_organizaciones('Org invitaciones') where id = org and vinculada;
  if n <> 1 then raise exception 'FALLO 30e: no se marca como vinculada'; end if;
  perform public.desvincular_organizacion(org);
  select count(*) into n from public.mis_organizaciones();
  if n <> 0 then raise exception 'FALLO 30f: no se desvinculó'; end if;
  reset role;
  insert into public.clientes_bloqueados (organizacion_id, usuario_id, bloqueado_por) values (org, b, a);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.vincular_organizacion(org); raise exception 'FALLO 30g: un cliente bloqueado se vinculó'; exception when insufficient_privilege then null; end;
  reset role;
  update public.organizaciones set publica = false where id = org;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.vincular_organizacion(org); raise exception 'FALLO 30h: se vinculó a una organización no publicada'; exception when sqlstate 'P0002' then null; end;
  select count(*) into n from public.buscar_organizaciones('Org invitaciones');
  if n <> 0 then raise exception 'FALLO 30i: una organización no publicada aparece en la búsqueda'; end if;
  reset role; checks := checks + 1;

  -- 31. el cliente ve y responde las solicitudes de edición dirigidas a él; nadie más las ve
  insert into public.favoritos (usuario_id, organizacion_id) select c, org where not exists (select 1 from public.favoritos where usuario_id = c and organizacion_id = org);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  tok := public.solicitar_edicion_cliente(org, c, 'Corregir apellido')::text;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.mis_solicitudes_edicion() where id = tok::uuid and organizacion = 'Org invitaciones';
  if n <> 1 then raise exception 'FALLO 31a: el cliente no ve la solicitud'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.mis_solicitudes_edicion();
  if n <> 0 then raise exception 'FALLO 31b: otra persona ve solicitudes ajenas'; end if;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.responder_edicion_cliente(tok::uuid, false);
  select count(*) into n from public.mis_solicitudes_edicion();
  if n <> 0 then raise exception 'FALLO 31c: la solicitud respondida sigue pendiente'; end if;
  reset role; checks := checks + 1;

  -- 18. eliminar cuenta: el único admin de un equipo no puede irse; el público sí, y se lleva sus datos; anon no puede
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.eliminar_mi_cuenta(); raise exception 'FALLO 18a: el único admin eliminó su cuenta'; exception when check_violation then null; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.eliminar_mi_cuenta();
  reset role;
  if exists (select 1 from auth.users where id = c) or exists (select 1 from public.perfiles where id = c) then raise exception 'FALLO 18b: la cuenta de C sigue existiendo'; end if;
  if exists (select 1 from public.historial_turnos where usuario_id = c) or exists (select 1 from public.favoritos where usuario_id = c) then raise exception 'FALLO 18c: quedaron datos de C'; end if;
  set local role anon;
  begin perform public.eliminar_mi_cuenta(); raise exception 'FALLO 18d: anon ejecutó eliminar_mi_cuenta'; exception when insufficient_privilege then null; end;
  reset role; checks := checks + 1;

  -- 32. puerta de la app móvil (solo clientes): es_correo_cliente solo para service_role; true para un cliente,
  --     false para staff/inexistente; y nadie puede marcarse 'cliente' por su cuenta (app_metadata protegido, AC-3.7/AC-3.8)
  declare
    cli uuid := gen_random_uuid();   -- cuenta de cliente (app móvil)
  begin
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data, raw_app_meta_data, created_at, updated_at)
    values (cli, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cli_'||cli||'@test.local', 'x', now(), '{"nombre":"Cliente"}', '{"tipo_cuenta":"cliente"}', now(), now());

    -- es_correo_cliente no es ejecutable por authenticated ni por anon (solo service_role la usa desde la Edge Function)
    perform set_config('request.jwt.claims', json_build_object('sub', cli, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      perform public.es_correo_cliente('cli_'||cli||'@test.local');
      raise exception 'FALLO 32a: authenticated ejecutó es_correo_cliente';
    exception when insufficient_privilege then null; end;
    reset role;
    set local role anon;
    begin
      perform public.es_correo_cliente('cli_'||cli||'@test.local');
      raise exception 'FALLO 32b: anon ejecutó es_correo_cliente';
    exception when insufficient_privilege then null; end;
    reset role;

    -- como service_role (lo que hace la Edge Function): true para el cliente, false para staff y para un correo inexistente
    set local role service_role;
    if public.es_correo_cliente('cli_'||cli||'@test.local') is not true then raise exception 'FALLO 32c: un cliente no pasó la puerta'; end if;
    if public.es_correo_cliente('a_'||a||'@test.local') is not false then raise exception 'FALLO 32d: un correo del staff pasó la puerta'; end if;
    if public.es_correo_cliente('nadie_'||cli||'@test.local') is not false then raise exception 'FALLO 32e: un correo inexistente pasó la puerta'; end if;
    -- normaliza mayúsculas/espacios como la función estado_de_correo
    if public.es_correo_cliente('  CLI_'||cli||'@TEST.LOCAL  ') is not true then raise exception 'FALLO 32f: no se normalizó el correo'; end if;
    reset role;

    -- un cliente no puede fabricar su tipo_cuenta ni cambiarlo por una actualización normal (el tipo lo pone solo el servidor)
    perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      update auth.users set raw_app_meta_data = jsonb_set(coalesce(raw_app_meta_data, '{}'::jsonb), '{tipo_cuenta}', '"cliente"', true) where id = b;
      raise exception 'FALLO 32g: authenticated escribió app_metadata.tipo_cuenta';
    exception when insufficient_privilege then null; end;
    reset role;
  end;
  checks := checks + 1;

  raise exception 'OK: % verificaciones de seguridad pasaron (se deshace la transacción)', checks;
end $$;
rollback;
