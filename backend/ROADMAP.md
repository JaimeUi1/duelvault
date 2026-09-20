# Roadmap — DuelVault backend

Guía de estado para retomar el trabajo. Se actualiza a mano cuando cambia la fase.
Última revisión: 2026-09-19.

## Fases del TFG

- [x] Discovery
- [x] Diseño de datos y pantallas (`docs/00`, `docs/02`, `docs/03`, `docs/07`, `docs/perfil-dataset.md`)
- [x] Decisiones de arquitectura documentadas (`docs/ADRs/`, doce escritos)
- [ ] **Backend ← estamos aquí**
- [ ] Frontend (Angular)
- [ ] Estadísticas
- [ ] Escaneo por cámara (OCR passcode, OpenCV + Tesseract) — post-MVP
- [ ] Memoria y demo

El diseño de API deja de ser una fase bloqueante. El testing y la migración de datos
no son fases finales: van dentro del trabajo, donde tocan.

---

## Decisiones

**Cerradas**

- **Persistencia** → ADR-011. JPA como adaptador principal; `JdbcClient` no se añade
  todavía, y el disparador para hacerlo está escrito en el propio ADR.
- **Interfaces de puerto** → ADR-004. Obligatorias en salida, no en entrada.
- **Casos de uso** → ADR-004. Uno por problema, un solo método público, no se llaman
  entre sí; lo compartido baja al dominio.
- **DDD táctico** → ADR-004. Modelo rico en `collection`, ligero en `catalog`.
- **D2 · Límites de agregado y referencias entre contextos** → ADR-012. Raíces por
  contexto (`Card`, `CardPrint`, `CardSet`, `CollectionItem`, `Binder`, `PriceSnapshot`…),
  referencia entre agregados por id, escritura entre contextos por puerto de grano grueso
  y lectura por proyección SQL. `shared` solo admite lo que ningún contexto posee.

**Abiertas:** ninguna que bloquee el siguiente paso. Quedan `card_images` y
`card_limitations` dentro de `Card` como decisión provisional (revisar en el paso 5).

---

## Plan de trabajo del backend

Cada paso tiene criterio de terminado. Nada se da por hecho sin él.

### 0. Cerrar D2 · ✅ terminado
Terminado cuando ADR-012 está escrito. Aceptado el 2026-09-19.

### 1. Convenciones de API (`docs/04-Diseno-de-API-Endpoints.md`) · ✅ terminado
No los 27 recursos: solo lo que se decide una vez y para siempre.

- Paginación y ordenación.
- Formato de errores (RFC 9457 Problem Details) y mapeo de violaciones de restricción
  a respuestas HTTP. La unicidad de hueco y los `CHECK` van a saltar, y no pueden
  llegar al cliente como un 500.
- Representación de dinero (`NUMERIC` → `BigDecimal` + moneda), fechas y nombres de
  enums en JSON.
- **Parámetro `owned` en todo endpoint de listado**, por defecto `true` (póliza de B4).

El contrato de cada recurso se documenta con su corte vertical, con OpenAPI generado
desde el código.

Terminado cuando el documento existe y no hay que volver a discutir estas cinco cosas.
Las cinco están cerradas: envoltorio `{metadata,data}`, `owned`, paginación/orden,
**errores (RFC 9457, con catálogo de mensajes en BD — decisión de aprendizaje, no
necesidad del proyecto)** y dinero/fechas/enums.

### 2. Esqueleto hexagonal
Paquetes `com.duelvault.{catalog,collection,pricing,scanning,security,shared}`, cada
uno con `domain/ · application/{usecase,port/{in,out}} · infrastructure/{in/web,out/jpa}`.
Se añade `spring-boot-starter-data-jpa` aquí (ADR-011).

Terminado cuando compila con los paquetes vacíos y hay un test de **ArchUnit** que
falla si `domain` importa Spring o JPA. Ese test es la prueba de que la hexagonal no
es de mentira.

Decidido el 2026-09-20: la infraestructura transversal (handler RFC 9457, envoltorio
`{metadata,data}`, paginación, adaptador de `error_catalog`) va en
`shared/infrastructure/{in/web,out/...}`. Mismo criterio de admisión que el ADR-012 §4:
ningún contexto es su dueño. Cada paquete lleva un `package-info.java` con su propósito.

Y una segunda regla de ArchUnit (ADR-012): el dominio de un contexto solo puede importar
del dominio de otro los **tipos de identidad** (`CardPrintId`, `CardId`…), nada más.

### 3. Testcontainers desde el primer día
Base de pruebas de integración contra PostgreSQL 16 real con las migraciones aplicadas.

Primer contenido: **los trece casos de `07-Casos-limite` convertidos en tests**. Ya se
ejecutaron a mano y encontraron defectos reales; automatizarlos cuesta poco y da la
evidencia del capítulo de pruebas.

Añadir los dos que salieron al revisar el `V1`: un Xyz con Nivel y un Enlace sin Link
Rating deben rechazarse.

Terminado cuando `./mvnw verify` levanta el contenedor, aplica V1/V2 y pasa las quince.

