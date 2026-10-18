-- El perfil nace con el nombre que traiga el proveedor (correo: nombre/apellido; Google: given_name/family_name/full_name).
-- El rol sigue sin salir nunca de los metadatos del cliente.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb); v_full text := nullif(trim(coalesce(m ->> 'full_name', m ->> 'name', '')), '');
begin
  insert into public.perfiles (id, nombre, apellido, avatar_url)
  values (new.id,
          coalesce(nullif(m ->> 'nombre', ''), nullif(m ->> 'given_name', ''), split_part(v_full, ' ', 1)),
          coalesce(nullif(m ->> 'apellido', ''), nullif(m ->> 'family_name', ''), nullif(trim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), '')),
          case when (m ->> 'avatar_url') ~ '^https://' then m ->> 'avatar_url' else null end);
  return new;
end $$;
