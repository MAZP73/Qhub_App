# Arquitectura

## Capas (por feature)

`presentation → domain ← data`. `domain` es TypeScript puro: entidades, puertos (interfaces de repositorio) y casos de uso. `data` implementa los puertos (fetch, WebSocket, Supabase). `presentation` usa React/React Native con TanStack Query y nunca ve errores de fetch ni de Supabase: todo error es un `Failure` tipado (`@qhub/core`, con `Result<T>`).

`@qhub/api-client` es el único lugar que conoce la API Qhub; ambas apps lo reutilizan. Sus repositorios dependen de un puerto `HttpTransport`: la web usa `FetchTransport` (Bearer + identidad) y el móvil `ProxyTransport`, que en lugar de salir a la API envía la petición a la Edge Function.

**Estilos.** Los tokens del design system se generan (`@qhub/design`) como variables CSS + tema de Tailwind v4 (web) y como tema de NativeWind (móvil); los componentes solo usan utilidades de Tailwind sobre esos tokens, con claro/oscuro automático.

## Quién habla con quién

```
Web ──(Bearer de la organización + X-Usuario-Id/Rol)──────────────▶ API Qhub (REST + WS)
    └── Supabase (staff, roles, ajustes, auditoría, prefijos)

Móvil ──(sesión Supabase)──▶ Edge Function qhub-proxy ──(credencial de la organización, X-Usuario-Id = persona)──▶ API Qhub
    └── Supabase (perfiles, organizaciones públicas, favoritos, historial)
```

La API autentica a la **organización**, no a la persona: quien tenga su token puede actuar como cualquier persona de esa cuenta. Por eso el móvil, que es público, **no recibe nunca** ese token.

### qhub-proxy (política en `supabase/functions/_shared/policy.ts`)
- Solo deja pasar lo que haría una persona que saca turno (ver colas/horarios/franjas/estado, `POST /turnos`, sus turnos, cancelar/posponer los suyos, sus avisos). Atender, finalizar, no-show, administrar colas, empresas y auth están **denegados**.
- `X-Usuario-Rol` siempre `cliente`; `X-Usuario-Id` es el id de Supabase verificado. El cuerpo no puede traer `usuario_id`.
- La API valida la cuenta, no la persona: antes de cancelar/posponer/leer un turno se verifica que `usuario_id` sea el del que llama.
- La organización debe estar publicada, activa y vinculada.

### qhub-token
Entrega a un **integrante** de la organización (`es_miembro`) un token de la API usando la credencial guardada, que no sale del servidor. Responde `404 sin_conexion` si aún no hay conexión y `409 credencial_invalida` si la contraseña guardada dejó de servir. La web lo usa al iniciar sesión y cuando el token vence (la API no tiene refresh).

### qhub-link
Un **admin** gestiona desde la web las acciones `conectar` (valida y guarda la cuenta Qhub, sin publicar), `publicar`, `despublicar` y `desvincular`: la función comprueba `es_admin_org`, inicia sesión en la API con la cuenta Qhub de la organización y guarda la credencial en `organizacion_credenciales` (solo `service_role`). El administrador **no puede** escribir `publica` ni `vinculada` directamente (permiso de columna revocado).

## Datos (Supabase `Qhub_APP`)

16 tablas con RLS y `anon` sin permisos. `rls_test.sql` comprueba 29 propiedades (el rol no sale del cliente, nadie se sube el rol, credenciales inaccesibles, aislamiento entre organizaciones y entre personas, invitaciones por correo (una pendiente por correo, solo la ve su destinatario, el perfil configurado se aplica sin pisar el existente), auditoría, avisos del equipo, clientes y bloqueo, cuenta personal sin equipo, eliminación de cuenta…) dentro de una transacción que se deshace.

La estructura de carpetas y las reglas de dependencia están en [estructura.md](estructura.md).

## Decisiones y límites conocidos

- **Tiempo real en el móvil**: el proxy es petición/respuesta, no WebSocket. "Mi turno" se refresca cada 15 s. Para tiempo real real hay que retransmitir eventos (Supabase Realtime alimentado por un worker) — requeriría cambios en la API (webhook/canal) y se plantearía como plan aparte.
- **Push**: igual que arriba; la API no tiene webhook ni canal FCM.
- **Hora de las franjas**: se muestra en la zona de la cola (desfase deducido de la API), no la del dispositivo.
- **Web y contraseña de Qhub**: la contraseña no se guarda en el navegador (solo el token, en `sessionStorage`); al vencer se pide conectar de nuevo.
- **Contraseña de Qhub en `organizacion_credenciales`**: protegida por permisos (solo `service_role`), en texto. Recomendado: pasarla a Supabase Vault.
- **La API no tiene refresh token**: ante un 401 la web pide conectar de nuevo.

## Invitaciones por correo

