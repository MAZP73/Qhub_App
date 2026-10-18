-- Tiempo real de los avisos del equipo: `notificaciones_staff` entra en la publicación `supabase_realtime`
-- para que Supabase Realtime entregue los cambios (postgres_changes). Realtime respeta la política SELECT
-- existente de la tabla (cada quien solo ve su organización): no expone nada nuevo.
-- Idempotente: solo se añade si aún no está en la publicación.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notificaciones_staff'
  ) then
    alter publication supabase_realtime add table public.notificaciones_staff;
  end if;
end $$;
