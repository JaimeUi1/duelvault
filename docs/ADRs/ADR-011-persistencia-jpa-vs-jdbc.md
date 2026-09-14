---
tags: [tfg, adr, arquitectura, persistencia, jpa, jdbc]
adr: 011
estado: "Aceptada"
fecha: 2026-09-14
depende-de: ["[[03-Modelo-de-datos]]", "[[ADR-004-arquitectura-hexagonal]]"]
afecta-a: ["[[ADR-010-auditoria-con-envers]]"]
---

# ADR-011 · Estrategia de persistencia: JPA con JdbcClient reservado para proyecciones

## Contexto

El esqueleto del backend arrancó con `spring-boot-starter-jdbc` y sin `data-jpa`, sin que
la decisión estuviera tomada. Hay que cerrarla antes de escribir el primer puerto de
salida, porque define el adaptador entero.

Cuatro condicionantes propios del proyecto:

**El esquema es lo primero, y no lo genera nadie.** Las 27 tablas están diseñadas a mano,
versionadas con Flyway y validadas contra PostgreSQL 16. No hay `ddl-auto` ni lo va a
haber. Cualquier herramienta que asuma que el esquema se deriva del modelo Java sobra.

**El grafo de lectura es rico.** Una ficha de carta cruza `cards`, su especialización 1:1
según la clase, `card_translations`, arquetipos N:M, categorías de efecto jerárquicas y
las flechas de enlace. Mapear eso a mano es mucho `RowMapper`.

**El buscador no es un CRUD.** Son tres modos con distinto índice y distinta cláusula de
orden: trigramas con `immutable_unaccent(...) ILIKE ...` para nombre y texto literal, y
`search_vector @@ websearch_to_tsquery('spanish_unaccent', strip_enclitics(:q))` con
`ts_rank` para el modo por concepto. Encima, ocho facetas opcionales, paginación y el
parámetro `owned`. Nada de eso es expresable en JPQL.

**El ADR-010 comprometió Hibernate Envers**, que no existe sin Hibernate.

## Decisión

**JPA (Spring Data JPA + Hibernate) como adaptador de persistencia principal**, con
`JdbcClient` reservado para las proyecciones de solo lectura *si el buscador lo justifica*.

El corte no es escritura contra lectura: es **agregado contra proyección**.

| Vía | Casos |
|---|---|
| JPA, devuelve dominio | ficha de carta, alta y edición, archivar, recolocar, partir fila, vender, CRUD de carpetas |
| SQL nativo, devuelve proyección | buscador (los tres modos), `binder_summary` de la estantería, estadísticas, evolución del valor |

La regla: **si el resultado se va a modificar o tiene que respetar invariantes, repositorio
JPA que devuelve dominio; si son datos de pantalla que nadie va a tocar, SQL nativo a un
`record`.**

`JdbcClient` **no se añade hoy.** El buscador se implementa primero con `@Query(nativeQuery
= true)`, que ya permite el SQL específico de PostgreSQL. El disparador para pasarlo a
`JdbcClient` está escrito abajo, en Consecuencias.

## Alternativas

**Solo JDBC (`JdbcClient` a pelo).** Control total, SQL a la vista, sin magia, y encaja de
forma natural con un esquema diseñado a mano. Descartada por el volumen de mapeo manual
sobre 27 tablas y por perder el bloqueo optimista, que hace falta para el caso C de
`07-Casos-limite` (dos pestañas editando la misma carta).

**Spring Data JDBC.** Conceptualmente es el que mejor encaja con la hexagonal: agregados
de DDD, sin carga perezosa, sin contexto de persistencia, sin `@Entity` gestionadas. Tiene
`@Version`. Descartada por ecosistema pequeño, por no tener Envers y porque los límites de
agregado son estrictos (se carga el agregado entero o nada). No compensa el riesgo en un
proyecto con plazo.

**jOOQ.** Técnicamente la mejor opción para el buscador: SQL con tipos comprobados en
compilación, generado desde el esquema real, compone dinámicamente y soporta las funciones
propias. Con PostgreSQL la licencia es libre. Descartada por el paso de generación de
código en el build y por ser una herramienta más que aprender en un proyecto que ya tiene
varios frentes abiertos. Es la alternativa a reconsiderar si el buscador se complica más
de lo previsto.

**Criteria API / Specifications para el buscador.** Es la respuesta por defecto a "filtros
dinámicos en Spring". Descartada por una limitación concreta: no conoce
`immutable_unaccent`, `strip_enclitics` ni los operadores de texto completo, así que
obligaría a incrustar SQL crudo dentro del árbol de predicados. Y no serviría igualmente
para los tres modos, que no son el mismo `WHERE` con una condición distinta.

