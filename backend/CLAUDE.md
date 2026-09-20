# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es esto

`backend/` del TFG **DuelVault**: API REST para catalogar una colección real de
Yu-Gi-Oh! (4.533 filas históricas, 27 tablas). Monorepo: `backend/`, `frontend/`
(Angular, sin empezar), `db/`, `docs/` (diseño cerrado: modelo de datos, 11
pantallas y ADRs).

**Estado real del backend hoy:** existe `BackendApplication.java` y el árbol de
paquetes hexagonal (6 contextos, solo con `package-info.java`). El dominio, los
casos de uso y los adaptadores están por crear. Solo hay el smoke test generado:
faltan los tests de ArchUnit (paso 2, bloque C) y Testcontainers. No hay CI. El
`pom.xml` trae `data-jpa`, JDBC, Flyway y ArchUnit. `application.yaml` ya tiene
datasource + Flyway configurados.

## Comandos

Wrapper Maven (`./mvnw` en bash, `mvnw.cmd` en PowerShell). Java 25, Spring Boot 4.1.1.

| Acción | Comando |
|---|---|
| Compilar + empaquetar | `./mvnw clean package` |
| Arrancar la app | `./mvnw spring-boot:run` |
| Todos los tests | `./mvnw test` |
| Un test | `./mvnw test -Dtest=NombreClase` |
| Un método | `./mvnw test -Dtest=NombreClase#nombreMetodo` |

No hay linter/formatter configurado. Los tests de integración usarán
**Testcontainers**, que levanta su propio PostgreSQL: no hace falta tener uno
arrancado a mano. Los tests de dominio no levantan nada.

## Base de datos y migraciones

- PostgreSQL 16 vía `docker-compose.yml` en la raíz (solo el servicio `db` por
  ahora; backend y frontend se añadirán). `docker compose up -d` para arrancar.
  DB/user/pass = `duelvault` en desarrollo.
- Migraciones Flyway en `backend/src/main/resources/db/migration/`
  (`V1__init_schema.sql`, `V2__reference_data.sql`).
- El `V1` **declara su propio esquema** (`CREATE SCHEMA duelvault` + `search_path`)
  porque `immutable_unaccent()` cita el diccionario `duelvault.unaccent` por su
  nombre completo. No heredar el esquema de la configuración de Flyway.
- Flyway siempre; **jamás `ddl-auto: update`**.
- Una migración aplicada no se edita. En desarrollo se recrea la base:
  `docker compose down -v`. (El `V1` sí se ha revisado en sitio porque **todavía
  no hay ninguna base desplegada**; a partir del primer despliegue, cada cambio
  es una migración nueva.)
- `db/migrations/anexo-migraciones-historicas/` guarda `V3__binders_slots_alt_art.sql`
  y `V4__fixes_frontron.sql`: son **migraciones de diseño de DuelVault**, aplastadas
  en el `V1` antes del primer despliegue y conservadas como evidencia documental
  para la memoria (el `DROP`/`ADD` de cada corrección prueba que el defecto
  existió). El nombre "frontron" es un desliz del fichero, no otro proyecto. **No
  se ejecutan y no se borran.**

## Arquitectura — reglas no negociables

Módulo por contexto, hexágono dentro de cada uno:
`com.duelvault.{catalog,collection,pricing,scanning,security,shared}`
y dentro `domain/ · application/{usecase,port/{in,out}} · infrastructure/{in/web,out/{jpa,jdbc}}`.

- `domain/` no importa Spring, JPA ni ninguna librería de terceros. Un test de
  **ArchUnit** falla si lo hace.
- Las `@Entity` viven solo en `infrastructure/out/jpa`, con mapper explícito a los
  modelos de dominio. Nunca cruzan hacia `application` ni `web`.
- Los puertos los define el dominio por lo que necesita, no el adaptador por lo
  que ofrece Spring Data.
- **Interfaz obligatoria en los puertos de salida; en los de entrada, no.** El
  adaptador no puede ser conocido por el caso de uso, así que la interfaz de
  salida invierte esa dependencia y hace trabajo real. El controlador ya puede
  importar el caso de uso (va de fuera hacia dentro), así que ahí se usa la clase
  directamente.
