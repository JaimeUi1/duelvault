---
tags: [tfg, portfolio, proyecto, yugioh, fullstack, arquitectura-hexagonal]
estado: "Diseño cerrado — pendiente de implementación"
tipo: "Trabajo de Fin de Grado (Ingeniería Informática) + proyecto de portfolio"
stack: "Java + Spring Boot (backend, arquitectura hexagonal) + Angular (frontend) + PostgreSQL"
lienzo-diseno: "https://claude.ai/code/artifact/0dad5f4c-3aa6-4854-8234-db419690af46"
---

# DuelVault — Catálogo de mi colección de Yu-Gi-Oh!

Esta nota es la portada del proyecto: la que iría en el README de GitHub, en el índice de la memoria del TFG y en el índice de este vault. El resto de fases cuelgan de aquí como notas enlazadas.

> **Contexto académico:** se presenta como **Trabajo de Fin de Grado de Ingeniería Informática**, no solo como pieza de portfolio. Todavía sin tutor ni plantilla oficial asignada — se documenta con la estructura de este vault, pendiente de ajustar si la universidad pide otro formato. En cuanto haya tutor, conviene validar con él el alcance, y en particular el diferenciador del punto 4.

> **Metodología de trabajo:** Jaime programa todo el código, backend y frontend. Claude Code se usa para revisión de código y dudas de implementación; este vault y el Proyecto de Claude son la base de conocimiento de diseño y arquitectura. Si la universidad exige declarar el uso de herramientas de IA, dejar constancia en la memoria.

## 1. Resumen

> **DuelVault** es una aplicación web fullstack para catalogar, consultar y valorar una colección personal de cartas de Yu-Gi-Oh!, con una API REST en Java/Spring Boot sobre arquitectura hexagonal y un frontend en Angular. Muestra la ficha detallada de cada carta al estilo de una wiki, pero añade lo que una wiki no puede: qué copias posees, de qué rareza y edición, en qué carpeta y página están archivadas, qué pagaste por ellas y cuánto valen hoy.

El nombre combina *Duel*, término oficial con el que el juego denomina sus partidas, y *Vault*, que evoca el almacenamiento seguro y duradero de una colección de valor.

## 2. Motivación

- Es un problema real y personal: organizar una colección de más de 7.000 cartas repartidas en carpetas físicas.
- El dominio da pie a un modelo de datos genuinamente complejo (clases de carta con atributos distintos, ediciones, rarezas, arte alternativo, restricciones por formato), ideal para demostrar diseño de base de datos.
- Cubre de forma natural CRUD, autenticación, agregaciones, búsqueda sobre miles de registros y un componente técnico propio — es decir, lo que se pide en una prueba técnica fullstack y lo que espera ver un tribunal.

## 3. Objetivos

- **Académico:** cumplir los requisitos de un TFG — análisis, diseño, implementación, pruebas y documentación de un sistema completo, con al menos un componente técnico que vaya más allá de un CRUD.
- **Principal:** demostrar perfil **fullstack** con buenas prácticas de arquitectura, documentado de principio a fin.
- **Secundario:** tener una herramienta real y usable para llevar la colección.

## 4. Alcance funcional

### MVP (fase 1)
- Catálogo de cartas con ficha de detalle completa, con los campos que correspondan a cada clase de carta.
- CRUD de la colección: qué cartas posees, rareza, edición, idioma, estado de conservación, precio pagado y ubicación física (carpeta, página, hueco).
- Autenticación de administrador + vista pública de solo lectura sin login.
- Búsqueda por texto e índice alfabético, con filtros por tipo, atributo, tipo de monstruo, nivel, arquetipo, rareza, set e idioma.

### Fase 2 — estadísticas y valor
- Composición de la colección y valor total.
- Evolución del valor en el tiempo, a partir del histórico de precios.

### Fase 3 — diferenciador: escaneo de cartas por cámara
- Apuntar con la cámara del móvil a una carta física, leer por OCR su passcode de 8 dígitos y proponer la carta detectada para autorrellenar el formulario de alta.
- Pipeline: captura → corrección de perspectiva y preprocesado (OpenCV) → recorte de la región del passcode → OCR (Tesseract/Tess4j) → búsqueda en el catálogo → sugerencia editable.
- Diseñada por su caso peor: confianza baja, dígito dudoso, varias candidatas y salida manual siempre visible.
- Es una mejora **posterior al MVP**: si se complica, el proyecto sigue siendo entregable sin ella.