### 4. Migración de las 4.533 filas históricas
Es ETL contra SQL y no depende del backend. En cuanto está hecha, todo lo demás se
desarrolla contra datos reales: se puede medir si el índice de trigramas cumple, ver
una carpeta con huecos ocupados y descubrir el siguiente caso límite.

Los nueve pasos están en `03-Modelo-de-datos §5`. Tres reglas que no estaban ahí y que
el esquema ahora exige:

- **Si el marco es XYZ, el valor de `nivel` va a `xyz_rank`, no a `level`.** En el
  dataset comparten columna. Igual con `numLink` → `link_rating`.
- Las carpetas se crean desde el ETL. El `V3` que las creaba a partir de
  `binder_number` se fue al aplastar el esquema, así que ese trabajo ya no tiene
  respaldo en SQL.
- Cara y `slot_number` quedan a NULL hasta que se asignen los huecos.

Rehacer desde cero con `docker compose down -v` mientras se afina.

Terminado cuando la carga corre entera y produce **las cifras**: cuántas filas se
normalizaron por cada regla y cuántas quedaron en cuarentena. Eso cierra también el
ADR-006.

### 5. Corte vertical 1 — catálogo en lectura
`GET /cards`, `GET /cards/{id}` con la especialización por clase. Público, sin auth.
Extremo a extremo: dominio, caso de uso, puerto, adaptador, controlador, test.

Terminado cuando la ficha completa de un monstruo, una mágica y una trampa sale por
HTTP con datos migrados de verdad.

### 6. Corte vertical 2 — buscador
Los tres modos: nombre, texto literal y concepto. Con `@Query(nativeQuery = true)`,
nunca Criteria (ADR-011).

Terminado cuando `mago` encuentra "Fantastimago", `invocar cementerio` encuentra
*Renacimiento del Monstruo* y hay un `EXPLAIN ANALYZE` que demuestra que los índices
GIN se usan. Esa medición va a la memoria, y es la que activa o no el disparador de
`JdbcClient`.

### 7. Seguridad
Cierra el **ADR-003**, hoy en estado `Propuesta`. La pregunta que lo desbloquea es si
el frontend se sirve desde el mismo origen que la API.

Terminado cuando un anónimo recibe 401/403 en un endpoint de admin, nunca 500 ni datos
parciales.

### 8. Corte vertical 3 — colección
CRUD de `collection_items`, ubicación física y las dos operaciones que no son CRUD:

- **Recolocar cartas**: abre transacción y hace `SET CONSTRAINTS ... DEFERRED`. Único
  punto donde el límite transaccional importa, y por eso lleva test propio. Ojo: con
  Hibernate el orden de vaciado no está bajo control, así que si da guerra es el
  primer candidato a bajar a `JdbcClient`.
- **Partir una fila** (B1): hace falta para vender copias sueltas y para archivar dos
  copias en huecos distintos. Es comportamiento del agregado, no un caso de uso.

Más la validación que la base de datos no hace: que el hueco quepa en el
`slots_per_face` real de esa carpeta, con mensaje útil.

Y la comprobación previa al borrado de una carta o un set con ejemplares, para que el
error no venga de una tabla que el usuario no ha tocado.

**`price_snapshots` empieza a escribirse aquí, no en el paso 11.** El caso de uso
`RegistrarEjemplar` (alta de ejemplar) registra también el precio de mercado del
momento — el propietario lo comprueba siempre al dar de alta, sea o no la primera
copia. Escribe en `pricing` a través de un puerto de salida, mismo patrón de
referencia por id que `CollectionItem→CardPrintId`. El paso 11 sigue siendo cuándo se
construye la pantalla de Estadísticas; el dato nace antes.

### 9. Auditoría
**Antes de empezar**: `./mvnw dependency:tree` para ver qué Hibernate fija Spring Boot
4.1.1. Si es 7.4 o superior, valorar el soporte nativo de tablas de auditoría frente al
módulo Envers; si se cambia de rumbo, escribir un ADR que sustituya al 010.

En cualquier caso, el DDL de las tablas `_AUD` se escribe a mano en su migración.
Selectivo: `collection_items`, `cards`, `card_prints`, `binders`.

### 10. CI y compose completo
GitHub Actions con build y tests en cada push. Servicios `backend` y `frontend` en
`docker-compose.yml`.

### 11. Estadísticas y precios
La tabla `price_snapshots` ya se está poblando desde el paso 8 (alta de ejemplar);
este paso es la pantalla — cifras destacadas, gráfica de evolución (valor de lo que
se posee *hoy*, valorado con el precio de cada fecha, no cartera histórica exacta),
composición y top de cartas más valiosas. Con el "87 cartas pendientes de valorar" de
B2, que evita que el total mienta por omisión.

---

## Regla transversal: un ADR por decisión, escrita en el momento

`docs/ADRs/` tiene doce. **Un ADR no se edita**: si la decisión cambia, se escribe uno
nuevo que lo sustituye. Cada fase se cierra con el suyo antes de pasar a la siguiente.

Dos están en estado `Propuesta` a propósito, porque la decisión no se ha tomado:
**003** (autenticación, se cierra en el paso 7) y **006** (los 151 duplicados del
dataset, se cierra en el paso 4).

