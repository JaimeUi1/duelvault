---
tags: [tfg, adr, auditoria, envers, hexagonal]
adr: 010
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
depende-de: ["[[ADR-004-arquitectura-hexagonal]]", "[[ADR-011-persistencia-jpa-vs-jdbc]]"]
---

# ADR-010 · Auditoría selectiva con Hibernate Envers

## Contexto

Una colección que se lleva durante años acumula cambios que interesa poder reconstruir:
cuándo se recolocó una carta, cuándo cambió de estado, qué precio de compra se corrigió.
Sin histórico, un error de edición es indistinguible de un dato correcto.

La restricción es que la auditoría **no debe tocar el dominio**. Anotar las entidades de
negocio con algo de infraestructura sería exactamente el tipo de contaminación que el
ADR-004 quiere evitar.

## Decisión

**Hibernate Envers, aplicado de forma selectiva.**

Encaja con la hexagonal sin ensuciarla porque **se anota sobre las entidades JPA, que
viven en `infrastructure/out/jpa`**. El dominio no se entera de que existe. Es, de hecho,
un buen ejemplo práctico de para qué sirve la separación.

**Selectiva** quiere decir cuatro tablas y solo cuatro:

| Se audita | No se audita |
|---|---|
| `collection_items` | Los catálogos (`rarities`, `monster_types`, `languages`...) |
| `cards` | `price_snapshots` |
| `card_prints` | Tablas de traducción |
| `binders` | |

`price_snapshots` queda fuera porque **ya es un histórico por diseño**: auditarlo sería
guardar el historial de un historial.

## Alternativas

**Disparadores de base de datos que escriban en tablas de histórico.** Funciona y es
independiente del ORM. Descartado porque mete comportamiento en la infraestructura fuera
del control de la aplicación, y porque el DDL de todos esos disparadores hay que
mantenerlo a mano.

**Auditar a mano desde los casos de uso**, escribiendo una fila de histórico en cada
operación. Es lo más explícito y lo más fácil de olvidar: basta con un caso de uso nuevo
que no lo haga.

**No auditar nada.** Defendible en un proyecto de un solo usuario. Se descarta porque el
coste es bajo y porque poder mostrar la evolución de un ejemplar es contenido para la
memoria.

## Consecuencias

**Tres cautelas que hay que conocer**

- **El DDL de las tablas `_AUD` hay que escribirlo a mano** en una migración Flyway. Las
  migraciones son versionadas y nunca se generan solas.
- **No audita lo que no pasa por Hibernate.** La carga inicial de las 4.533 filas se hace
  con SQL, así que queda fuera del histórico. Es correcto: la migración no es un cambio del
  usuario.
- Depende de que el adaptador de persistencia sea JPA. Está atado al ADR-011.

**Revisión pendiente antes de implementarlo**

Hibernate 7.4 incorporó el soporte de tablas de auditoría **al propio ORM**: se activa con
`@Audited` y admite tabla propia con `@Audited.Table`, sin necesidad de añadir el módulo
Envers para este caso de uso. Envers sigue publicándose y mantenido, así que ninguna de las
dos vías es un callejón sin salida.

Antes de escribir la migración de las tablas `_AUD` hay que comprobar qué versión de
Hibernate fija Spring Boot 4.1.1 (`./mvnw dependency:tree`). Si es 7.4 o superior, conviene
valorar el soporte nativo y, si se cambia de rumbo, **escribir un ADR posterior que
sustituya a este** en lugar de editarlo.
