-- Notificaciones push de la app móvil: dispositivos registrados por persona y registro de avisos ya enviados.
-- Aditivo: no toca ninguna tabla, columna ni política existente.

create table public.dispositivos_push (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null references public.perfiles(id) on delete cascade,
  token          text not null unique,
  plataforma     text not null check (plataforma in ('android', 'ios')),
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create index dispositivos_push_usuario_idx on public.dispositivos_push (usuario_id);
create trigger dispositivos_push_actualizado before update on public.dispositivos_push
  for each row execute function public.set_actualizado_en();

alter table public.dispositivos_push enable row level security;
-- Cada persona ve y borra solo sus dispositivos. Registrar pasa por la función de abajo (el token puede venir de otra cuenta en el mismo teléfono).
create policy dispositivos_push_propios_select on public.dispositivos_push for select to authenticated using (usuario_id = (select auth.uid()));
create policy dispositivos_push_propios_delete on public.dispositivos_push for delete to authenticated using (usuario_id = (select auth.uid()));

-- Registra (o reasigna) el token de este teléfono a la persona que inició sesión.
create or replace function public.registrar_dispositivo_push(p_token text, p_plataforma text)
returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'Inicia sesión' using errcode = '28000'; end if;
  if p_token is null or length(p_token) not between 10 and 300 then raise exception 'Token inválido' using errcode = '22023'; end if;
  if p_plataforma not in ('android', 'ios') then raise exception 'Plataforma inválida' using errcode = '22023'; end if;
  insert into public.dispositivos_push (usuario_id, token, plataforma) values (uid, p_token, p_plataforma)
  on conflict (token) do update set usuario_id = excluded.usuario_id, plataforma = excluded.plataforma;
end $$;
revoke all on function public.registrar_dispositivo_push(text, text) from public, anon;
grant execute on function public.registrar_dispositivo_push(text, text) to authenticated;

-- Avisos que ya se mandaron por push (evita repetirlos). Solo la Edge Function qhub-push (service_role) la usa.
create table public.avisos_push_enviados (
  usuario_id      uuid not null references public.perfiles(id) on delete cascade,
  organizacion_id uuid not null references public.organizaciones(id) on delete cascade,
  aviso_id        text not null,
  enviado_en      timestamptz not null default now(),
  primary key (usuario_id, organizacion_id, aviso_id)
);
alter table public.avisos_push_enviados enable row level security;
