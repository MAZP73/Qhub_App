-- La clave inicial de la invitación ahora se guarda CIFRADA en reposo (sobre AES-GCM { v, iv, d } en base64).
-- La cifra la Edge Function `qhub-invite` con una clave del servidor (CLAVE_INICIAL_KEY) que nunca toca la base.
-- La descifra la Edge Function `qhub-clave`, que es la única que puede ejecutar la función de lectura.
comment on column public.claves_iniciales.clave is
  'Sobre cifrado AES-GCM ({ v, iv, d } en base64), nunca texto plano. Lo descifra la Edge Function qhub-clave con CLAVE_INICIAL_KEY.';

-- La función vieja devolvía la clave a cualquier `authenticated`: ahora devolvería el blob cifrado. Se elimina por completo.
revoke all on function public.ver_clave_inicial(text) from public, anon, authenticated;
drop function if exists public.ver_clave_inicial(text);

-- Nueva función de lectura: misma autorización (correo invitado + invitación pendiente/vigente) pero devuelve el TEXTO CIFRADO.
-- Solo `service_role` (la Edge Function qhub-clave) puede ejecutarla; el cliente ya no lee la clave por RPC directo.
create or replace function public.clave_inicial_cifrada(p_token text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_email text; v_clave text;
begin
  select u.email into v_email from auth.users u where u.id = (select auth.uid());
  select c.clave into v_clave from public.claves_iniciales c join public.invitaciones i on i.id = c.invitacion_id
   where i.token = p_token and i.aceptada_en is null and i.expira_en > now() and lower(i.email) = lower(v_email);
  return v_clave;
end $$;
revoke all on function public.clave_inicial_cifrada(text) from public, anon, authenticated;
grant execute on function public.clave_inicial_cifrada(text) to service_role;