**`@Query` nativo con el patrón `(:x IS NULL OR col = :x)` repetido por faceta.** Deja un
único plan para todas las combinaciones, preparado para el caso peor, y arruina el uso de
los índices GIN. Medido en `03-Modelo-de-datos`: 18,9 ms de recorrido secuencial frente a
0,23 ms con índice. Es el motivo por el que existe el disparador hacia `JdbcClient`.

## Consecuencias

**A favor**

- El mapeo del grafo lo hace Hibernate, y el bloqueo optimista con `@Version` sale casi
  gratis.
- Es lo que el mercado usa por defecto, lo cual importa en un proyecto que también es
  portfolio.
- Mantiene vivo el ADR-010.
- Hoy hay un único modelo de transacción y una dependencia menos que mantener.

**En contra, y asumido**

- El SQL es opaco y el N+1 aparece solo. Se vigila con `spring.jpa.show-sql` en desarrollo
  y con `EXPLAIN ANALYZE` sobre las consultas del buscador.
- Obliga a mapper explícito entre `@Entity` e entidad de dominio, en los dos sentidos. Es
  trabajo aburrido y es innegociable: el atajo de usar la `@Entity` como modelo de dominio
  es la "hexagonal de mentira".
- **Hibernate decide cuándo salen las sentencias**, no el código. En el caso de uso de
  recolocar cartas, que abre transacción y hace `SET CONSTRAINTS ... DEFERRED`, eso
  significa que el orden de vaciado no está bajo control. Necesita test de integración
  propio, y si diera problemas, es el primer candidato a bajar a `JdbcClient`.

**Disparador para introducir `JdbcClient`**

Se añade el paquete `infrastructure/out/jdbc` cuando se cumpla cualquiera de estas dos:

1. El buscador con facetas opcionales deja de ser mantenible como cadena fija, o un
   `EXPLAIN ANALYZE` demuestra que los índices GIN no se están usando.
2. Una proyección de pantalla (estantería, estadísticas) resulta forzada de expresar como
   entidad.

No es indecisión: es aplazar una decisión hasta tener la información para tomarla, dejando
el camino abierto a propósito. El coste de añadirlo después es bajo porque `JdbcClient` se
construye sobre el mismo `DataSource`, participa en la misma transacción de Spring y no
necesita configuración nueva.

**Tres medidas que se toman desde ahora para que ese coste siga siendo bajo**

- El paquete `infrastructure/out/jdbc` queda previsto en `CLAUDE.md` aunque esté vacío, para
  que el día que aparezca no parezca una violación de la arquitectura.
- Las consultas de pantalla devuelven `record` de proyección desde el primer día, aunque se
  escriban con JPA. Si el buscador ya devuelve un DTO, cambiar la implementación no se nota
  fuera del adaptador.
- Las lecturas van en su propia transacción con `@Transactional(readOnly = true)` y no se
  mezclan con escrituras. Esto evita de raíz el problema de coherencia entre las dos vías:
  `JdbcClient` es invisible para Hibernate, así que dentro de una misma transacción no
  vería los cambios que Hibernate aún no ha vaciado (y al revés, un `UPDATE` por
  `JdbcClient` sobre filas que Hibernate tiene cargadas puede acabar sobrescrito al hacer
  flush).

**Efecto sobre el ADR-010**

Hibernate 7.4 incorporó el soporte de tablas de auditoría al propio ORM: se activa con
`@Audited` y admite tabla propia con `@Audited.Table`, sin añadir el módulo Envers para ese
caso. Envers sigue publicándose y mantenido, así que ninguna de las dos vías es un callejón
sin salida. Antes de implementar la auditoría hay que comprobar qué versión de Hibernate fija
Spring Boot 4.1.1 (`./mvnw dependency:tree`) y, si es 7.4 o superior, revisar el ADR-010 con
un ADR posterior en lugar de editarlo.

En cualquiera de los dos casos, el DDL de las tablas `_AUD` se escribe a mano en su propia
migración Flyway. Y la auditoría sigue siendo selectiva: `collection_items`, `cards`,
`card_prints` y `binders`, nunca los catálogos ni `price_snapshots`, que ya es un histórico
por diseño.

**Lo que esto habilita para la memoria**

Un apartado que justifica el rechazo de la opción por defecto (Criteria) con una limitación
técnica concreta y medida, en vez de por preferencia. Y, si el disparador llega a activarse,
dos adaptadores de tecnologías distintas detrás del mismo puerto: la demostración práctica
de para qué sirve la hexagonal, en lugar de la explicación teórica.