- El error a evitar es la **"hexagonal de mentira"**: usar entidades JPA como
  modelo de dominio.

### Casos de uso

- **Uno por problema, un solo método público, y no se llaman entre sí.** Cada caso
  de uso es un límite de transacción, y la lista de clases en `application/usecase`
  es la lista de lo que el sistema sabe hacer.
- Lo que dos casos de uso comparten **baja al dominio** (método de la entidad o
  servicio de dominio). Nunca se extrae a un tercer caso de uso. Ejemplo: partir
  una fila es `CollectionItem.partir(...)`, y lo usan vender y archivar.
- Se nombran por el problema, no por la operación CRUD: `ArchivarEjemplar`,
  `RecolocarCarta`, `VenderEjemplar`. No `ActualizarCollectionItem`.
- Entrada por objeto `Command` propio del caso de uso, salida por `record`. Nunca
  el DTO del controlador ni la entidad.
- No hay un caso de uso por tabla. `CardPrint` no se crea sola, nace al registrar
  un ejemplar.

### DDD táctico, donde paga

- **`collection` lleva modelo rico**: objetos valor (`Ubicacion` con carpeta, hoja,
  cara y hueco; `Money`, que vive en `shared`), comportamiento en la raíz, y servicio de
  dominio para lo que cruza agregados (recolocar, validar hueco contra
  `slots_per_face`).
- **`catalog` se modela ligero** a propósito: una carta no tiene invariantes propias
  más allá de las del esquema. Objetos valor sí; ceremonia no.
- Un repositorio **por raíz de agregado**, no por tabla. No existe
  `MonsterCardRepository`: se carga y se guarda `Card` entera.
- **Referencia entre agregados por id**: `CollectionItem` guarda un `CardPrintId`,
  no un `CardPrint`.
- **Límites de agregado y contextos (ADR-012)**: `CardPrint` es raíz propia (no cuelga de
  `Card`); `Binder` es raíz separada de `CollectionItem`; `Passcode` pertenece a `catalog`.
  Un contexto solo importa del dominio de otro sus tipos de identidad. La escritura entre
  contextos va por puerto de salida; la lectura de pantallas, por proyección SQL. En
  `shared` solo entra lo que usan dos o más contextos y ninguno posee (`Money`, jerarquía
  de errores). La infraestructura transversal (`@RestControllerAdvice` RFC 9457,
  envoltorio `{metadata,data}`, paginación, adaptador de `error_catalog`) vive en
  `shared/infrastructure/{in/web,out/...}`.
- Sin setters públicos en el dominio. Constructores que validan.
- Nada de eventos de dominio, event sourcing ni CQRS con dos bases: no hay nada
  que reaccione a nada.

### Reparto entre base de datos y dominio

La regla no es "nada de lógica en la base de datos". Es:

> **La base de datos garantiza invariantes que no pueden depender del código; el
> dominio decide y explica.**

- Los `CHECK` y las restricciones `UNIQUE` del esquema **están bien puestos** y no
  se quitan. Los dos disparadores existentes (`clear_location_on_binder_delete`,
  `clear_artwork_label_on_original_delete`) no deciden nada: limpian columnas que
  quedarían incoherentes al desvincular una fila.
- Lo que sí queda prohibido es un disparador que **calcule reglas de negocio** (por
  ejemplo contar cuántas cartas caben en una cara). Eso vive en el dominio, que es
  quien puede dar el mensaje útil.
- Criterio completo en `docs/07-Casos-limite.md §E`.

## Persistencia (ADR-011)

- **JPA / Spring Data JPA como adaptador principal**, y devuelve modelos de dominio.
- **`JdbcClient` no se añade todavía.** El buscador se implementa primero con
  `@Query(nativeQuery = true)`. El disparador para introducir `infrastructure/out/jdbc`
  está escrito en el ADR-011.
- El corte, cuando llegue, es **agregado contra proyección**: si el resultado se va
  a modificar o respeta invariantes, repositorio JPA con dominio; si son datos de
  pantalla, SQL nativo a un `record`.
- Las consultas de pantalla devuelven `record` de proyección **desde ya**, aunque se
  escriban con JPA.
