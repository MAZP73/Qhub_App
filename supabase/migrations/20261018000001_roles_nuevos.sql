-- Roles de organización nuevos. Van solos: un valor de enum nuevo no se puede usar en la misma transacción.
alter type public.rol_organizacion add value if not exists 'supervisor';  -- ve operación, historial y equipo; no atiende ni edita
alter type public.rol_organizacion add value if not exists 'recepcion';   -- atiende la fila; sin historial, equipo ni ajustes
