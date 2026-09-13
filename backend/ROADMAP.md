# Roadmap — DuelVault backend

Guía de estado para retomar el trabajo. Se actualiza a mano cuando cambia la fase.

## Fases del TFG

- [x] Discovery
- [x] Diseño de datos y pantallas (`docs/00`, `docs/02`, `docs/03`, `docs/07`, `docs/perfil-dataset.md`)
- [ ] **Diseño de API REST ← estamos aquí**
- [ ] Setup (esqueleto hexagonal, Angular, Docker Compose completo)
- [ ] Backend (dominio + adaptadores)
- [ ] Migración de las 4.533 filas históricas
- [ ] Frontend (Angular)
- [ ] Estadísticas
- [ ] Escaneo por cámara (OCR passcode, OpenCV + Tesseract) — post-MVP
- [ ] Testing
- [ ] Memoria y demo

## Último trabajo hecho

- `9e5a2d9` — schema v1 actualizado (`V1__init_schema.sql`, 27 tablas creadas) + `V2__reference_data.sql` con datos de referencia.
- `049a139` — esqueleto backend inicial: `pom.xml` (Spring Boot 4.1.1, Java 25, `spring-boot-starter-jdbc` + Flyway + Postgres driver, sin `data-jpa` aún), `application.yaml` con datasource/Flyway, `docker-compose.yml` (solo servicio `db`), migraciones V1/V2.
- `.claude/settings.json` — hook `PostToolUse` tras `git push`: analiza el commit y sugiere si algo merece nota en Obsidian.

## Estado real del código

- Solo existe `BackendApplication.java`. **No hay paquetes hexagonales, ni dominio, ni adaptadores todavía.**
- `docker-compose.yml` solo levanta Postgres 16 (`db`). Backend y frontend no están en compose.
- Migraciones Flyway (V1 init schema + V2 reference data) sí están escritas y aplican corriendo `./mvnw spring-boot:run`.
- `docs/` no tiene todavía un documento de diseño de API REST (no existe `01-...`), que es la fase siguiente según el roadmap general.

## Qué queda inmediatamente después de "Diseño de API REST"

1. Diseñar los endpoints REST (recursos: cards, monster/spell/trap_cards, card_prints, collection_items; fase 2: price_snapshots) y documentarlo en `docs/`.
2. Crear el esqueleto hexagonal: paquetes `com.duelvault.{catalog,collection,pricing,scanning,security,shared}` con `domain/ · application/{usecase,port/{in,out}} · infrastructure/{in/web,out/jpa}`.
3. Añadir `spring-boot-starter-data-jpa` cuando toque la capa de persistencia (entidades JPA solo en `infrastructure/out/jpa`, con mapper a dominio).
4. Añadir servicio `backend` y `frontend` a `docker-compose.yml`.
5. Arrancar Angular (frontend aún sin empezar).
6. Migrar las 4.533 filas del dataset histórico a las tablas nuevas.

## Notas

- Nunca `ddl-auto: update`; todo pasa por Flyway. Migración aplicada no se edita — recrear con `docker compose down -v` en desarrollo.
- Jaime programa todo el código; Claude Code es para revisión y dudas — ver `CLAUDE.md`.
