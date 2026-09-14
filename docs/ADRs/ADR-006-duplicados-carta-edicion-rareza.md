---
tags: [tfg, adr, modelo-datos, migracion]
adr: 006
estado: "Propuesta"
fecha-decision: null
abierto-desde: 2026-09-14
depende-de: "[[ADR-002-separar-carta-impresion-ejemplar]]"
---

# ADR-006 · Qué son los 151 duplicados de carta + número de set + rareza

> **Estado: Propuesta.** No hay decisión porque falta información que solo puede dar una
> revisión manual del dataset. Se cierra durante la fase de migración.

## Contexto

En el volcado histórico, **151 combinaciones de carta + código de set + rareza aparecen en
más de una fila**. El modelo nuevo obliga a decidir qué significan, porque cada opción
produce un recuento distinto de la colección.

El problema es que hoy no se sabe si son:

- **Lotes de compra distintos.** Dos ejemplares comprados en momentos y a precios
  distintos, registrados por separado a propósito. En ese caso son dos ejemplares
  legítimos y fusionarlos destruiría información.
- **Ruido de carga.** La misma carta metida dos veces por error durante años de registro
  manual. En ese caso son un solo ejemplar y contarlos dobla el tamaño real de la
  colección.
- **Una mezcla de ambas cosas**, que es lo más probable.

Hay un dato que empuja hacia la primera lectura y otro hacia la segunda. A favor de los
lotes: el campo `precio` puede diferir entre las dos filas. En contra: el dataset **no
registra fecha de compra** en ningún sitio (`fechaUpdate` es fecha de alta o de última
consulta de precio), así que aunque fueran lotes distintos, el dato que los justificaría
no existe.

## Opciones sobre la mesa

**Fusionar sumando copias.** Una sola fila con `quantity` acumulada. Simple, y coherente
con que la ubicación física sea de un solo ejemplar. Pierde el precio distinto de cada
fila.

**Conservar como filas separadas.** Cada una es un `collection_item` con su propio
`purchase_price`. Es lo que el modelo ya permite, y es coherente con la decisión de B1 de
que cada venta sea una fila. Riesgo: si en realidad son ruido, la colección declara más
ejemplares de los que existen.

**Cuarentena y revisión manual.** Cargarlos en una tabla aparte, no contarlos, y decidir
caso por caso. Es lo más honesto y lo más caro.

## Lo que falta por saber

1. Revisar a mano una muestra de 20 duplicados y ver si el precio, la página o la carpeta
   difieren entre las filas. Si difieren sistemáticamente, son lotes; si son idénticas, es
   ruido.
2. Contrastar con el recuento físico de al menos una carpeta: si la aplicación dice 400
   cartas y en la estantería hay 380, la respuesta está clara.

## Consecuencia transversal

Sea cual sea la decisión, la migración debe **reportar la cifra**: cuántas filas se
fusionaron, cuántas se conservaron y cuántas quedaron en cuarentena. Ese número forma
parte del capítulo de migración de la memoria, y sin él la carga no es reproducible ni
auditable.

Mientras tanto, el paso 7 del plan de migración carga **un `collection_item` por fila
original, sin fusionar nada**. Es la opción reversible: fusionar después es posible,
recuperar lo fusionado no.