### Fuera de alcance
- Módulo de tienda / e-commerce. La colección conserva solo un estado informativo: POSEÍDA / EN VENTA / VENDIDA.
- Plataforma multiusuario donde terceros registren su propia colección.
- Reconocimiento de la carta por su ilustración completa — descartado en favor del OCR del passcode.
- Aplicación nativa: el móvil es web responsive, y el escaneo funciona desde el navegador con `getUserMedia` (exige HTTPS en el despliegue).

## 5. Stack tecnológico

| Capa | Tecnología | Notas |
|---|---|---|
| Backend | Java + Spring Boot | **Arquitectura hexagonal**: dominio aislado de Spring y JPA |
| Frontend | Angular | Componentes standalone, guards de rutas admin, interceptor de JWT |
| Base de datos | **PostgreSQL** | Migraciones versionadas con Flyway |
| Auditoría | Hibernate Envers | Selectiva: solo entidades que cambian y que importan |
| Visión / OCR | OpenCV + Tesseract (Tess4j) | Solo para el escaneo de la fase 3 |
| Documentación API | OpenAPI / Swagger | Generada desde el código |
| Seguridad | Spring Security + JWT | Administrador único; la vista pública es anónima |
| Contenedores | Docker Compose | Backend, frontend y base de datos con un comando |
| CI | GitHub Actions | Build y tests en cada push |
| Testing | JUnit + Mockito, Jasmine/Karma o Jest | El dominio se testea sin levantar Spring |

### Por qué PostgreSQL y no MySQL

Tipos de datos más ricos para el dominio (JSONB con índices, arrays, enums nativos), búsqueda por subcadena acelerada con índices de trigramas (`pg_trgm`) e insensible a acentos (`unaccent`) sin montar un motor de búsqueda aparte, restricciones diferibles y `CHECK` expresivos. MySQL habría sido válido, pero sin ventajas que compensaran.

## 6. Arquitectura

El backend sigue **arquitectura hexagonal**: el dominio (entidades y reglas de negocio) no depende de Spring ni de JPA, y se comunica con el exterior mediante puertos (interfaces) que implementan los adaptadores.

```
                    [Angular SPA]
                         |
                     HTTP/JSON
                         v
        ┌─────────────────────────────────┐
        │   Adaptadores de entrada         │  Controladores REST
        ├─────────────────────────────────┤
        │   Aplicación (casos de uso)      │  Puertos de entrada
        ├─────────────────────────────────┤
        │   Dominio                        │  Entidades y reglas puras,
        │   (sin Spring, sin JPA)          │  testeables sin contenedor
        ├─────────────────────────────────┤
        │   Adaptadores de salida          │  JPA/PostgreSQL, OCR,
        │   (implementan puertos)          │  seguridad, APIs externas
        └─────────────────────────────────┘
```

Un efecto colateral valioso: **la auditoría con Envers no ensucia el dominio**, porque se anota sobre las entidades JPA, que viven en infraestructura. La separación demuestra ahí su utilidad práctica.

Detalle y estructura de paquetes → `05-Arquitectura.md`.

## 7. Modelo de datos

27 tablas en PostgreSQL, validadas ejecutando las migraciones contra una base real. Estructura principal:

- **`cards`** — la carta canónica, identificada por su passcode oficial de 8 dígitos. Puede apuntar a otra carta como arte alternativo (Mago Oscuro / la versión de Arkana, que tiene passcode propio).
- **`monster_cards` / `spell_cards` / `trap_cards`** — especialización 1:1 según la clase, para no arrastrar campos vacíos.
- **`card_prints`** — cada impresión concreta: set, número, rareza, edición e idioma. La rareza forma parte de la clave, porque un mismo número de set se imprime en varias.
- **`collection_items`** — cada ejemplar poseído, con su ubicación física (carpeta, página, hueco), estado de conservación y precio pagado.
- **`binders`** — las carpetas de anillas, con nombre, color de lomo y huecos por página.
- **`price_snapshots`** — histórico de precios; sin él no hay gráfica de evolución.
- Además: traducciones por idioma, arquetipos, categorías de efecto jerárquicas, restricciones por formato e imágenes (que pueden colgar de una impresión concreta, porque una misma carta se reimprime con ilustraciones distintas bajo el mismo passcode).

