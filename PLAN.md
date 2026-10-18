# Qhub App — Plan y estado

Última actualización: 2026-10-18. Stack: **plataforma web (React + Vite + TypeScript + Tailwind)** y **app móvil (React Native + Expo + NativeWind)**, Clean Architecture, Docker Compose. **Sin IA**, por indicación del usuario.

## Hecho y verificado (`tool/verify.sh` → exit 0)

- [x] Monorepo npm workspaces: `@qhub/core`, `@qhub/api-client`, `@qhub/design`, `@qhub/web`, `@qhub/mobile`
- [x] Design system generado desde el artefacto: tokens → variables CSS, tema de Tailwind v4 (web) y NativeWind (móvil), 35 íconos y logos
- [x] **Web**: login/registro, organización (crear/invitación), conexión con Qhub (token en `sessionStorage`, la contraseña no se guarda), colas (listar, crear, editar horario, archivar, reactivar, límite 6/3), **fila en vivo** por WebSocket (llamar, finalizar, no-show), historial y métricas con CSV, equipo e invitaciones, ajustes, publicar en el móvil, claro/oscuro, roles admin/agente, code-splitting por ruta
- [x] **Móvil**: acceso, explorar, organización y colas, sacar turno ahora o reservar franja (hora en la zona de la cola), Mi turno (posición, estimado, cancelar, posponer), avisos, historial, perfil
- [x] Supabase `Qhub_App`: migraciones, RLS, Edge Functions `qhub-proxy` y `qhub-link` desplegadas
- [x] Docker: `node` (tipos/tests/builds), `web` (nginx), `qhub-api` local, `contract-tests`
- [x] Pruebas: 150 de unidad/UI (core 8 · api-client 48 · design 7 · web 56 · móvil 31) · 8 de contrato contra la API en contenedor · 9 de política del proxy (Deno) · 13 de seguridad RLS contra la base real
- [x] **Web ampliada**: inicio con dashboard por rol (KPIs, gráficos, lista de arranque), Mi perfil (datos, seguridad, preferencias, eliminar cuenta), recuperación de contraseña, roles `supervisor` y `recepcion` con matriz de permisos, selectores de país/ciudad/prefijo/hora (24 h)/fecha, historial por rango de fechas, shell responsivo con cajón y accesibilidad
- [x] **Web, segunda tanda**: avisos del equipo (campana + página), clientes de la app (lista, detalle, bloqueo con enforcement en el proxy), búsqueda global, menú contraíble, actualización automática configurable, dashboard ampliado con exportación CSV/PDF, verificación en dos pasos (TOTP), cambio de correo y sesiones, lista de arranque de 6 pasos
- [x] **Inicio y Dashboard separados**: Inicio = accesos rápidos + recientes + lista de arranque; Dashboard = indicadores con comparación, gráficas mejoradas (ejes, promedio, líneas, ranking), **vista de tabla en cada gráfica**, CSV por gráfica, CSV completo y PDF
- [x] **Panel de búsqueda** estilo Azure (historial con «Borrar todo», accesos recientes, atajos) · **Login** con la distribución de IBM Cloud y marca Qhub · logo y texto siguen el tema claro/oscuro
- [x] **Conectar con Qhub solo al crear la cuenta**: lo confirma la base de datos (`qhub_conectada_en`); después la app abre siempre y, si falta token, avisa dentro de la pantalla. **Página 404** con la marca
- [x] **Conexión con Qhub una sola vez**: se guarda en el servidor (`qhub-link` conectar/publicar/despublicar/desvincular) y `qhub-token` entrega el token al iniciar sesión y al vencer; también para agentes. Requiere `QHUB_API_BASE_URL` (API con URL pública)
- [x] **Solo producción**: `docker compose up -d --build` construye y sirve la web (nginx, :8080) y el móvil (bundle de Android con nginx, :8082). APK instalable con `tool/build-apk.sh`. Sin servidores de desarrollo, recarga en caliente ni Expo Go.
- [x] **Cabecera**: buscador centrado, logo que lleva al Inicio, ícono de búsqueda en móvil; login con la imagen a la izquierda y el formulario a la derecha
- [x] **Tipos de cuenta**: persona natural (espacio personal, rol *titular*, sin equipo, 3 colas) u organización (empresa, equipo y roles, 6 colas); se elige al crear la cuenta; la base impide equipo en una cuenta personal
- [x] **Prefijo de turno sugerido** a partir del nombre de la cola (sin repetir los de otras colas), editable
- [x] **Reorganización**: estructura estándar por feature (carpetas planas; capas por nombre de archivo, comprobadas por `architecture.test.ts`), `shared/ui`, `testing/`, pruebas junto al código; lo repetido entre web y móvil centralizado en `@qhub/core` (validaciones, formatos, CSV, fechas, geografía, prefijos, errores de Supabase, `.env`); repositorios de `api-client` por recurso; guía en `docs/estructura.md`
- [x] **API** (autorizado por el usuario): `ENFORCE_TURN_OWNERSHIP` (apagada por defecto) valida a la persona en turnos; prueba `tests/test_turn_ownership.py`
- [x] Bundle de Android con Metro + NativeWind y imagen de producción de la web servida con nginx (SPA, cabeceras de seguridad)
- [x] **Equipo y seguridad**: invitaciones por correo con perfil configurado y contraseña inicial que la persona ve y copia al aceptar; integrantes gestionados (datos, contraseña y correo solo con aprobación del administrador, aplicado en Auth); solicitudes e historial en Equipo; cambio de cuenta entre pestañas
- [x] **Avisos**: para todos los roles, por acciones importantes (auditoría), emergentes y del navegador
- [x] **Clientes**: solo eliminar; editar sus datos exige su permiso (el cliente aprueba o rechaza desde Avisos del móvil)
- [x] **Móvil como red de organizaciones**: buscar por nombre o ID (QH-XXXXXX), vincularse (varias a la vez), ver colas y sacar turno solo vinculado; el cliente aparece en la plataforma
- [x] **Entorno central**: un solo `.env` en la raíz; Docker lo reparte a web y móvil; `tool/build-apk.sh` genera el APK

