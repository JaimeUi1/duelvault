---
tags: [tfg, adr, indice]
---

# Registros de decisión de arquitectura (ADR)

Cada fichero recoge una decisión técnica con su porqué, en el formato
**Contexto → Decisión → Alternativas → Consecuencias**.

El código dice *qué* se hizo; estas notas dicen *por qué*, y sobre todo qué
alternativas se descartaron, que es lo que se pierde en cuanto pasan unos meses.

## Convención

- **Un ADR no se edita.** Si la decisión cambia, se escribe uno nuevo que lo
  sustituye y se marca el viejo como `Sustituida por ADR-0XX`. La cadena de
  decisiones es el valor.
- Los números no se reutilizan ni se reordenan, aunque haya huecos.
- Estados posibles en el `frontmatter`:

| Estado | Significado |
|---|---|
| `Propuesta` | El problema está identificado y las opciones planteadas; la decisión no está tomada |
| `Aceptada` | Decidida y vigente |
| `Sustituida por ADR-0XX` | Reemplazada por una decisión posterior |

- Los que llevan `redactado:` posterior a `fecha-decision:` se escribieron a
  posteriori, recuperando el razonamiento de los documentos de diseño. Se indica
  a propósito: la decisión es de esa fecha, la redacción no.

## Índice

| # | Decisión | Estado |
|---|---|---|
| [001](ADR-001-eleccion-base-de-datos.md) | PostgreSQL como base de datos | Aceptada |
| [002](ADR-002-separar-carta-impresion-ejemplar.md) | Tres niveles: carta, impresión y ejemplar | Aceptada |
| [003](ADR-003-estrategia-de-autenticacion.md) | Estrategia de autenticación | **Propuesta** |
| [004](ADR-004-arquitectura-hexagonal.md) | Arquitectura hexagonal por contexto | Aceptada |
| [005](ADR-005-reconocimiento-cartas-por-camara.md) | OCR del passcode para el escaneo | Aceptada |
| [006](ADR-006-duplicados-carta-edicion-rareza.md) | Qué son los 151 duplicados del dataset | **Propuesta** |
| [007](ADR-007-enum-vs-tabla-de-catalogo.md) | ENUM nativo para lo cerrado, tabla para lo abierto | Aceptada |
| [008](ADR-008-marco-y-habilidades-separados.md) | Marco y habilidades como dimensiones distintas | Aceptada |
| [009](ADR-009-carpetas-como-entidad.md) | Las carpetas son una entidad, no un número | Aceptada |
| [010](ADR-010-auditoria-con-envers.md) | Auditoría selectiva con Envers | Aceptada |
| [011](ADR-011-persistencia-jpa-vs-jdbc.md) | JPA, con JdbcClient reservado para proyecciones | Aceptada |

## Pendientes de escribir

Se abrirán cuando la decisión se tome, no antes:

- **ADR-012 · Límites de agregado y referencias entre contextos.** Qué es raíz de
  agregado y cómo referencia `collection` a `catalog`.
- **ADR-013 · Estrategia de despliegue.** Sale de la fase de DevOps.
