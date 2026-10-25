# Decisiones de arquitectura de Doggo

Registro de las decisiones tomadas durante la construcción del MVP, con su motivo. Complementa a
[`modelo-de-datos.md`](modelo-de-datos.md) (tablas y reglas de la base) y al documento de contexto
original del producto.

## 1. Arquitectura general

| Decisión | Motivo |
|---|---|
| **Flutter** (un código para web, Android e iOS) + **Supabase** (Auth, Postgres, Realtime, Storage), **sin servidor propio** | Lo pide el contexto; plan gratuito; menos piezas que mantener. |
| **La seguridad vive en la base**: RLS, permisos por columna, `CHECK`, triggers y RPC `security definer` | Ocultar un botón no protege nada; un cliente malicioso puede llamar a la API directamente. |
| **Patrón `Repository`** con dos implementaciones: `DemoRepository` (en memoria) y `SupabaseRepository` | Cambiar de modo sin tocar la UI. El demo es el respaldo si Supabase falla. |
| **`DemoRepository` se construyó primero** (fase 2) | No había proyecto de Supabase; permite probar cada pantalla con Playwright desde el inicio. `SupabaseRepository` llegó después, con los mismos mensajes de error (traduce los códigos de la base). |
| **Modo real por defecto y "Probar demo" como respaldo**: con claves de Supabase la app arranca en real; "Probar demo" cambia a la demo en memoria y "Cerrar sesión" vuelve al real | Los revisores ven datos compartidos y en vivo, y la demo (con los 4 roles) sigue disponible aunque Supabase falle. |
| **Tiempo real**: `watchMyBookings` escucha `postgres_changes` de `bookings` (RLS filtra las ajenas) y recarga la lista; al quedar suscrito recarga una vez | Lo que cambia mientras se abre la conexión no llega como evento. Medido contra el proyecto real: solicitud al cuidador en ~0,8 s y aceptación al dueño en ~0,4 s. |
| Estado con **Riverpod**, navegación con **go_router** | Lo pide el contexto. |
| Mapa con **flutter_map + OpenStreetMap** | Sin API key y funciona en web. |
| Hosting en **GitHub Pages** con `--base-href /Doggo/` | El repositorio se llama `DoggoTech/Doggo` (no `doggo`). |
| **Workflows** `deploy.yml` (Pages en cada push a `main`, con `flutter analyze` y `flutter test` antes), `apk.yml` (tag `v*` o a mano → Release) y `keepalive.yml` (no hace nada mientras no haya `SUPABASE_URL`) | Publicar solo con GitHub, como pide el contexto. Sin secretos, todo sale en modo demo. |
| **APK firmado con la clave de depuración** | Basta para instalarlo directo; una clave propia hará falta solo para la Play Store. |

## 2. Base de datos (Supabase)

| Decisión | Motivo |
|---|---|
| Helpers en un schema **`private`** | PostgREST solo expone `public`: los helpers no son RPC llamables. |
| Las restricciones de cliente se detectan con **`current_user in ('anon','authenticated')`** | Dentro de una RPC `security definer` `current_user` cambia al dueño: las RPC internas no chocan con sus propias reglas, y no se puede falsificar desde la API. |
| Permisos **por columna** además de RLS | RLS filtra filas; los `GRANT` filtran columnas. Un usuario no puede cambiar su `role`, `status` ni `verified` (probado con llamadas directas). |
| **`dog_notes` separada de `dogs`** | RLS filtra filas, no columnas: así las notas médicas se ven solo con reserva `accepted`, y el nombre del perro desde `pending`. |
| **`profile_private`** para teléfono, dirección y ubicación exacta | Solo los ve el dueño y la contraparte de una reserva `accepted`. |
| **Ubicación pública desplazada 200–300 m, fija por usuario** (hash del id) | Si el desplazamiento cambiara en cada guardado, se podría promediar y recuperar la exacta. |
| **Rechazar a un cuidador = suspenderlo** | Se respetan los 3 estados del contexto (`pending_review`, `approved`, `suspended`). |
| Cuentas creadas **desde el panel de Supabase** nacen como dueño aprobado; las de la app **exigen** aceptar términos | Las 4 cuentas de prueba se crean en el panel y se les asigna rol con `assign_roles.sql`. |
| **Plazo de respuesta de 2 h** (o hasta 30 min antes del inicio); **reservar con ≥1 h** de anticipación | Decisión de producto. Columna `response_deadline`, validada en el trigger. |
| Estado **`expired`** + `expire_overdue_bookings()` con **pg_cron** cada minuto | Las solicitudes sin respuesta vencen solas. La app también muestra como vencida una `pending` con el plazo pasado. |
| **`sitter_availability`** en hora de **Bogotá**; sin filas = sin restricción | Horario semanal del cuidador; la reserva se valida contra él. |
| El total de la reserva **lo calcula la base** | Un cliente no puede fijar su propio precio. Guardería y hospedaje por día/noche. |
| No se borra un perro con reservas activas (trigger) | El cuidador perdería sus datos. |
| Pruebas con **PGlite** (Postgres real en WASM) y Supabase simulado | Verificar RLS y triggers sin crear un proyecto. `npm run db:serve` levanta la base para explorarla. |

