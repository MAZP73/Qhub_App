# Qhub App

Una **plataforma web** (React + TypeScript) para administrar cada organización y una **app móvil** (React Native) para el público, ambas sobre la [API Qhub](../Qhub). Clean Architecture, estilos con **Tailwind** (web: Tailwind v4; móvil: NativeWind) y todo — tipos, tests, builds, API local — con **Docker Compose**.

| | Web `apps/web` | Móvil `apps/mobile` |
|---|---|---|
| Para quién | Personal de una organización (admin / agente) | Público |
| Stack | React 19 · Vite · TanStack Query · React Router · Tailwind v4 | React Native (Expo) · React Navigation · TanStack Query · NativeWind |
| Hace | Colas y horarios, fila en vivo (WebSocket), llamar / finalizar / no-show, historial y métricas (CSV), equipo, publicar en el móvil | Explorar organizaciones, sacar turno (ahora o reservado), ver posición y espera, avisos, historial |
| API Qhub | Directa (login de la organización) | **Nunca directa**: por la Edge Function `qhub-proxy` |

> El diseño sale **siempre** del design system: https://claude.ai/artifact/359jKRUBxnvzJYn9nH8Srv (ver [CLAUDE.md](CLAUDE.md)). Sus tokens se convierten en el tema de Tailwind con `npm run generate -w @qhub/design`.

## Estructura

```
packages/
  core/          Result, Failure, formato de turnos (TypeScript puro)
  api-client/    Cliente de la API Qhub: domain (entidades, puertos, casos de uso) + data (fetch, WebSocket)
  design/        Tokens → CSS vars + tema de Tailwind (web) + NativeWind (móvil), íconos y logos generados
apps/
  web/           features/{auth,qhub,shell,queues,live,history,team,settings,staff}
  mobile/        features/{auth,organizations,gateway,tickets,notifications,history,profile}
supabase/        migrations · functions (qhub-proxy, qhub-link + política con tests) · tests (RLS)
docker/ compose.yaml tool/ docs/
```

## Estructura

`apps/` (web y móvil) · `packages/` (core, api-client, design: lo compartido) · `supabase/` · `tool/` · `docs/`. Cada app se organiza por *feature* (una carpeta plana por capacidad; la capa —dominio, datos o presentación— se reconoce por el nombre del archivo), y lo común a web y móvil vive en `packages/` para no repetirlo. Guía completa: [docs/estructura.md](docs/estructura.md).

## Cómo se ejecuta todo (Docker)

```bash
tool/verify.sh                   # tipos + tests + builds + política del proxy + contrato contra la API + RLS
tool/verify.sh --web-image       # además construye las imágenes de producción (web y móvil)

docker compose up -d --build                               # producción: web (nginx) en http://localhost:8080 y móvil (bundle Android) en http://localhost:8082
docker compose --profile tools run --rm node bash          # shell con Node 22
docker compose --profile local-api up -d qhub-api          # API local (sin credenciales reales)
docker compose --profile local-api run --rm contract-tests # pruebas de integración contra ella
```

**Móvil.** `tool/build-apk.sh` compila el **APK de Android** en Docker (gratis, sin cuenta de Expo) y lo deja en `apk/qhub.apk`: cópialo al teléfono (cable, Drive, WhatsApp…) e instálalo aceptando «instalar apps de orígenes desconocidos». La primera vez tarda bastante (descarga el SDK de Android); las siguientes aprovechan la caché. Está firmado con llave de depuración: sirve para instalar directo, no para subirlo a Google Play (para eso, EAS Build o tu propia llave). `docker compose up -d --build` además compila el bundle de producción (`expo export`) y lo sirve con nginx en `http://localhost:8082`. No hay Expo Go ni servidores de desarrollo.

## Configuración

Todo el entorno vive en **un solo archivo**: el `.env` de la raíz (gitignored, ya está puesto; no hay archivos `.example`). Docker Compose lo lee solo y reparte lo público a cada app con el prefijo que necesita; `tool/` lo lee para las migraciones.