- Lecturas con `@Transactional(readOnly = true)` y **sin mezclarlas con escrituras**
  en la misma transacción: `JdbcClient` es invisible para Hibernate y no vería los
  cambios pendientes de flush (y al revés, un `UPDATE` nativo sobre filas cargadas
  puede acabar sobrescrito).
- El buscador necesita SQL nativo sí o sí: `immutable_unaccent(...) ILIKE ...` con
  trigramas, y `search_vector @@ websearch_to_tsquery('spanish_unaccent',
  strip_enclitics(:q))` con `ts_rank`. **Nada de Criteria API.**

## Modelo de datos (resumen; detalle en `docs/03-Modelo-de-datos.md`)

Separación en tres niveles, clave del dominio:

- `cards` — carta canónica por passcode oficial de 8 dígitos (`CHAR(8)`, los ceros
  a la izquierda son significativos); puede apuntar a otra como arte alternativo.
- `monster_cards` / `spell_cards` / `trap_cards` — especialización 1:1 por clase.
- `card_prints` — cada impresión: set, número, rareza, edición, idioma. La rareza
  es parte de la clave.
- `collection_items` — cada ejemplar poseído: ubicación física (carpeta, hoja,
  **cara**, hueco), estado, precio pagado.
- `price_snapshots` — histórico de precios (fase 2).

Detalles que se olvidan y rompen cosas:

- **`quantity` cuenta todas las copias poseídas**; el hueco localiza solo la
  archivada. Una fila con hueco 4 y cantidad 3 es correcta. La estantería **no**
  cuenta con `SUM(quantity)`.
- **Un monstruo se mide por Nivel, Rango o Link Rating: exactamente uno**, y el
  marco lo determina. Un Xyz siempre lleva Rango (puede ser 0); un Enlace siempre
  lleva Link Rating y nunca DEF.
- **Cada venta es una fila.** Vender 1 de 3 baja la original a 2 y crea otra con
  cantidad 1 y estado `SOLD`. No se fusionan. Una vendida no tiene ubicación.
- **Recolocar cartas** abre transacción y hace `SET CONSTRAINTS
  uq_collection_items_slot DEFERRED`. Es el único punto donde el límite
  transaccional importa.
- **Todo endpoint de listado lleva el parámetro `owned`**, por defecto `true`
  (póliza de B4).
- Borrar una carta o un set de los que se poseen ejemplares **falla** por la cadena
  `cards`/`card_sets` → `card_prints` (CASCADE) → `collection_items` (RESTRICT).
  Es correcto, pero el caso de uso debe comprobarlo antes y explicarlo.

La taxonomía (atributos, tipos de monstruo, marcos, rarezas) sale de la BD oficial
de Konami, no del dataset propio.

## Decisiones de arquitectura

`docs/ADRs/` con formato *Contexto → Decisión → Alternativas → Consecuencias*.
Diez aceptados, dos en estado `Propuesta` (003 autenticación, 006 duplicados del
dataset). **Un ADR no se edita: si la decisión cambia, se escribe uno nuevo que lo
sustituye.** Cada fase se cierra con el suyo.

Antes de proponer un cambio de arquitectura o de esquema, comprobar si ya hay un
ADR que lo cubra.

## Roadmap (dónde estamos)

Discovery ✅ · Diseño de datos, pantallas y ADRs ✅ · **Backend ← estamos aquí** ·
Frontend (Angular) · Estadísticas · Escaneo por cámara (OCR del passcode con
OpenCV + Tesseract, post-MVP) · Memoria y demo.

Orden del trabajo de backend, con detalle y criterio de terminado en `ROADMAP.md`:
convenciones de API → esqueleto hexagonal + ArchUnit → Testcontainers con los trece
casos de `07-Casos-limite` → **migración de las 4.533 filas** → catálogo en lectura
→ buscador → seguridad → colección → Envers → CI.

El testing y la migración **no** son fases finales: van donde tocan.

## Contexto académico

TFG de Ingeniería Informática. **Jaime programa todo el código**; Claude Code se usa
para revisión y dudas de implementación, vigilando que lo escrito cumpla la
arquitectura de este documento. `docs/` es la base de conocimiento de diseño.

Java 25 y Spring Boot 4.1.1 van por delante de buena parte de la documentación
publicada. Ante una duda de versión, comprobar con `./mvnw dependency:tree` en vez
de asumir.