## 3. Producto (decisiones del usuario)

- **Superadmin** entra al MVP (fase 10): pestaña **Equipo** (nombrar admin por correo exacto, quitar el rol, suspender o reactivar admins, auditoría completa); **Eliminar cuenta** en Usuarios solo para él. El admin ve **Mi historial** al final de Usuarios.
- **No se elimina ni se asciende** a quien tiene reservas activas: la otra parte perdería la reserva sin aviso.
- **Reserva en hoja compacta** que sube sobre el perfil, con `−` / `+` para día, hora, duración, días o noches.
- **Horario semanal** del cuidador; el dueño solo ve horas dentro de él (franja 7:00–19:00, pasos de 30 min).
- **Contacto** (teléfono y dirección) visible solo con la reserva **aceptada**, en ambos sentidos.
- **Zona de servicio obligatoria**: sin ella el cuidador no sale en el mapa (avisos al cuidador y al admin).
- **Aprobar = Verificar**: el admin revisa documento y selfie antes de aprobar; aprobar pone al cuidador en el mapa con la insignia "Verificado". No hay interruptor aparte: rechazar no verifica y reactivar a un cuidador lo deja aprobado y verificado. (Antes eran dos cosas; se unieron porque un "verificado" rechazado no tenía sentido).
- **Ubicación en vivo** del dueño (seguimiento con `getPositionStream`), que se apaga al salir del mapa.
- **Carlos Cuidador** (`cuidador@doggo.app`) sale en el mapa demo para recibir reservas.
- Panel **"Modo demo"** arriba en el perfil para cambiar de rol sin perder datos.

## 4. Frontend

| Decisión | Motivo |
|---|---|
| **No forzar `ensureSemantics()`** | Su capa de accesibilidad bloqueaba el arrastre del mapa con mouse. Flutter la activa cuando un lector de pantalla la pide. |
| Cada elemento accesible es **su propio nodo** (`Semantics(container: true)`) | Flutter fusionaba nodos: un botón quedaba dentro de un título y un campo de texto cubría toda una tarjeta. |
| **Diseño adaptable**: barra inferior en celular, riel lateral desde 840 px; en el mapa, panel lateral desde 720 px de contenido | La app debe verse bien en celular y en escritorio. |
| Filtro de **teléfonos, correos y enlaces** idéntico en Dart y en SQL | La app avisa al instante; la base lo impone igual. |
| Reglas de reserva (precio, plazos) en `lib/data/pricing.dart` y `booking_rules.dart`, **iguales al trigger** | Lo que la app muestra coincide con lo que la base acepta. |

## 5. Pruebas

- **Playwright e2e** en dos proyectos: móvil (Pixel 7) y escritorio. La accesibilidad se activa con el botón nativo de Flutter (`flt-semantics-placeholder`).
- Se **mockean** los tiles de OpenStreetMap y las fotos: las pruebas no dependen de la red.
- Lecciones de Flutter web: escribir con teclas y verificar el valor (`typeInto`); `dispatchEvent('click')` para elementos alcanzados desplazando o pines solapados; desplazar con la rueda (`scrollUntil`) porque Flutter solo construye lo visible; no recargar en el modo demo.
- **Unitarias** (`flutter test`) para el repositorio demo y las reglas; **base de datos** (`npm run test:db`).
- Flujo por fase: rama → implementar → probar → dictamen con guía de prueba → OK del usuario → merge `--no-ff`.

## 5b. Pulido (fase 12)

| Decisión | Motivo |
|---|---|
| **Pines agrupados** cuando se tapan en pantalla (grupo con el precio más bajo y el número de cuidadores; tocarlo acerca el mapa). Desde zoom 17 ya no se agrupa, y el seleccionado nunca. | Con 11 cuidadores en Bogotá varios pines quedaban uno encima de otro y no se podían tocar. |
| Dentro de un grupo, **cada cuidador conserva su propio nodo accesible** | Con lector de pantalla se llega a cada cuidador sin tener que acercar el mapa (y las pruebas e2e siguen encontrando cada pin). |
| **`ErrorState`** común con "Reintentar" | Antes algunas pantallas mostraban el texto técnico del error. |
| **`AppearIn`**: fundido corto al cambiar de pestaña y al aparecer una tarjeta | Microanimaciones del contexto; respeta "reducir movimiento" del sistema. |

## 6. Pendientes

1. **Después del MVP**: beneficios para cuidadores con buena calificación (niveles, destacar en el mapa), cuando haya reseñas reales.
