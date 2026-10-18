# Estructura del repositorio

Una sola idea: **cada cosa vive en un solo lugar**. Lo que usan web y móvil está en `packages/`; lo que es de una app, dentro de su carpeta; y dentro de cada app todo se organiza por *feature* con las mismas tres capas.

```
Qhub_App/
├─ apps/
│  ├─ web/                       React + Vite + TypeScript + Tailwind v4 (panel de administración)
│  └─ mobile/                    React Native + Expo + NativeWind (app pública)
├─ packages/                     Código compartido (nada de React aquí, salvo el diseño generado)
│  ├─ core/                      Result/Failure, validaciones, formatos, CSV, fechas, geografía,
│  │                             prefijos de cola, variables de entorno y mapeo de errores de Supabase
│  ├─ api-client/                Único lugar que conoce la API Qhub: entidades, puertos, casos de uso,
│  │                             repositorios por recurso, transporte HTTP y tiempo real (WebSocket)
│  └─ design/                    Tokens del design system → CSS, Tailwind, íconos y logos (generado)
├─ supabase/                     Migraciones, Edge Functions (qhub-proxy, qhub-link) y pruebas de RLS
├─ docker/  compose.yaml         Imágenes (node, nginx) y servicios
├─ tool/                         verify.sh, acceso a SQL y configuración de autenticación de Supabase

└─ docs/                         Esta guía y la de arquitectura
```

## Dentro de cada app

```
src/
├─ main.tsx · index.ts           Arranque
├─ app/                          Composición: lo único que conoce a todas las features
│  ├─ App.tsx  container.tsx     Raíz de dependencias (en las pruebas se sustituye por fakes)
│  ├─ env.ts                     Variables públicas (VITE_* / EXPO_PUBLIC_*)
│  ├─ AppRoutes.tsx              Rutas y puerta de acceso (web); `resolve-redirect.ts` es la política pura y probada
│  └─ *.test.tsx                 Pruebas de recorridos completos que cruzan varias features
├─ features/<feature>/           Una carpeta PLANA por capacidad de negocio (sin subcarpetas)
├─ shared/
│  ├─ ui/                        Kit visual (solo utilidades de Tailwind sobre los tokens)
│  └─ *.ts                       Utilidades sin negocio (p. ej. `download.ts`, `invoke-function.ts`)
├─ architecture.test.ts          Comprueba las reglas de capas por nombre de archivo
└─ testing/                      Fakes, arnés de render y configuración de pruebas
```

Las pruebas viven **junto a lo que prueban** (`algo.ts` → `algo.test.ts`). Las de recorridos completos, en `app/`.

## Capas: se reconocen por el nombre del archivo

Cada feature es una sola carpeta; la capa de cada archivo la dice su nombre:

| Archivo | Capa | Puede usar |
|---|---|---|
| `*.tsx`, `use*.ts`, `hooks.ts` | **presentación** (pantallas, componentes, hooks) | React, router, TanStack Query, el dominio y `shared/` |
| `supabase-*.ts`, `device-*`, `session-token-store.ts` | **datos** (adaptadores) | Supabase, `fetch`, WebSocket, almacenamiento del navegador |
| cualquier otro `.ts` (`organization.ts`, `permissions.ts`, `repository.ts`…) | **dominio** | solo TypeScript puro |

```
presentación ──▶ dominio ◀── datos
      │              ▲
      └── shared ────┘         app/ solo cablea; ninguna feature importa de otra feature
                               salvo lo que ésta publica como dominio (p. ej. permisos, historial)
```

- El dominio no importa React, `fetch`, Supabase, el router ni nada de datos o presentación. `architecture.test.ts` lo comprueba en cada corrida de pruebas.
- Nada de Supabase ni `fetch` fuera de los archivos de datos. Los errores llegan a la UI como `Failure`.
- Si algo lo necesitan **web y móvil**, va a `packages/` (no se copia). Si solo lo usa una app, se queda en ella.
- Un archivo por concepto; nombres en `kebab-case` (lógica) y `PascalCase` (componentes).

## Features de la web

| Feature | Qué contiene |
|---|---|
| `session` | Estado de sesión de toda la app (usuario, organización, conexión con Qhub, verificación en dos pasos) |
| `staff` | Personas y organización: identidad, roles, permisos, perfil, puertos (`repository.ts`) y adaptador Supabase |
| `auth` | Acceso, registro, alta de la cuenta (persona u organización), recuperar contraseña y código de verificación |
| `qhub` | Conexión de la cuenta con la API Qhub |
| `queues` · `live` · `history` | Colas y horarios, fila en vivo, historial y métricas |
| `home` | Inicio: saludo, accesos rápidos, páginas recientes, lista de arranque y colas ahora |
| `dashboard` | Dashboard: periodos, comparación, gráficas con vista de tabla, CSV y PDF |
| `invitation` | Página `/invitacion` (botón del correo) y la invitación recordada durante el inicio de sesión |
| `clients` · `team` | Personas de la app móvil (con bloqueo) y equipo con roles e invitaciones |
| `notifications` | Avisos del equipo |
| `profile` · `security` | Mi perfil y seguridad (contraseña, correo, sesiones, verificación en dos pasos) |
| `preferences` | Tema, accesibilidad y actualización automática |
| `settings` · `geo` · `shell` | Ajustes de la organización, selectores de ubicación/teléfono y el marco de la app (menú, búsqueda, campana) |

Los puertos de `staff` están partidos por responsabilidad (`AuthPort`, `ProfilePort`, `OrganizationPort`, `TeamPort`, `QueueLabelPort`) y `StaffRepository` los reúne.