## Pendiente (requiere decisión o acción tuya)

- [ ] **Publicar la API** con URL pública y fijar `QHUB_API_BASE_URL` como secret de las Edge Functions: sin eso el móvil no opera de punta a punta
- [ ] **Rotar el Personal Access Token** `sbp_…` compartido por chat, y los de la API (ver su `PENDIENTES.md`)
- [ ] **APK firmado para tiendas / IPA**: `tool/build-apk.sh` genera un APK instalable (llave de depuración); para Google Play o App Store hace falta tu propia llave (EAS Build o Gradle/Xcode)
- [ ] **Correo propio (SMTP)** para correos con la marca y sin el límite de envíos de Supabase (`SMTP_*` en `.env`, luego `python3 -I tool/supabase_auth.py`)
- [ ] **Probar el APK en un teléfono o emulador** (`tool/emulator.sh` está listo pero no se terminó de probar)
- [ ] **Tiempo real y push en el móvil**: requieren cambios en la API → **plan aparte** (Regla #2)
- [ ] Mover la contraseña de Qhub de `organizacion_credenciales` a Supabase Vault
- [ ] Activar `ENFORCE_TURN_OWNERSHIP=true` en el despliegue de la API cuando la app móvil esté en producción
- [ ] Revisión final del móvil: perfil (misma edición que la web, con los límites de gestionado) y selectores de país/ciudad
- [ ] Contraseña inicial de invitaciones (`claves_iniciales`): hoy en texto hasta que se acepta; cifrarla o moverla a Vault
- [ ] Revisar las pantallas autenticadas con datos reales de Qhub (se revisaron con respuestas simuladas)
- [ ] IA (estimación avanzada, picos, asistente): **no iniciada, por indicación del usuario**
