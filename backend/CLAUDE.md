# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Qué es esto

`backend/` del TFG **DuelVault**: API REST para catalogar una colección real de
Yu-Gi-Oh! (4.533 filas históricas, 27 tablas). Monorepo: `backend/`, `frontend/`
(Angular, sin empezar), `db/`, `docs/` (diseño cerrado: modelo de datos + 10
pantallas).

**Estado real del backend hoy:** solo existe `BackendApplication.java`. Los
paquetes hexagonales, el esqueleto de dominio y los adaptadores están por crear.
El `pom.xml` trae `spring-boot-starter-jdbc` + Flyway, **no** `data-jpa` todavía;
las reglas sobre `@Entity` de abajo aplican cuando se añada esa capa.
`application.yaml` ya tiene datasource + Flyway configurados.

## Comandos

Wrapper Maven (`./mvnw` en bash, `mvnw.cmd` en PowerShell). Java 25, Spring Boot 4.1.1.

| Acción | Comando |
|---|---|
| Compilar + empaquetar | `./mvnw clean package` |
| Arrancar la app | `./mvnw spring-boot:run` |
| Todos los tests | `./mvnw test` |
| Un test | `./mvnw test -Dtest=NombreClase` |
| Un método | `./mvnw test -Dtest=NombreClase#nombreMetodo` |

No hay linter/formatter configurado. `./mvnw test` levanta contexto Spring
(`@SpringBootTest`), así que necesita PostgreSQL accesible o los tests de
integración fallan.

## Base de datos y migraciones

- PostgreSQL 16 vía `docker-compose.yml` en la raíz (solo el servicio `db` por
  ahora; backend y frontend se añadirán). `docker compose up -d` para arrancar.
  DB/user/pass = `duelvault` en desarrollo.
- Migraciones Flyway en `backend/src/main/resources/db/migration/` (`V1__init_schema.sql`,
  `V2__reference_data.sql`). `spring.flyway.locations = classpath:db/migration`.
- `db/migrations/anexo-migraciones-historicas/` (V3, V4) es material del proyecto
  anterior ("frontron"), no forma parte del esquema activo.
- Flyway siempre; **jamás `ddl-auto: update`**.
- Una migración aplicada no se edita. En desarrollo se recrea la base:
  `docker compose down -v`.

## Arquitectura hexagonal — reglas no negociables

Módulo por contexto, hexágono dentro de cada uno:
`com.duelvault.{catalog,collection,pricing,scanning,security,shared}`
y dentro `domain/ · application/{usecase,port/{in,out}} · infrastructure/{in/web,out/jpa}`.

- `domain/` no importa Spring, JPA ni ninguna librería de terceros. Se testea sin
  levantar contenedor.
- Las `@Entity` viven solo en `infrastructure/out/jpa`, con mapper explícito a los
  modelos de dominio. Nunca cruzan hacia application ni web.
- Los puertos los define el dominio por lo que necesita, no el adaptador por lo
  que ofrece Spring Data.
- Las reglas de negocio van en el dominio, nunca en disparadores de BBDD ni en el
  servicio de aplicación.
- El error a evitar es la "hexagonal de mentira": usar entidades JPA como modelo
  de dominio.

## Modelo de datos (resumen; detalle en `docs/03-Modelo-de-datos.md`)

Separación en tres niveles, clave del dominio:
- `cards` — carta canónica por passcode oficial de 8 dígitos; puede apuntar a otra
  como arte alternativo.
- `monster_cards` / `spell_cards` / `trap_cards` — especialización 1:1 por clase.
- `card_prints` — cada impresión: set, número, rareza, edición, idioma. La rareza
  es parte de la clave.
- `collection_items` — cada ejemplar poseído: ubicación física (carpeta, página,
  hueco), estado, precio pagado.
- `price_snapshots` — histórico de precios (fase 2).

La taxonomía (atributos, tipos de monstruo, marcos, rarezas) sale de la BD oficial
de Konami, no del dataset propio.

## Roadmap (dónde estamos)

Discovery ✅ · Diseño de datos y pantallas ✅ · **Diseño de API REST ← siguiente** ·
Setup (esqueleto hexagonal, Angular, Docker Compose) · Backend · Migración de las
4.533 filas · Frontend · Estadísticas · Escaneo por cámara (OCR del passcode con
OpenCV + Tesseract, diferenciador post-MVP) · Testing · Memoria y demo.

## Contexto académico

TFG de Ingeniería Informática. **Jaime programa todo el código**; Claude Code se
usa para revisión y dudas de implementación. `docs/` es la base de conocimiento de
diseño (incluye ADRs con formato Contexto → Decisión → Alternativas → Consecuencias).