1. El administrador (Equipo → Invitar) escribe el correo, el rol y, si quiere, nombre, apellido y cargo. La Edge Function `qhub-invite` (solo administradores de organizaciones, no cuentas personales) valida, rechaza a quien ya es miembro, crea o actualiza **una** invitación pendiente por correo (vence a los 7 días) y envía el correo por Supabase Auth: invitación si no tiene cuenta, enlace de acceso si ya la tiene. Si el correo no sale (límite de envíos), la invitación queda y se comparte con el código.
2. El botón del correo lleva a `/invitacion?token=…`. Si no hay sesión se pasa por el login y se vuelve (el código se recuerda en `sessionStorage`). La página muestra equipo, rol y el perfil configurado (`ver_invitacion`: solo para el correo invitado), permite crear contraseña (opcional) y acepta (`aceptar_invitacion`, que copia el perfil sin pisar lo que la persona ya tenía).
3. El código también sirve a mano (Configura tu cuenta → Tengo una invitación). En la lista de pendientes va censurado (Mostrar/Ocultar, Copiar, Reenviar, Cancelar).
4. Los correos de Supabase solo se pueden personalizar con un SMTP propio (`SMTP_HOST`… en `.env.secret`, luego `python3 -I tool/supabase_auth.py`); las plantillas con botón están en `supabase/templates/`.

## Administrar personas

- **Equipo** (solo administradores, solo su organización): editar nombre, apellido, cargo y teléfono (`editar_miembro`), cambiar rol y acceso, y **quitar del equipo** (`quitar_miembro`: termina la pertenencia, no borra la cuenta; no se puede quitar a uno mismo ni al último administrador).
- **Clientes** (personas de la app móvil, información sensible): la organización solo puede **eliminarlos** de su lista (`eliminar_cliente`) o bloquearlos. Editar sus datos exige su permiso: `solicitar_edicion_cliente` → el cliente aprueba o rechaza (`responder_edicion_cliente`, desde la app móvil) → `editar_cliente` sirve para un solo cambio dentro de las 24 h. La pantalla de respuesta del cliente en la app móvil queda para la revisión final del móvil.
- Avisos para todos los roles: bienvenida al unirse, cambio de rol y, para administración, quién se une y clientes nuevos.
- **Contraseña inicial al invitar:** el administrador puede asignarla (o generarla) al invitar a alguien sin cuenta. Se crea con `qhub-invite` (`auth.admin.createUser`), **no se guarda en claro** y se le muestra al administrador una sola vez; la cuenta queda marcada en `app_metadata.clave_asignada`. Cambiarla después exige permiso del administrador (`solicitudes_miembros`: la persona la pide, el admin aprueba, vale 24 h y un solo cambio). Es una regla de la interfaz: la recuperación por correo («Olvidé mi contraseña») sigue disponible. Además, cualquier integrante puede pedirle al administrador un cambio de sus datos.
- **Equipo gestionado (solo organizaciones):** quien es parte de un equipo y no es administrador no cambia por su cuenta nombre, apellido, cargo ni teléfono (un trigger de la base lo impide; sí puede completarlos si están vacíos). Recuperar la contraseña por correo pasa por la función `qhub-recover`: sin permiso del administrador no se envía el correo y se le avisa; con permiso aprobado se envía y el permiso se gasta. Las **cuentas personales** y los **administradores** se gestionan solos. **Restricción real:** un disparador sobre `auth.users` (`trg_auth_gestionado`) impide que un integrante gestionado cambie su contraseña o su correo sin aprobación del administrador, venga de donde venga (la app, el enlace de recuperación o la API directa); el permiso se gasta con el cambio. Solo se toca el Supabase **de la app**; el de la API Qhub es otro proyecto y no se modifica (los integrantes nunca manejan la contraseña de Qhub: la conexión la guarda el administrador en el servidor).
- **Contraseña inicial:** al invitar, si el administrador no la escribe se genera sola. Queda en `claves_iniciales` (sin permisos directos; solo `ver_clave_inicial`, para el correo invitado) hasta que la persona acepta: la ve en la pantalla de la invitación, la copia y confirma que la guardó. La persona nunca elige su propia contraseña inicial.
- **Avisos de acciones:** todo lo importante (invitar, reenviar/cancelar, quitar o cambiar de rol a alguien, editar perfiles, eliminar clientes, crear/editar/archivar colas, publicar) se anota en `auditoria` y un disparador avisa a la administración (admin y supervisor) en la campana; los textos nunca llevan nombres de clientes.
- **Avisos emergentes:** `NoticePopups` (montado en el panel) consulta cada 10 s los avisos sin leer y muestra como notificación flotante (con botón «Ver», que respeta el rol) los que llegan nuevos; los que ya existían al abrir quedan solo en la campana. Si la pestaña está en segundo plano y la persona activó «Avisos del navegador» (Avisos → Activar avisos) sale además una notificación del sistema.