---

## Último trabajo hecho

- **2026-09-19** — **ADR-012** aceptado (`docs/ADRs/ADR-012-limites-de-agregado-y-referencias-entre-contextos.md`):
  raíces de agregado por contexto, referencia por id, puerto de grano grueso para
  escritura entre contextos (`RegistrarEjemplar`) y proyección SQL para lectura en las dos
  direcciones. Contrastado con las diez pantallas (`docs/05`, `docs/06`). Paso 0 del plan
  de trabajo, terminado. Desbloquea el paso 2.
- **2026-09-15** — `docs/04-Diseno-de-API-Endpoints.md §4` cerrado: formato de
  errores RFC 9457 (top-level, `application/problem+json`), mapeo de status
  (400/401-403 reservado/404/409/422/500), jerarquía de excepciones en
  `shared.domain` (`TipoDeError`: `tipo()`+`argumentos()`), traducción de
  `CHECK`/`UNIQUE` en el adaptador JPA, y catálogo de mensajes en BD
  (`error_catalog`, caché+fallback+auditoría) como decisión deliberada de
  aprendizaje. Paso 1 del plan de trabajo del backend, terminado. Commit
  `04bacc1`.
- **2026-09-14** — `V1__init_schema.sql` revisado antes del primer despliegue: el
  esquema se declara en el propio fichero en vez de heredarlo de Flyway, se cierran los
  dos `CHECK` que faltaban (un Xyz sin Rango y un Enlace sin Link Rating se colaban),
  se documenta la cadena de borrado carta/set → impresión → ejemplar, y
  `binder_summary` separa `card_count` de `placed_count`. Verificado ejecutándolo
  contra PostgreSQL 16 real: 27 tablas, sin errores.
- **2026-09-14** — `docs/ADRs/` con los once ADR y su índice.
- `9e5a2d9` — schema v1 (`V1__init_schema.sql`) + `V2__reference_data.sql`.
- `049a139` — esqueleto backend inicial: `pom.xml` (Spring Boot 4.1.1, Java 25,
  `spring-boot-starter-jdbc` + Flyway + Postgres driver), `application.yaml`,
  `docker-compose.yml` (solo `db`), migraciones V1/V2.
- `.claude/settings.json` — hook `PostToolUse` tras `git push`.

## Estado real del código

- Solo existe `BackendApplication.java`. **No hay paquetes hexagonales, ni dominio, ni
  adaptadores todavía.**
- `docker-compose.yml` solo levanta Postgres 16. Backend y frontend no están en compose.
- Migraciones Flyway (V1 + V2) escritas y aplicando con `./mvnw spring-boot:run`.
- Sin tests de ninguna clase. Sin CI.
- `docs/` no tiene todavía documento de diseño de API (`04-...`).

## Deuda de documentación pendiente

Pequeña, pero se olvida:

- **Sets: alta y consulta.** Decidido el 2026-09-19 y contratos en `docs/05` (sección
  "Sets"): `POST /card-sets` con el caso de uso `RegistrarSet` (paso 8) y
  `GET /card-sets` con `owned` (paso 5). Pantalla 11 (Sets: listado con interruptor
  «Mis sets / Todos» y alta) añadida a `docs/02`; el atajo «+ Crear set» del formulario
  de alta se mantiene. Falta dibujar en `docs/06` esa pantalla y el atajo, y el selector
  con búsqueda del filtro `cardSet[]` del buscador (decidido: selector, no lista con
  recuentos).
- Añadir a `07-Casos-limite` el caso **A12**: borrar una carta o un set de los que se
  poseen ejemplares falla con un mensaje que habla de `collection_items`.
- `07-Casos-limite §D` todavía dice que las filas legadas sin hueco se aceptan *"porque
  el índice es parcial"*. Desde la corrección de A11 no hay índice parcial: el motivo
  es que los nulos no se consideran iguales entre sí.
- `07-Casos-limite` dice que las **cuatro** migraciones de diseño se conservan en el
  anexo, y solo están las dos deltas (V3 y V4). Ajustar la frase o guardar las otras.
- El `LEEME.md` del anexo dice que esos ficheros **no** van al repositorio, y la ruta
  que usa el proyecto está dentro de él. Decidir una: dentro conserva el versionado de
  una evidencia que se va a citar en la memoria.

## Notas

- Nunca `ddl-auto: update`; todo pasa por Flyway. Una migración aplicada no se edita
  (el `V1` se revisó en sitio porque no hay ninguna base desplegada; a partir del
  primer despliegue, cada cambio es una migración nueva).
- Jaime programa todo el código; Claude Code es para revisión y dudas — ver `CLAUDE.md`.
- Java 25 y Spring Boot 4.1.1 van por delante de la documentación publicada. Vigilar
  Hibernate en el paso 9 y, más tarde, Tess4j y los bindings de OpenCV.
- Los casos de la sección C de `07-Casos-limite` (estados vacíos, JWT que caduca, dos
  pestañas editando) alimentan el frontend, no el backend. Siguen abiertos.