| Variable | Para qué |
|---|---|
| `APP_ENV`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Públicas. Compose las pasa a la web (`VITE_*`) y al móvil (`EXPO_PUBLIC_*`) al construir |
| `QHUB_API_URL`, `QHUB_WS_URL` | Públicas, solo web (el móvil habla con `qhub-proxy`). En producción: la URL de Render (`https://` y `wss://`) |
| `SUPABASE_PROJECT_REF`, `SUPABASE_ACCESS_TOKEN`, `APP_URLS` | Secretas: solo `tool/` (migraciones, autenticación, despliegue de funciones). **Nunca** llegan a una app |
| `SMTP_*` (opcional, comentadas) | Correo propio para los correos con tu marca |

Para cambiar algo (por ejemplo la URL de la API al desplegar) edita `.env` y corre `docker compose up -d --build`. La `service_role` de Supabase la inyecta Supabase en las Edge Functions; no vive en ningún archivo del proyecto.

**La pantalla de conectar con Qhub sale solo al crear la cuenta.** Al conectar por primera vez, un administrador deja registrado en la base de datos (`organizaciones.qhub_conectada_en`, función `confirmar_conexion_qhub`) que la conexión ya se hizo; desde entonces **ninguna sesión vuelve a ver esa pantalla**, sin depender de la API ni del navegador. Si en una sesión falta el token y no hay conexión guardada que lo renueve, la app abre igual y muestra un aviso «Falta reconectar con Qhub» con una ventana para escribir la cuenta (se guarda para no pedirla más).

**La conexión con Qhub se hace una sola vez.** (Si el servidor no puede guardarla —por ejemplo, tu API aún no tiene URL pública— queda guardada **cifrada en este dispositivo** con una clave del navegador que no se puede extraer, y también entras directo; se borra con «Olvidar la conexión guardada».) La primera vez (o al registrarte) un administrador conecta su cuenta Qhub; la conexión se guarda **en el servidor** (`organizacion_credenciales`) y, al iniciar sesión, la plataforma pide un token a la función `qhub-token` sin escribir nada. Funciona también para agentes y recepción, que no necesitan saber la contraseña de Qhub; el token vencido se renueva solo. La contraseña nunca vuelve al navegador. En *Ajustes → Conexión con Qhub* se puede olvidar la conexión guardada; publicar o dejar de publicar en el móvil ya no pide la contraseña.

La Edge Function necesita un secret con la **URL pública de la API Qhub** (las funciones corren en la nube y no alcanzan `127.0.0.1`). **Sin ese secret no se puede guardar la conexión ni usar el móvil**; la plataforma lo avisa al conectar y sigue funcionando con la conexión de la sesión:

```bash
docker run --rm -e SUPABASE_ACCESS_TOKEN -v "$PWD:/work" -w /work node:22-slim \
  npx -y supabase@latest secrets set QHUB_API_BASE_URL=https://api.tu-dominio.com --project-ref <ref>
```

## Tipos de cuenta y roles

La plataforma sirve a una **persona natural** (cuenta personal: espacio propio, hasta 3 colas, sin equipo; su rol es *titular*) o a una **organización** (empresa: hasta 6 colas, equipo, invitaciones y clientes). Se elige al crear la cuenta y no se cambia; coincide con los dos tipos de cuenta de la API Qhub. Roles de una organización:

`superadmin` (plataforma) · `usuario` (público) · y por organización:

| Rol | Puede |
|---|---|
| `admin` | Todo: colas, equipo, **clientes** (con su correo y teléfono, y bloquearlos), ajustes, publicar en el móvil, atender, exportar y recibir avisos |
| `supervisor` | Ver inicio, colas, fila en vivo, historial, equipo y **clientes** (nombre y actividad, sin contacto ni bloqueo); recibe avisos y exporta. No atiende ni edita |
| `agente` | Atender la fila, consultar el historial y exportar |
| `recepcion` | Atender la fila. Sin historial, equipo, clientes, avisos ni ajustes |
| *titular* | Solo en una **cuenta personal**: todo lo del administrador excepto el equipo (no existe) |

El rol nunca viene del cliente; ver [docs/arquitectura.md](docs/arquitectura.md). La API Qhub solo conoce `admin` y `agente`: el resto opera como `agente` y la web limita lo que ven. La matriz vive en `apps/web/src/features/staff/permissions.ts`.

