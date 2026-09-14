---
tags: [tfg, adr, modelo-datos]
adr: 002
estado: "Aceptada"
fecha-decision: 2026-09-05
redactado: 2026-09-14
depende-de: "[[ADR-001-eleccion-base-de-datos]]"
---

# ADR-002 · Tres niveles: carta, impresión y ejemplar

## Contexto

El dataset histórico es una única tabla MySQL `cartas` sin normalizar, con 4.533 filas.
Cada fila mezcla tres cosas distintas: los datos canónicos de la carta, los de su edición
concreta y los de la copia poseída.

La evidencia de que eso no da más de sí está en los propios datos:

- 4.533 filas contienen solo **3.363 cartas distintas** por passcode, y representan
  **7.004 copias** poseídas. Los tres números son diferentes porque miden tres cosas.
- **202 números de set aparecen con más de una rareza.** `RA01-SP057` existe en ultra,
  ultimate y quarter century secret. Son tres productos distintos con tres precios
  distintos, no tres veces la misma cosa.
- **33 passcodes tienen el nombre escrito de dos formas** distintas, porque el nombre se
  repetía en cada fila en vez de vivir en un solo sitio.
- El precio es una columna mutable con su `fechaUpdate`: sin histórico no hay gráfica de
  evolución del valor, que es un objetivo declarado del proyecto.

## Decisión

Tres niveles, con las claves que les corresponden:

1. **`cards`** — la carta canónica, identificada por su passcode oficial de 8 dígitos.
   Con su nombre y texto en `card_translations` (uno por idioma) y su especialización 1:1
   en `monster_cards` / `spell_cards` / `trap_cards`.
2. **`card_prints`** — cada impresión concreta: carta, set, número de set, **rareza**,
   edición e idioma. La rareza **forma parte de la clave única**, porque el mismo número
   de set se imprime en varias.
3. **`collection_items`** — cada ejemplar poseído: cantidad, estado de conservación,
   precio pagado, ubicación física y estado de venta.

El precio de mercado cuelga de la impresión, no de la carta, y como serie temporal en
`price_snapshots`.

## Alternativas

**Mantener la tabla plana y limpiarla.** Es lo que el dataset ya demostró que no
funciona: obliga a repetir el nombre y el texto de efecto en cada fila (de ahí las 33
discrepancias), impide distinguir "tengo tres copias" de "existe en tres rarezas", y no
tiene sitio donde poner un histórico de precios.

**Dos niveles: carta y ejemplar.** Guardar rareza y edición directamente en el ejemplar.
Es tentador porque hay menos joins, pero rompe en cuanto quieres el precio de mercado: el
precio es de la impresión, no del ejemplar concreto que tú tienes, y tampoco de la carta.
Con dos niveles hay que duplicar el precio en cada copia o inventarse dónde ponerlo.

**Modelo entidad-atributo-valor** para absorber las diferencias entre clases de carta.
Descartado: pierde toda la integridad de tipos y hace imposible ordenar o sumar por ATK,
que es justo lo que la pantalla de estadísticas necesita.

## Consecuencias

**A favor**

- La ficha de carta y la vista de colección son consultas distintas sobre datos distintos,
  que es lo que la pantalla de detalle ya asumía con su bloque "En mi colección".
- Permite registrar una carta del catálogo que **no** posees (una `card` sin
  `collection_items`), lo que deja abierta la póliza de B4 sin trabajo adicional.
- El histórico de precios es posible por construcción.

**En contra, y asumido**

- La ficha completa cruza cinco o seis tablas. Es el precio de no tener campos vacíos ni
  datos repetidos.
- La migración se complica: hay que crear una impresión por combinación única de carta,
  set, número, rareza, edición e idioma, y un `collection_item` por fila original. Los 151
  duplicados exactos quedan sin fusionar hasta decidir qué son (ADR-006).
- Aparece una ambigüedad que hay que resolver explícitamente: `quantity` cuenta **todas**
  las copias poseídas de esa impresión, mientras que el hueco localiza solo la que está
  archivada en la carpeta. De ahí que una fila con hueco 4 y cantidad 3 sea correcta, y
  que la estantería no pueda contar cartas con `SUM(quantity)`.