La taxonomía (7 atributos, 26 Tipos de monstruo, marcos, habilidades, rarezas) está tomada de la base de datos oficial de Konami, no del dataset propio. Detalle completo, decisiones y plan de migración → `03-Modelo-de-datos.md`.

## 8. Diseño de pantallas

Diez pantallas diseñadas y aprobadas: estantería, carpeta abierta, detalle de carta, buscador, estadísticas, alta/edición, escaneo (captura y resultado dudoso), detalle en móvil y acceso admin. Dirección visual híbrida — entrada oscura y táctil, interior claro y legible — con el color por tipo de carta como ancla del sistema.

Lienzo: https://claude.ai/code/artifact/0dad5f4c-3aa6-4854-8234-db419690af46 · Detalle → `02-Diseno-de-pantallas.md` · Tokens → `duelvault-tokens.css`

## 9. Documentación del proceso

Estructura del vault:

```
📁 DuelVault-docs/
 ├─ 00-Descripcion-del-proyecto.md        (esta nota)
 ├─ 01-Requisitos-y-alcance.md            (historias de usuario, casos de uso)
 ├─ 02-Diseno-de-pantallas.md             ✅
 ├─ 03-Modelo-de-datos.md                 ✅
 ├─ 04-Diseno-de-API-Endpoints.md
 ├─ 05-Arquitectura.md
 ├─ 06-Seguridad.md
 ├─ 07-Testing.md
 ├─ 08-Despliegue-DevOps.md
 ├─ 09-Roadmap-Backlog.md
 ├─ 10-Retrospectiva.md
 ├─ perfil-dataset.md                     ✅
 └─ ADRs/
     ├─ ADR-001-eleccion-base-de-datos.md
     ├─ ADR-002-separar-carta-impresion-ejemplar.md
     ├─ ADR-003-estrategia-de-autenticacion.md
     ├─ ADR-004-arquitectura-hexagonal.md
     ├─ ADR-005-reconocimiento-cartas-por-camara.md
     ├─ ADR-006-duplicados-carta-edicion-rareza.md
     ├─ ADR-007-enum-vs-tabla-de-catalogo.md
     ├─ ADR-008-marco-y-habilidades-separados.md
     ├─ ADR-009-carpetas-como-entidad.md
     └─ ADR-010-auditoria-con-envers.md
```

**Sobre los ADR:** notas cortas con el formato *Contexto → Decisión → Alternativas → Consecuencias*. Es el artefacto que un tribunal reconoce como "esta persona piensa como ingeniero, no solo como programador".

## 10. Roadmap

1. **Discovery** — alcance y casos de uso. ✅
2. **Diseño** — modelo de datos y pantallas. ✅
3. **Diseño de API** — contrato REST entre modelo y pantallas. ← *siguiente*
4. **Setup** — esqueleto backend con paquetes hexagonales, esqueleto Angular, Docker Compose, migraciones.
5. **Backend** — dominio, casos de uso, adaptadores, autenticación.
6. **Migración de datos** — carga de las 4.533 filas históricas con su limpieza documentada.
7. **Frontend** — pantallas e integración con la API.
8. **Estadísticas y valor.**
9. **Escaneo por cámara** (diferenciador).
10. **Testing** — dominio sin Spring, integración, y evaluación empírica del reconocimiento.
11. **Memoria, despliegue y demo pública.**

## 11. Qué destacar

- **Migraciones versionadas** con Flyway desde el primer día, nunca `ddl-auto: update`.
- **Dominio realmente aislado** de Spring y JPA — el error más fácil es la "hexagonal de mentira" en la que las entidades JPA se usan como modelo de dominio.
- **Restricciones en la base de datos que atrapan errores reales**: los `CHECK` de rango habrían impedido las tres filas del dataset donde un valor de ATK acabó en la columna de nivel.
- **Evaluación empírica del escaneo** con fotos propias en distintas condiciones, reportando el porcentaje de aciertos. Una cifra real vale más que "funciona bien".
- **La migración de datos como capítulo propio**: 4.533 filas con erratas acumuladas durante años, con métricas de cuántas se normalizaron por cada regla.
- **README con capturas, diagrama y demo desplegada**, y un apartado honesto de qué se haría distinto con más tiempo.

---

*Última actualización: 2026-09-05*