## Recuperación de contraseña y URLs permitidas

La web ofrece «¿Olvidaste tu contraseña?» (el correo trae un enlace a `/restablecer`). Para que esos enlaces funcionen, `python3 -I tool/supabase_auth.py` fija en Supabase la URL del sitio y las redirecciones permitidas (`APP_URLS` en `.env.secret`, por defecto `localhost:8080` y `localhost:5173`) y exige contraseñas de 8+ caracteres.

## Avisos, clientes y bloqueo

- **Avisos** (campana de la cabecera y página *Avisos*): los generan triggers de la base cuando alguien se une al equipo, guarda la organización o saca su **primer** turno. Llegan solo a administradores y supervisores; el contenido no se edita desde el navegador.
- **Clientes**: las personas de la app móvil que usan tu organización (lista agregada por `clientes_organizacion`, con búsqueda, filtros, orden, detalle con sus últimos turnos y exportación CSV). El administrador ve el contacto y puede **bloquear** a un cliente: la función `qhub-proxy` le niega sacar turnos (403) mientras esté bloqueado.
- **Inicio** (accesos a la mano): saludo y resumen del día, **accesos rápidos** a cada módulo según el rol (con avisos sin leer y colas), páginas visitadas hace poco, la lista «Termina de configurar» (perfil, verificación en dos pasos, datos de la cuenta, cola, publicación y equipo) y el estado de las colas.
- **Dashboard** (`/dashboard`): el análisis. Periodos Hoy / 7 / 30 días, indicadores **comparados con el periodo anterior**, y gráficas (turnos por día u hora, espera promedio, estado, resumen por cola, clientes nuevos) con ejes, promedio y leyenda. **Cada gráfica se puede ver como tabla y descargar en CSV.** Arriba: **Descargar CSV** (reporte completo) y **Descargar PDF** (se guarda desde el diálogo de impresión, con las tablas incluidas).
- **Búsqueda** (Ctrl K o `/`): panel con el **historial de búsqueda** (con «Borrar todo»), las páginas visitadas hace poco en mosaico y, al escribir, páginas, colas y personas del equipo según el rol. El historial queda solo en este navegador.
- **Menú lateral** contraíble a 48 px (se recuerda) y cajón en móvil.
- **Actualización automática**: cada pantalla se actualiza sola cada 5, 10, 20, 30 o 60 s (o solo a mano); se elige en la propia pantalla o en *Mi perfil → Preferencias*. Las consultas pesadas (historial) no se recargan antes de 30 s.
- **Tema claro/oscuro** (del sistema o elegido): el logo cambia solo a su versión negativa y todo el texto cumple contraste AA en ambos temas (auditado con un script que mide cada elemento).

## Página 404

Una dirección que no existe muestra una página 404 con la marca (dentro de la app, con su menú), sin repetir lo que se escribió; sin sesión, cualquier dirección lleva al acceso y no revela qué páginas existen.

## Errores y avisos seguros

Ningún error muestra detalles técnicos: sin nombres de tablas, restricciones, servicios internos, rutas, tokens, trazas ni textos crudos en inglés. `Failure` filtra el mensaje en su constructor (lo técnico se reemplaza por uno genérico en español), la API no revela sus roles ni sus campos, los 5xx son siempre genéricos, no se confirma si un correo ya existe, una pantalla que falla muestra «Algo salió mal» (con `ErrorBoundary`, web y móvil) y los errores de arranque van a la consola. El servidor web no anuncia su versión.

## Perfil y accesibilidad

En **Mi perfil**: datos personales (con país, ciudad y prefijo telefónico elegidos de listas), verificación en dos pasos (app autenticadora con código QR; al iniciar sesión se pide el código), cambio de contraseña y de correo, sesiones (cerrar las otras o todas), actividad reciente, nivel de seguridad, preferencias (tema, actualización automática, texto más grande, menos movimiento, contraste alto) y eliminación de la cuenta (con confirmación y la regla del último administrador). La interfaz usa menú con salto al contenido, foco visible, diálogos que atrapan el foco y gráficos con alternativa en texto.
